# cmd-dispatch

A thin **conversational foreman** for coding agents. You talk to a lead agent (Claude Code / Fable)
and say *"put sonnet on #41, 5.6 on the other two"* — it spawns one headless **Codex or Claude** worker
per GitHub issue, using the provider implied by the model alias. Each gets its own git worktree/branch,
and the lead
reviews before anything merges.

This is deliberately **not** a framework. It's a small CLI (`bin/dispatch`) plus a slash command
(`/dispatch`). The conversational steering — *"kill #52, give it to 5.6"* — is the whole point; the moment
it becomes a config-driven autonomous loop, it's just a worse [zeroshot](https://github.com/the-open-engine/zeroshot).

## How it works

```
you ── talk ──▶ Claude Code (foreman)
                   │  parses "5.6 on #41, 5.5 on #52 #57"
                   ▼
              dispatch start …   (per issue)
                   │
      ┌────────────┼────────────┐
      ▼            ▼            ▼
  codex exec   codex exec   codex exec     ← headless, --sandbox workspace-write, --json
  wt-issue-41  wt-issue-52  wt-issue-57    ← isolated git worktree + branch each
      │            │            │
      └── commit (never push) ──┘
                   ▼
         foreman reviews diff → dispatch pr <n>   ← you are the merge gate
```

State lives in `<target-repo>/.dispatch/` (add it to `.gitignore`), so "who's on what" survives crashes
and new sessions. One job per issue.

## Setup

```sh
npm i -g @openai/codex     # the worker runtime
codex login                # use your ChatGPT subscription (Pro/Plus) — interactive, browser
./install.sh               # symlinks CLI to ~/.local/bin, command to ~/.claude/commands
dispatch doctor            # verifies deps + prints the REAL model strings for models.conf
```

Then edit **`models.conf`** so your aliases name a provider and model (doctor detects installed CLIs):

```
5.6    = codex gpt-5.6-sol
sonnet = claude sonnet
```

## Use

In Claude Code, from inside the target repo:

```
/dispatch put 5.6 on #41, 5.5 on #52 and #57
```

Or drive the CLI directly:

```sh
dispatch start 41 5.6         # spawn a worker
dispatch status               # RUNNING / DONE / FAILED / KILLED + last event / final message
dispatch usage                # subscription usage bars and reset windows
dispatch logs 41 -f           # tail live output
dispatch stop 52              # kill a worker (keeps the worktree)
dispatch clean 52             # remove worktree + branch + job state (to reassign)
dispatch pr 41                # push branch + open PR closing the issue (after you review)
```

## Documentation

- [Getting started](docs/getting-started.md) - a 5-minute walkthrough of using it (start here)
- [Usage](docs/usage.md) - install, CLI commands, `/dispatch`, and model aliases
- [Architecture](docs/architecture.md) - worktrees, worker processes, state files, and PR gate
- [Limitations](docs/limitations.md) - current boundaries and missing commands
- [Codex events](docs/codex-events.md) - observed `codex exec --json` event vocabulary
- [Claude events](docs/claude-events.md) - observed Claude stream-JSON event vocabulary

## Design notes / limits

- **Subscription auth, no API keys.** dispatch shells out to `codex`, which holds its own login.
- **Merge gate is you.** Workers commit but never push or PR. Nothing lands without lead review.
- **Model strings drift** — that's why they're aliases in `models.conf`, resolved at runtime, never
  hardcoded. Re-run `dispatch doctor` after Codex upgrades.
- **`--full-auto` is deprecated** in current Codex; this uses the explicit `--sandbox workspace-write`.
- Codex and Claude workers are supported; Gemini currently has an unverified runner stub.
- Next sturdiness step: workers report status through `cowork-bridge` instead of the foreman polling
  files. Same UX, better plumbing.
