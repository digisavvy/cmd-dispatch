# Merge gate

The headless merge gate is opt-in. It reviews everything a completed worker committed and either
opens a pull request or holds the job. It never merges.

Run it for an existing job:

```sh
dispatch gate <issue#> [--gate-model <alias>]
```

Or request it when starting a worker:

```sh
dispatch start <issue#> <model> --gate [--gate-model <alias>]
```

Both forms use the `opus` alias unless `--gate-model` selects another configured alias.
`dispatch start` rejects `--gate-model` without `--gate`. Its generated runner starts the gate in
the background only after the worker exits successfully.

## What it checks

The gate requires the job state to be `DONE` and reviews every commit the worker made — the range
`base_sha..HEAD`, where `base_sha` is recorded in `.dispatch/jobs/<issue#>/meta` when the worktree is
created — against the GitHub issue and worker final message. A job whose `base_sha` still equals
`HEAD` produced no commits and is rejected without running the reviewer. Jobs started before
`base_sha` was recorded fall back to `HEAD~1`, and the report says so. Before running the reviewer,
it applies `php -l` to each changed, existing PHP file. A PHP lint failure rejects immediately
without running the reviewer. Added `[VERIFY]` and `TODO` lines are also included in the review
prompt and saved report.

After PHP lint, the gate runs an optional repository verification hook. An executable
`.dispatch/verify.sh` in the main checkout takes precedence; otherwise, the gate runs
`$DISPATCH_VERIFY_CMD` through Bash when that variable is set. The hook runs with the worker
worktree as its current directory, under a default 600-second timeout configurable with
`DISPATCH_VERIFY_TIMEOUT`, and receives `DISPATCH_BASE_SHA` and `DISPATCH_ISSUE` in its environment.
A non-zero exit rejects immediately, saves the hook output verbatim in `gate.md`, and skips the
reviewer. With no configured hook, `gate.md` explicitly reports `Verify hook: none configured`.

The reviewer must emit a complete line exactly matching one of:

```text
VERDICT: APPROVE
VERDICT: REJECT
```

A missing or malformed verdict, reviewer error, PHP lint failure, or verification-hook failure is
a rejection.

The reviewer call runs under `timeout "${DISPATCH_GATE_TIMEOUT:-900}"`, so a wedged reviewer
becomes a rejection instead of a silent hang. The review prompt is hardened against two known
failure modes: the issue body is wrapped in `<untrusted-issue-body>` tags so hostile issue text
cannot instruct the reviewer, and the worker's final message appears last, labeled an unverified
claim, so the maker's self-assessment cannot prime the checker.

## Outcomes

- `APPROVE` runs `dispatch pr <issue#>`, which pushes the worker branch and opens a pull request.
  It does not merge the pull request.
- `REJECT` holds the job, writes the full report to `.dispatch/jobs/<issue#>/gate.md`, and posts
  that report as a GitHub issue comment — unless the job has a rework attempt left (below).

The report is written for both outcomes, and both outcomes send a notification (see
[notifications.md](notifications.md)): `APPROVE` includes the PR URL, `REJECT` points at the
report. A job must already be `DONE`; `RUNNING`, `STALLED`, `FAILED(code)`, and `KILLED` jobs are
refused.

## Bounded rework

A rejection can be sent back to the same worker instead of held, once per remaining attempt:

```sh
dispatch start <issue#> <model> --gate --max-attempts 2
dispatch rework <issue#> [--gate-model <alias>]
```

`--max-attempts` defaults to `1` — no rework, exactly the behavior above — accepts at most `3`, and
requires `--gate`. `meta` tracks `attempt` and `max_attempts`, and gate ledger lines carry
`attempt=<n>`.

When the gate rejects a job that opted in and still has an attempt left, it appends
`<ts> rework issue=<n> attempt=<m>` to the ledger, notifies `REWORK`, and re-runs the same worker in
the same worktree. On the last attempt it holds, comments, and notifies exactly as it always has.

Each round:

- `gate.md`, `last_message.txt`, `events.jsonl`, `worker.log`, and `exitcode` move to
  `.dispatch/jobs/<issue#>/attempts/<attempt>/` before the rerun overwrites them
- `prompt.txt` is rebuilt as `prompt.base.txt` plus the rejection report wrapped in
  `<untrusted-review-feedback>` tags, so feedback never stacks across rounds
- the worker is told to address every finding, keep the same scope rules, fix forward in a new
  commit (no amend, rebase, or force-push), and to stop and say so if a finding is wrong

`dispatch rework <issue#>` is the manual entry point to the same machinery. It requires a job that
is `DONE`, has its worktree, has a `gate.md` containing `VERDICT: REJECT`, and has
`attempt < max_attempts`; `--gate-model` changes the reviewer for the next round. A job with
`max_attempts=1` — including every job started before rework existed — can never enter rework.
Rework after `FAILED` is not supported: a crashed worker has no gate report to feed back.
