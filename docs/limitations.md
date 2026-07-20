# Limitations

`cmd-dispatch` is a thin file-based foreman, not a live multi-agent runtime. Current limitations are:

- No live-session attach. Workers run through headless `codex exec`, not an interactive Codex session.
- No mid-run steering channel. To change direction, stop/clean the job and start a new one with different instructions or a different model.
- Conflicts surface at merge/review time. Per-issue worktrees isolate workers while they run, but they do not prevent later Git conflicts between branches.
- No `dispatch merge` command. The current landing command is `dispatch pr`, which pushes a branch and opens a PR after foreman review.
- No `dispatch watch` command. Progress checks are explicit with `dispatch status` or `dispatch logs <issue#> -f`.
- Single-foreman, file-based state. `.dispatch/` is local state in the target repository, with no locking, database, server, or coordination protocol for multiple foremen.
- One job directory per issue. Re-running an issue requires `dispatch clean <issue#>` before another `dispatch start`.
- `dispatch logs` reads stderr only. Structured worker events are in `events.jsonl`, while human logs are in `worker.log`.
