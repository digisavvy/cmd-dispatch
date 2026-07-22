# Working with dispatch

`dispatch` is a conversational foreman for headless coding workers. The foreman assigns one GitHub
issue to one worker in an isolated worktree. The worker commits its result, then a human foreman or
the opt-in headless gate reviews it before a pull request is opened.

The operating model is:

```text
foreman -> worker in an issue worktree -> review gate -> pull request
```

## Conventions

- Run `dispatch` from inside the target repository, the repository whose issues are being worked.
- Keep one job per issue. To redo a job, use `dispatch clean <n>` before starting it again.
- Treat `<target-repo>/.dispatch/` as dispatch-owned job state.
- Workers commit on `dispatch/issue-<n>`, but never push or open a pull request.
- Review a completed worker's commit before opening a pull request. `dispatch gate` is an optional
  headless review, not an auto-merge path.
- Never merge automatically. `dispatch pr` and an approved gate only push and open a pull request.
- Do not fabricate commands, flags, model names, results, or repository facts. Check `bin/dispatch`
  when documenting CLI behavior and use `[VERIFY]` when a fact cannot be confirmed.

## Driving a job

```sh
dispatch models                 # list configured aliases and resolved models
dispatch start 41 5.6           # start one worker
dispatch status 41              # inspect its state
dispatch wait 41                # wait for it to finish
dispatch gate 41                # optional review of a DONE job
dispatch pr 41                  # after review, push and open a PR
```

The normal merge gate is the foreman's review. To opt into a headless gate, use
`dispatch start <n> <model> --gate [--gate-model <alias>]` or run
`dispatch gate <n> [--gate-model <alias>]` after the job is `DONE`.
