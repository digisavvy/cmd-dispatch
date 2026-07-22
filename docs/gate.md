# Merge gate

The headless merge gate is opt-in. It reviews one completed worker commit and either opens a pull
request or holds the job. It never merges.

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

The gate requires the job state to be `DONE` and reviews the job's `HEAD` commit against the GitHub
issue and worker final message. Before running the reviewer, it applies `php -l` to each changed,
existing PHP file. A PHP lint failure rejects immediately without running the reviewer. Added
`[VERIFY]` and `TODO` lines are also included in the review prompt and saved report.

The reviewer must emit a complete line exactly matching one of:

```text
VERDICT: APPROVE
VERDICT: REJECT
```

A missing or malformed verdict, reviewer error, or PHP lint failure is a rejection.

## Outcomes

- `APPROVE` runs `dispatch pr <issue#>`, which pushes the worker branch and opens a pull request.
  It does not merge the pull request.
- `REJECT` holds the job, writes the full report to `.dispatch/jobs/<issue#>/gate.md`, and posts
  that report as a GitHub issue comment.

The report is written for both outcomes. A job must already be `DONE`; `RUNNING`, `STALLED`,
`FAILED(code)`, and `KILLED` jobs are refused.
