# Architecture

`cmd-dispatch` is intentionally file-based. The CLI creates one isolated Git worktree per GitHub issue, starts one headless Codex worker inside that worktree, and records enough state under `.dispatch/` for the foreman to check progress later.

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

The shell pid from the background `nohup bash "$jobdir/run.sh"` process is written to `pid`. When `codex exec` exits, `run.sh` writes the exit code to `exitcode`.

## Event Streams

`codex exec --json` writes structured events to stdout and human progress to stderr. Dispatch keeps those streams separate:

- `events.jsonl` is stdout JSONL for status parsing and future tooling
- `worker.log` is stderr for `dispatch logs`
- `last_message.txt` is written by `codex exec -o` and used by `dispatch status` after a worker finishes

`dispatch status` parses the latest JSON object in `events.jsonl` with `jq` when available. It summarizes agent messages, command executions, file changes, and turn completion. See [codex-events.md](codex-events.md) for the event vocabulary currently documented for this project.

## State Layout

State lives in the target repository:

```text
.dispatch/
  ledger.log
  jobs/
    <n>/
      meta
      prompt.txt
      run.sh
      pid
      exitcode
      events.jsonl
      worker.log
      last_message.txt
```

`meta` stores simple `key=value` fields:

```text
issue=<n>
alias=<requested alias>
model=<resolved model>
branch=dispatch/issue-<n>
worktree=<absolute worktree path>
started_at=<UTC timestamp>
```

`exitcode` is absent while the process is running. A value of `0` means `DONE`; any nonzero value means `FAILED(code)`. `dispatch stop` writes `killed`, which appears as `FAILED(killed)` because the state logic treats only `0` as done.

## Merge Gate

Workers commit in their worktrees but never push and never open PRs. The foreman remains the merge gate:

1. Check `dispatch status <n>` and inspect the worker's worktree.
2. Review the diff and run tests/builds if needed.
3. Run `dispatch pr <n>` only after review.

`dispatch pr` refuses to proceed when tracked files have staged or unstaged changes, then pushes `dispatch/issue-<n>` and runs `gh pr create --fill --head "$branch"` with a body that closes the issue.

There is no automatic merge path in the current implementation.
