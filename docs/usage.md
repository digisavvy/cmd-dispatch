# Usage

`dispatch` is a small Bash CLI plus a Claude Code slash command for assigning headless Codex or Claude workers to GitHub issues. Run it from the target repository unless a command documents `-R <repo>`.

## Install

Install the Codex CLI and log in first:

```sh
npm i -g @openai/codex
codex login
```

Install `dispatch` from this repository:

```sh
./install.sh
```

The installer:

- symlinks `bin/dispatch` to `${DISPATCH_BIN_DIR:-$HOME/.local/bin}/dispatch`
- symlinks `commands/dispatch.md` to `${DISPATCH_CMD_DIR:-$HOME/.claude/commands}/dispatch.md`
- copies `models.conf.example` to `models.conf` if `models.conf` does not already exist

If the installer reports that `~/.local/bin` is not on `PATH`, add it to your shell config:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Then verify the local setup:

```sh
dispatch doctor
```

## CLI

### `dispatch doctor`

Checks core dependencies, reports Codex, Claude, and Gemini paths/versions in a Providers section, and lists configured aliases.

```sh
dispatch doctor
```

### `dispatch start <issue#> <model> [-R repo] [--gate] [--gate-model alias] [--max-attempts N]`

Starts one worker for one GitHub issue. `dispatch` fetches the issue title/body with `gh issue view`, creates a worktree at `../<repo>-wt-issue-<n>`, creates branch `dispatch/issue-<n>`, writes job state under `.dispatch/jobs/<n>/`, and launches the selected provider CLI with `nohup`.

`<model>` is normally an alias from `models.conf`; its value selects the provider. Start errors before creating a worktree if that provider CLI is missing. Raw `gpt-*`, `claude-*`, and `gemini-*` slugs are also inferable.

```sh
dispatch start 41 5.6
dispatch start 52 mini
dispatch start 57 gpt-5.6-terra
dispatch start 41 5.6 -R /path/to/target-repo
dispatch start 42 5.6 --gate --gate-model opus
dispatch start 43 5.6 --gate --max-attempts 2
```

Only one job directory may exist per issue. To redo an issue, stop or clean the existing job first.
The automatic merge gate is off by default. `--gate` runs it in the background after a successful
worker exit. `--gate-model` selects its model alias and defaults to `opus`; it is only valid with
`--gate`.

`--max-attempts` bounds automatic rework on a gate rejection. It defaults to `1` (reject holds the
job, as before), accepts at most `3`, and is only valid with `--gate`. With a higher value, a
rejection re-runs the same worker with the gate's findings appended to its prompt; the last attempt
holds and comments as usual. See [gate.md](gate.md).

### `dispatch usage [--json] [--probe|--live]`

Shows each configured provider's subscription usage as a terminal bar, including every limit window
the provider reports and the time until reset. `--json` emits normalized records for scripts.

```sh
dispatch usage
dispatch usage --json
dispatch usage --probe
```

Codex usage comes from the newest local `~/.codex/sessions/**/rollout-*.jsonl` session: observed
`token_count` events include the server-provided `rate_limits.primary` and optional `secondary`
snapshots (`used_percent`, `window_minutes`, and `resets_at`). This is the last recorded snapshot,
not a network refresh; running Codex updates it. Set `DISPATCH_CODEX_SESSIONS_DIR` to override that
location (primarily useful for fixtures).

Claude does not persist subscription-window utilization. By default its row therefore displays
`n/a`. Pass `--probe` (or `--live`) to spend one Claude API call and show the live five-hour status
and reset time; Claude does not report a numeric used percentage, so its bar remains `n/a`.
Providers without observed usage data degrade the same way.

### `dispatch report [--since YYYY-MM-DD] [-R repo]`

Reads the append-only `.dispatch/ledger.log` and reports workers dispatched, gate approvals, and
accept rate per worker model alias. `--since` includes ledger events on or after the given UTC date.
The command creates no state files.

```sh
dispatch report
dispatch report --since 2026-07-01
dispatch report -R /path/to/target-repo
```

If workers have been dispatched but no gate verdicts have been recorded, each alias is still shown
with zero approvals and a zero percent accept rate.

### `dispatch status [issue#] [--stale-after seconds]`

Shows all jobs, or one job, with state and the latest parsed event or final worker message.

```sh
dispatch status
dispatch status 41
dispatch status 41 --stale-after 600
```

States are:

- `RUNNING` when the recorded pid is alive and no exit code exists
- `STALLED` when a running job's newest event is at least five minutes old
- `DONE` when `exitcode` exists and is `0`
- `FAILED(code)` when `exitcode` exists and is nonzero
- `KILLED` when `exitcode` is `killed` (written by `dispatch stop`), or when there is no exit code and the recorded pid is not alive

For a single issue, status also prints the worktree path. `STALLED` is a heuristic, not a failure; some legitimate tasks are quiet during a long tool call. Use `--stale-after` to change the threshold in seconds.

### `dispatch wait <issue#>|--any [--status done|any|stalled] [--stale-after seconds] [--timeout seconds] [--interval seconds]`

Waits for one job to reach a terminal state. By default it waits indefinitely, checks every five seconds, prints the final status row, and exits `0` for `DONE` or with the worker's exit code for `FAILED`; `KILLED` exits nonzero. `--status done` also treats every non-`DONE` result as failure. `--status stalled` additionally wakes with exit code `0` when the job is heuristically `STALLED`; `--stale-after` changes the default 300-second threshold. A timeout exits `124`.

With `--any`, the command watches all jobs that are active when it starts and returns when the first one finishes, printing its issue number.

```sh
dispatch wait 41
dispatch wait 41 --status done --timeout 600 --interval 2
dispatch wait 41 --status stalled --stale-after 600
dispatch wait --any
```

### `dispatch logs <issue#> [-f] [--raw|--events]`

Without options, prints the last 40 lines of `.dispatch/jobs/<n>/worker.log`, preserving the original stderr-only behavior. With `-f`, it interleaves stderr progress with a provider-aware rendered view of structured events so active workers do not appear idle.

```sh
dispatch logs 41
dispatch logs 41 -f
dispatch logs 41 -f --raw
dispatch logs 41 --events
```

`--raw` selects stderr only. `--events` selects rendered events only and can also be combined with `-f`.

### `dispatch stop <issue#>`

Kills a running worker process, writes `killed` to `exitcode` (the job then reports `KILLED`), appends a stop entry to `.dispatch/ledger.log`, and keeps the worktree.

```sh
dispatch stop 52
```

To reassign the issue after stopping it:

```sh
dispatch clean 52
dispatch start 52 5.6
```

### `dispatch pr <issue#>`

Pushes the worker branch and opens a GitHub PR with `gh pr create --fill`. The PR body includes `Closes #<n>` and the resolved model.

```sh
dispatch pr 41
```

Run this only after the foreman has reviewed the worker's commit. The command refuses to continue if tracked files in the worktree have unstaged or staged changes. Untracked files do not block it.

### `dispatch gate <issue#> [--gate-model alias]`

Runs a strict headless review of a `DONE` job using `opus` by default. It gathers the issue, worker
message, and committed diff, checks changed PHP files with `php -l`, and flags added `[VERIFY]` and
`TODO` markers. After lint, it runs the executable `.dispatch/verify.sh` from the main checkout, or
`$DISPATCH_VERIFY_CMD` when no executable script exists. The hook runs from the worker worktree
with `DISPATCH_BASE_SHA` and `DISPATCH_ISSUE` set and a default 600-second timeout, configurable
with `DISPATCH_VERIFY_TIMEOUT`. Full findings are saved to `.dispatch/jobs/<n>/gate.md`.

An approval calls `dispatch pr`, which pushes and opens a PR but does not merge it. A rejection or
objective-check failure holds the job and posts the findings as an issue comment.

```sh
dispatch gate 41
dispatch gate 41 --gate-model 5.6
```

### `dispatch rework <issue#> [--gate-model alias] [-R repo]`

Re-runs the same worker in the same worktree with the gate's rejection findings appended to its
prompt, then re-gates it. This is the manual entry point to the bounded rework loop that
`--max-attempts` runs automatically.

```sh
dispatch rework 41
dispatch rework 41 --gate-model 5.6
```

It refuses unless the job exists, is `DONE`, still has its worktree, has a `gate.md` containing
`VERDICT: REJECT`, and has `attempt < max_attempts` in `meta`. Jobs started without
`--max-attempts` greater than `1` therefore never rework. The previous round's `gate.md`,
`last_message.txt`, `events.jsonl`, `worker.log`, and `exitcode` are archived under
`.dispatch/jobs/<n>/attempts/<attempt>/`, and `--gate-model` changes the reviewer for the next
round. See [gate.md](gate.md).

### `dispatch clean <issue#> [--force]`

Stops the recorded pid if present, force-removes the worktree, prunes stale worktree metadata,
deletes the local branch, archives the job's review record, appends a clean entry to
`.dispatch/ledger.log`, and removes `.dispatch/jobs/<n>/`.

```sh
dispatch clean 52
```

This is the reset path for reassigning or starting over on an issue.

Because deleting the branch is a force delete, `clean` first checks whether the branch holds commits
that exist on no other branch, remote-tracking ref, or tag. If it does, and the job never reached
`dispatch pr`, the clean is refused — those commits are the worker's only output and would survive
only in the reflog:

```text
dispatch: issue #52 has 2 commit(s) on dispatch/issue-52 that exist on no other branch, remote, or tag.
Cleaning would discard them (recoverable from the reflog only).
  keep them:     dispatch pr 52          (push the branch and open a PR)
  discard them:  dispatch clean 52 --force
```

Cleaning after a PR or a merge is unaffected and stays silent: the commits are on `origin/<branch>`
and on the base branch, and a job with a recorded `pr_url` is exempt from the check even if the PR
was squash-merged and its remote-tracking ref has since been pruned. Use `--force` for the
intentional discard — a throwaway experiment, or a worker whose output is not worth a PR. The ledger
records the count either way as `unmerged=<n>`.

The archive is a copy of the small text artifacts under `.dispatch/archive/<n>-<utc-ts>/`, so a
post-mortem survives the cleanup:

| Archived | Dropped |
|---|---|
| `meta`, `gate.md`, `last_message.txt`, `prompt.base.txt` | `events.jsonl`, `worker.log` |
| `attempts/<k>/gate.md`, `attempts/<k>/last_message.txt` | `attempts/<k>/events.jsonl`, `attempts/<k>/worker.log` |
| | `run.sh`, `pid`, `exitcode`, `prompt.txt` |

The dropped set is the unbounded provider stream and the reproducible scaffolding; keeping it is the
failure mode described in [event-log-research.md](event-log-research.md). Each `clean` also prunes the
oldest archives beyond a fixed cap, so `.dispatch/archive/` stays bounded without a separate command.

- **`DISPATCH_ARCHIVE=off`** skips archiving entirely (delete-only, the pre-archive behaviour). The
  ledger still records the clean, with `archived=none`.
- **`DISPATCH_ARCHIVE_KEEP`** sets the retention cap; default `50` job archives.

```sh
DISPATCH_ARCHIVE=off dispatch clean 52
DISPATCH_ARCHIVE_KEEP=10 dispatch clean 52
```

### `dispatch notify <issue#> <state> [next-action...] [-R repo]`

Pushes a human notification for a job that reached an attention state. The generated `run.sh`
calls this automatically right after writing `exitcode` — you normally never run it by hand,
but it is also the integration point for anything that detects attention states itself (the
STALLED detector from issue #13 calls it with `STALLED`; the auto-gate from issue #15 passes
its verdict as the message).

```sh
dispatch notify 41 DONE
dispatch notify 52 FAILED\(1\)
dispatch notify 41 DONE "gate APPROVED — PR #45 open"
```

The banner front-loads the signal so the three questions — which job, what outcome, what now —
are answerable at a glance:

```text
#<n> <state> · <repo>     title
<alias or model>          subtitle
<action>                  message
```

With no explicit `next-action`, a default is chosen per state: `DONE` → `Review & merge:
dispatch pr <n>`; `FAILED(code)` → `Worker errored — inspect: dispatch logs <n>`; `STALLED` →
`May be stuck / awaiting something — check: dispatch logs <n> -f`.

Channels (all best-effort, never blocking):

- **Terminal bell** on the controlling terminal, if the session still has one.
- **macOS banner** on Darwin: `terminal-notifier` when installed, `osascript` otherwise. Banners are
  grouped per job, so a later round replaces the earlier banner instead of stacking.
- **`DISPATCH_NOTIFY_CMD`** — when set to one trusted local executable, it runs with the headline as args
  (`<issue#> <state> <headline>`, where the headline is `#<n> <state> · <repo> — <action>`) and the
  full job context in env:

  | Env var | Value |
  |---|---|
  | `DISPATCH_ISSUE` | issue number |
  | `DISPATCH_STATE` | `DONE`, `FAILED(code)`, `STALLED`, ... |
  | `DISPATCH_PROVIDER` / `DISPATCH_MODEL` | resolved worker identity |
  | `DISPATCH_REPO` / `DISPATCH_REPO_ROOT` | repo name / absolute path |
  | `DISPATCH_NEXT_ACTION` | the human next step |
  | `DISPATCH_PR_URL` | PR url when a gate opened one (empty otherwise) |
  | `DISPATCH_MESSAGE` | the one-line headline |

  Keep the hook fast — it runs synchronously, after the exit code is on disk. Use a wrapper script
  when fixed command-line flags are needed, and treat all arguments and environment values as
  untrusted data.
- **`DISPATCH_NOTIFY=off`** disables every channel.

## `/dispatch` Slash Command

`install.sh` installs `commands/dispatch.md` as the Claude Code `/dispatch` command. The slash command tells the lead agent to parse natural-language assignments and call the CLI.

Examples:

```text
/dispatch put 5.6 on #41, 5.5 on #52 and #57
/dispatch 5.6:41 5.5:52 5.5:57
/dispatch #41 #52 #57
```

When an issue has no explicit model, the command instructs the lead agent to present a picker instead of guessing. The picker choices are aliases that should exist in `models.conf`:

- `5.6` - 5.6 Sol, frontier
- `5.6-terra` - 5.6 Terra, balanced
- `5.6-luna` - 5.6 Luna, fast/cheap
- `5.5` - frontier prior generation
- `mini` - 5.4 Mini, cheapest

Inline assignments win. For example, `/dispatch put 5.6 on #41 and pick for #52` should not re-ask for issue 41.

## `models.conf`

By default, `dispatch` reads `models.conf` next to the repository's `bin/` directory. Set `DISPATCH_MODELS_CONF` to use another file:

```sh
DISPATCH_MODELS_CONF=/path/to/models.conf dispatch start 41 5.6
```

The format is:

```conf
alias = provider exact-model-string
```

The example file defines:

```conf
5.6       = codex gpt-5.6-sol
5.5       = codex gpt-5.5
5.4       = codex gpt-5.4
mini      = codex gpt-5.4-mini
default   = codex gpt-5.6-terra
5.6-sol   = codex gpt-5.6-sol
5.6-terra = codex gpt-5.6-terra
5.6-luna  = codex gpt-5.6-luna
sonnet    = claude sonnet
opus      = claude opus
haiku     = claude haiku
```

Model resolution treats the first value token as provider and the remainder as model. Unmatched strings error unless their provider can be inferred from the raw slug.

Use `dispatch doctor` after Codex upgrades to check the currently available model strings and update `models.conf`.
