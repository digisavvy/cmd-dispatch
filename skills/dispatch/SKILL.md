---
name: dispatch
description: Use when the user wants to delegate GitHub issues to coding-agent workers — "dispatch", "put <model> on #N", "have codex/claude fix this issue", spawning multiple workers, or checking on dispatched work. Covers the `dispatch` CLI and the `/dispatch` and `/pick` commands.
---

# Dispatch: conversational agent foreman

`dispatch` (repo: `github.com/digisavvy/cmd-dispatch`, CLI on PATH) turns Claude Code into a **foreman**
that spawns headless coding-agent **workers** — one per GitHub issue, each in its own git worktree/branch.
Workers commit but never push; **the foreman reviews before anything merges.** You are the merge gate.

## When to use it

Use dispatch when the user wants to hand issues to workers and keep steering conversationally
("put 5.6 on #41, sonnet on #42", "spin up a worker on the auth bug", "how's #52 doing").
Don't use it for a change you should just make directly, or for non-code issues (marketing, ops).

## The loop

1. **Run from inside the target repo** (the one with the issues) — it needs a local git clone.
2. **Dispatch:** `dispatch start <issue#> <alias>` (or `/dispatch put 5.6 on #41, sonnet on #42`).
3. **Watch:** `dispatch status` · `dispatch wait <n>` (blocks until done) · `dispatch logs <n> -f --events`.
4. **Review (merge gate):** read the diff in the worktree + the worker's final message.
5. **Land:** `dispatch pr <n>` (pushes branch, opens PR). Never PR a FAILED job or unreviewed work.
6. **Steer/tidy:** `dispatch stop <n>` · reassign = `dispatch clean <n> && dispatch start <n> <alias>`.

## Models (alias carries provider)

Aliases live in `models.conf` as `<alias> = <provider> <model>`; the user just says the alias.
`dispatch models` lists them. Curated set:

| | Best | Balanced | Fast |
|---|---|---|---|
| **Codex** | `5.6` | `5.6-terra` | `5.6-luna` |
| **Claude** | `opus` | `sonnet` | `haiku` |
| **Kimi** | `kimi` (k3) | `kimi-code` (k2.7-code) | `kimi-fast` |

If the user doesn't name a model, use **`/pick`** (or `/dispatch #N` with no model) — it shows a
provider→tier menu and dispatches the choice, so no aliases need memorizing. `dispatch doctor`
shows which provider CLIs are installed.

## Other commands

- `dispatch usage [--probe]` — subscription usage % + reset windows (codex live; claude reset via `--probe`).
- `dispatch wait --any` — block until any active job finishes.
- `dispatch logs <n> --events` — rendered event stream (not just stderr).
- Jobs ping the human on `DONE`/`FAILED` automatically (terminal bell + macOS banner, after the
  exit code lands). `DISPATCH_NOTIFY_CMD` routes the ping to Slack/ntfy/etc.; `DISPATCH_NOTIFY=off`
  silences it. When a notification says "Next: review & merge", do the review step below.

## Rules of thumb

- **Report failures/blockers first.** Surface a stuck or FAILED worker before wins.
- **One job per issue.** Redo = `clean` then `start`.
- **Never invent model strings** — only aliases from `dispatch models`.
- Workers run non-interactively in isolated worktrees; you cannot steer one mid-run — kill and re-dispatch.
- State lives in `<repo>/.dispatch/`; it survives crashes and new sessions.

## Gotchas baked into the tool (don't re-solve)

- Codex workers need `--add-dir <git-common-dir>` to commit inside a worktree (already handled).
- Claude workers need `--verbose` with `--output-format stream-json` (already handled).
- Worker stdout (JSONL events) and stderr split into `events.jsonl` / `worker.log`.

See the repo's `docs/` (getting-started, usage, architecture, limitations) or the
[wiki](https://github.com/digisavvy/cmd-dispatch/wiki) for depth.
