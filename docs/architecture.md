# Architecture

`cmd-dispatch` is intentionally file-based. The CLI creates one isolated Git worktree per GitHub issue, starts one headless Codex or Claude worker inside that worktree, and records enough state under `.dispatch/` for the foreman to check progress later.

## Worktree Isolation

`dispatch start <issue#> <model>` resolves the target repository, fetches the issue with `gh issue view`, and creates:

- branch `dispatch/issue-<n>`
- worktree `../<repo>-wt-issue-<n>`
- job directory `<target-repo>/.dispatch/jobs/<n>/`

Each worker receives a generated prompt that includes the issue title/body and rules requiring it to stay on `dispatch/issue-<n>`, avoid unrelated edits, run available tests/builds, commit its work, and not push or open a PR.

## Headless Workers

Workers are launched by a generated per-job `run.sh` script under `nohup`:

```sh
codex exec -C "$worktree" -m "$model" --sandbox workspace-write --add-dir "$gitcommon" --json \
  -o "$jobdir/last_message.txt" "$(cat "$jobdir/prompt.txt")" \
  > "$jobdir/events.jsonl" 2> "$jobdir/worker.log"
```

The `--add-dir` path points at the repository's Git common directory so the worker can commit from a linked worktree while running in the workspace-write sandbox.

Claude runs with the worktree as cwd, stream JSON, `--add-dir "$gitcommon"`, and `--dangerously-skip-permissions`; the isolated worktree and foreman review provide the same trust boundary. Gemini has an unverified runner template only.

The shell pid from the background `nohup bash "$jobdir/run.sh"` process is written to `pid`. When `codex exec` exits, `run.sh` writes the exit code to `exitcode`, then appends a `finish` line to the ledger and calls `dispatch notify <n> <state> -R <repo>` through the resolved dispatch bin. Both are additive and fire only after `exitcode` is on disk, so a wedged append or notification channel can never block the worker or the foreman's polling loop. The notification (terminal bell, macOS banner, optional `DISPATCH_NOTIFY_CMD` hook) is described in [usage.md](usage.md). `dispatch stop` writes the `killed` sentinel to `exitcode` and logs its own `stop` line, so a stopped job never also reports `finish`.

## Event Streams

`codex exec --json` writes structured events to stdout and human progress to stderr. Dispatch keeps those streams separate:

- `events.jsonl` is stdout JSONL for status parsing and future tooling
- `worker.log` is stderr for `dispatch logs`
- `last_message.txt` is written by `codex exec -o` and used by `dispatch status` after a worker finishes

`dispatch status` reads the provider from `meta`, then parses the latest JSON object with `jq`. Codex keeps its `item.*` summaries; Claude summarizes assistant text, tool use, and result records. Gemini and unknown providers fall back to the last raw line. See [codex-events.md](codex-events.md) and [claude-events.md](claude-events.md).

## State Layout

State lives in the target repository:

```text
.dispatch/
  ledger.log
  archive/
    <n>-<utc-ts>/            (review record kept by `dispatch clean`; see usage.md)
  jobs/
    <n>/
      meta
      prompt.base.txt
      prompt.txt
      run.sh
      pid
      exitcode
      events.jsonl
      worker.log
      last_message.txt
      gate.md
      attempts/<attempt>/        (archived rework rounds; see gate.md)
```

`meta` stores simple `key=value` fields:

```text
issue=<n>
title=<issue title, whitespace-collapsed and truncated to 45 chars>
alias=<requested alias>
provider=<codex|claude|gemini>
model=<resolved model>
branch=dispatch/issue-<n>
worktree=<absolute worktree path>
base_sha=<commit the worker starts from>
gate=<0|1>
gate_model=<gate model alias>
attempt=<current attempt, from 1>
max_attempts=<rework ceiling, 1-3>
started_at=<UTC timestamp>
```

Fields that change after the job starts (`attempt`, `gate_model`) are rewritten in place through a
temp file: a read takes the first matching line, so appending would leave the stale value winning.

`title` is the one untrusted, issue-derived field. `dispatch start` collapses its whitespace before
writing, so an embedded newline cannot forge a second record; it is read back only as banner display
text. See [notifications.md](notifications.md).

`prompt.base.txt` is the pristine generated prompt. `prompt.txt` is what the worker reads: identical
to the base on the first attempt, and rebuilt as base plus the latest rejection report on each
rework round, so feedback never stacks. See [gate.md](gate.md).

`exitcode` is absent while the process is running. A value of `0` means `DONE`; any other numeric value means `FAILED(code)`. `dispatch stop` writes the sentinel `killed`, which reports as `KILLED`.

### Ledger

`ledger.log` is append-only: nothing in `dispatch` rewrites or truncates it. One event per line, in a
fixed `<ts> <verb> issue=<n> k=v…` grammar:

```text
<ts> start  issue=<n> alias=<a> provider=<p> model=<m> pid=<pid>
<ts> stop   issue=<n> pid=<pid>
<ts> gate   issue=<n> verdict=<APPROVE|REJECT> alias=<a> gate_model=<g> [attempt=<k>]
<ts> rework issue=<n> attempt=<k>
<ts> pr     issue=<n> branch=<branch>
<ts> finish issue=<n> state=<DONE|FAILED> exit=<code> attempt=<k>
<ts> clean  issue=<n> branch=<branch> archived=<path relative to the repo root|none>
```

Every writer appends one short line with a single `echo` and no locking. That is safe because an
append to a regular file is atomic per `write(2)`, and bash's builtin `echo` issues one write below
roughly 1 KB — a longer line tears when jobs run in parallel. Findings, diffs, and JSON payloads
therefore never belong on a ledger line; they live in the job directory. See
[event-log-research.md](event-log-research.md) for the measurements behind that bound.

`dispatch report` is a pure `awk` projection over this file. It keys on the verb and skips unknown
verbs and unknown `k=v` fields, so a new verb needs no migration and ledgers written before a verb
existed stay readable. Consumers of `finish` must read its absence as "unknown", not as "did not
finish".

## Merge Gate

Workers commit in their worktrees but never push and never open PRs. The foreman remains the merge gate:

1. Check `dispatch status <n>` and inspect the worker's worktree.
2. Review the diff and run tests/builds if needed.
3. Run `dispatch pr <n>` only after review.

`dispatch pr` refuses to proceed when tracked files have staged or unstaged changes, then pushes `dispatch/issue-<n>` and runs `gh pr create --fill --head "$branch"` with a body that closes the issue.

There is no automatic merge path in the current implementation.
