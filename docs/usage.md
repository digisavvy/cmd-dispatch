# Usage

`dispatch` is a small Bash CLI plus a Claude Code slash command for assigning headless Codex workers to GitHub issues. Run it from the target repository unless a command documents `-R <repo>`.

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

Checks for `git`, `gh`, `jq`, and `codex`, prints Codex model help when available, and lists configured aliases from `models.conf`.

```sh
dispatch doctor
```

### `dispatch start <issue#> <model> [-R repo]`

Starts one worker for one GitHub issue. `dispatch` fetches the issue title/body with `gh issue view`, creates a worktree at `../<repo>-wt-issue-<n>`, creates branch `dispatch/issue-<n>`, writes job state under `.dispatch/jobs/<n>/`, and launches `codex exec` with `nohup`.

`<model>` can be an alias from `models.conf` or a raw Codex model string.

```sh
dispatch start 41 5.6
dispatch start 52 mini
dispatch start 57 gpt-5.6-terra
dispatch start 41 5.6 -R /path/to/target-repo
```

Only one job directory may exist per issue. To redo an issue, stop or clean the existing job first.

### `dispatch status [issue#]`

Shows all jobs, or one job, with state and the latest parsed event or final worker message.

```sh
dispatch status
dispatch status 41
```

States are:

- `RUNNING` when the recorded pid is alive and no exit code exists
- `DONE` when `exitcode` exists and is `0`
- `FAILED(code)` when `exitcode` exists and is nonzero
- `KILLED` when there is no exit code and the recorded pid is not alive

For a single issue, status also prints the worktree path.

### `dispatch logs <issue#> [-f]`

Prints the last 40 lines of `.dispatch/jobs/<n>/worker.log`, or follows it with `-f`.

```sh
dispatch logs 41
dispatch logs 41 -f
```

This is the worker's stderr stream. Structured JSON events are stored separately in `events.jsonl`.

### `dispatch stop <issue#>`

Kills a running worker process, writes `killed` to `exitcode`, appends a stop entry to `.dispatch/ledger.log`, and keeps the worktree.

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

### `dispatch clean <issue#>`

Stops the recorded pid if present, force-removes the worktree, deletes the local branch, and removes `.dispatch/jobs/<n>/`.

```sh
dispatch clean 52
```

This is the reset path for reassigning or starting over on an issue.

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
alias = exact-codex-model-string
```

The example file defines:

```conf
5.6       = gpt-5.6-sol
5.5       = gpt-5.5
5.4       = gpt-5.4
mini      = gpt-5.4-mini
default   = gpt-5.6-terra
5.6-sol   = gpt-5.6-sol
5.6-terra = gpt-5.6-terra
5.6-luna  = gpt-5.6-luna
```

Model resolution is simple: `dispatch start` looks for the first non-comment assignment matching the provided model key and uses the value after `=`. If no match is found, the key is passed through unchanged as the Codex model string.

Use `dispatch doctor` after Codex upgrades to check the currently available model strings and update `models.conf`.
