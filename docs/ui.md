# The terminal UI (`dispatch ui`)

`dispatch ui` is an interactive monitor for dispatched workers: a live list of every job — which
model is on which issue, in what state — with a detail pane for the selected job and one keypress
(or mouse click) to drop into that worker's live output. It is the glanceable version of
`dispatch status` plus `dispatch logs -f`, for the moments when several workers are running and
you want to *watch* the fleet rather than poll it.

```text
┌ dispatch · my-project ──────────────────┬───────────────────────────────────────┐
│ enter/double-click: live logs · ctrl-s… │ #41 RUNNING  Handle empty input grace…│
│                                         │ worker  5.6 -> codex gpt-5.6-sol      │
│ > #41  RUNNING    5.6     gpt-5.6-sol … │ branch  dispatch/issue-41             │
│   #52  RUNNING    sonnet  sonnet      … │ tree    ../my-project-wt-issue-41     │
│   #57  DONE       kimi    kimi-k3     … │ ── commits ──────────────             │
│   #33  FAILED(1)  5.6     gpt-5.6-sol … │ ba7e82f fix: handle empty input (#41) │
│                                         │ ── diff ─────────────────             │
│                                         │  src/input.php | 14 ++++++--          │
│                                         │ ── recent activity ──────             │
│                                         │ run: pytest -q (exit 0)               │
│                                         │ edit: modify input.php                │
│                                         │ msg: All tests pass, committing.      │
└─────────────────────────────────────────┴───────────────────────────────────────┘
```

## Use

```sh
dispatch ui                    # from inside the target repo
dispatch ui -R ~/code/my-project
dispatch ui --interval 5       # refresh every 5s instead of 2s
dispatch ui --stale-after 600  # same STALLED threshold flag as status/wait
```

- **List** — one row per job: issue, colored state (`RUNNING` green, `STALLED` yellow, `DONE`
  cyan, `FAILED` red, `KILLED` dim), alias, resolved model, attempt `k/n`, age, and the latest
  rendered event (or the final message once finished). Active jobs sort first.
- **Preview pane** — the selected job's drill-down: worker/gate/attempt metadata, the commits and
  diffstat produced so far (`base_sha..HEAD` in the worktree, the same range the gate reviews),
  recent activity rendered by the same per-provider event renderer `dispatch logs` uses, the gate
  verdict with its findings once `gate.md` exists, and the final message once the job ends.
- **Enter or double-click** — takes over the terminal with that worker's live log stream
  (`dispatch logs <n> -f`); `ctrl-c` returns to the list. fzf's mouse support is on by default,
  so a single click selects a row and updates the preview.
- **ctrl-s** — stop the selected worker (`dispatch stop`).
- **ctrl-g** — gate the selected job in the background (`nohup dispatch gate`), exactly like the
  `--gate` auto-gate: the verdict lands in `gate.md` (visible in the preview), the ledger, and a
  notification. Gating a job that is not `DONE` is silently refused by `dispatch gate` itself.
- **ctrl-p** — push the branch and open the PR (`dispatch pr`), in the foreground so the URL or
  refusal is readable; enter returns to the list.
- **ctrl-r** — manual refresh. **esc** / **ctrl-c** — quit.

The UI is read-mostly and stateless: it renders the same `.dispatch/` files `dispatch status`
reads, owns no behavior of its own (every action shells out to an existing subcommand), and can be
quit and reopened at any time without affecting workers.

## Requirements and degradation

`fzf` is the only new dependency, and only for this subcommand — `dispatch doctor` reports it as
optional. Live refresh needs fzf ≥ 0.36 (for `--listen`) and `curl`; on an older fzf or without
curl the UI still works, it just refreshes on `ctrl-r` instead of on a timer. The refresh timer
also restarts the preview command, so a preview you scrolled snaps back — pick a longer
`--interval` if that gets in the way while reading.

## How it works

One process, no daemon. `dispatch ui` renders the job list and hands it to `fzf`; every fzf
binding re-enters `bin/dispatch` through three internal helper modes:

- `dispatch ui --rows` prints the list (one tab-delimited line per job; the issue number rides in
  a hidden field that bindings reference as `{2}`). It is the `reload()` target.
- `dispatch ui --preview <n>` prints the detail pane for one job.
- `dispatch ui --watch` is the refresh pump. fzf is started with `--listen 0` (a random localhost
  port, guarded by a generated `FZF_API_KEY`), and a `start:` binding spawns the pump, which POSTs
  `reload(...)+refresh-preview` to `$FZF_PORT` every `--interval` seconds. The first failed POST
  means fzf is gone, so the pump exits with it — nothing to clean up.

All three take `-R`, so reload and preview render the correct repo regardless of the cwd fzf hands
them. `fzf` itself runs with the repo root as cwd, which is what lets the action bindings call
`dispatch logs/stop/gate/pr` unchanged (they resolve the repo from cwd).

## Why fzf (design notes)

The constraint, per the README: dispatch is deliberately not a framework — a small bash CLI whose
state is plain files. Options considered for the UI:

- **A curses-style TUI in another runtime** (Node/Ink, Go/bubbletea, Rust/ratatui) — the richest
  option, and the wrong one here: it adds a build/runtime dependency to a repo that is one bash
  file, and it would inevitably grow its own state and event loop.
- **`watch dispatch status` / tmux panes of `dispatch logs -f`** — zero new code but not
  interactive: no selection, no drill-down, no actions.
- **Pure-bash TUI** (tput, raw key reads) — no new dependency, but hundreds of lines of terminal
  handling (mouse reporting, resize, repaint) that fzf already does well.
- **fzf** (chosen) — already the de-facto terminal picker, one `brew install` most foremen have,
  mouse support by default, and its `--preview`/`reload`/`--listen` primitives map exactly onto
  "summary list, drill-down pane, live refresh". The UI stays a thin projection of on-disk state,
  which is the same bet the rest of dispatch makes.

The events groundwork was laid long before this command: workers write machine-parseable
`events.jsonl` separately from human `worker.log` precisely "so a TUI/status can parse clean
events" (see [architecture.md](architecture.md#event-streams)).
