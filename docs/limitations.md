# Limitations

`cmd-dispatch` is a thin file-based foreman, not a live multi-agent runtime. Current limitations are:

- No live-session attach. Workers run through headless `codex exec`, not an interactive Codex session.
- No mid-run steering channel. To change direction, stop/clean the job and start a new one with different instructions or a different model.
- Conflicts surface at merge/review time. Per-issue worktrees isolate workers while they run, but they do not prevent later Git conflicts between branches.
- No `dispatch merge` command. The current landing command is `dispatch pr`, which pushes a branch and opens a PR after foreman review.
- No full-screen `dispatch watch` dashboard. `dispatch wait` blocks for job completion, while `dispatch logs <issue#> -f` follows both rendered events and stderr progress.
- Single-foreman, file-based state. `.dispatch/` is local state in the target repository, with no locking, database, server, or coordination protocol for multiple foremen.
- One job directory per issue. Re-running an issue requires `dispatch clean <issue#>` before another `dispatch start`.
- Event rendering is intentionally concise. Use `dispatch logs <issue#> -f --raw` for stderr only; the underlying structured records remain in `events.jsonl`.
- Sandboxed claude workers have no Bash network egress. The claude worker and gate run under Claude Code's native sandbox with `network.allowedDomains` empty, so `Bash` commands cannot reach any host (Claude's own API runs in the parent process, outside the sandbox). Repositories whose tests or builds fetch from a package registry (`registry.npmjs.org`, PyPI, crates.io, etc.) during the run will fail. A per-job `allowedDomains` knob to opt those hosts in is **deferred** — for now, pre-install dependencies in the checkout before `dispatch start`, or vendor them. See `docs/isolation-research.md` for the sandbox model and its hostname-allowlist caveat.
