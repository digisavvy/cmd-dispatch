# Quickstart

Zero to your first reviewed PR. If you want to know *why* the tool works this way first, read
[Why cmd-dispatch?](why-dispatch.md) — it's five minutes and makes everything below obvious.

## The whole thing at a glance

```sh
git clone https://github.com/digisavvy/cmd-dispatch && cd cmd-dispatch && ./install.sh
dispatch doctor                  # tells you exactly what's missing, if anything
cd ~/code/your-project           # a repo with open GitHub issues
dispatch start 41 sonnet         # put a worker on issue #41
dispatch wait 41                 # go get coffee — returns when it's done
git -C ../your-project-wt-issue-41 diff main   # read what it did
dispatch pr 41                   # happy? push + open the PR
```

The rest of this page is the same seven steps with the checks and choices spelled out.

## 1. Have the basics

You need: **macOS or Linux**, `git`, `jq`, and the GitHub CLI **`gh`** logged in
(`gh auth status`). On macOS you also need coreutils for `gtimeout`
(`brew install coreutils`). Don't audit this list by hand — `dispatch doctor` in step 3 checks
every one of them and says how to fix what's missing.

And at least one worker to hire — any of these, installed and logged in:

```sh
npm i -g @openai/codex && codex login      # Codex — uses your ChatGPT Plus/Pro subscription
# and/or Claude Code itself                # you likely already have this one
```

Claude Code doubles as both the foreman you talk to and a worker provider. Gemini and Kimi work
too, if you have them.

## 2. Install dispatch

```sh
git clone https://github.com/digisavvy/cmd-dispatch
cd cmd-dispatch
./install.sh
```

That symlinks the `dispatch` CLI into `~/.local/bin` and the `/dispatch` and `/pick` slash commands
into Claude Code. If it warns that `~/.local/bin` isn't on your PATH, add the line it prints to
your shell config.

## 3. Let doctor check your setup

```sh
dispatch doctor
```

It checks every dependency, shows which provider CLIs it found, prints the **real model strings**
your providers accept, and validates your aliases. Fix anything it flags, re-run until it says
`Ready.`

## 4. Name your models

Aliases live in `models.conf` (created for you from the example). Each line is
`your-shorthand = provider model-string`:

```conf
5.6    = codex gpt-5.6-sol
sonnet = claude sonnet
```

Use the model strings doctor printed — don't guess them. `dispatch models` lists what you've
configured, anytime.

## 5. Dispatch your first worker

From **inside the project you want worked on** (not the cmd-dispatch repo — one common trip-up):

```sh
cd ~/code/your-project
dispatch start 41 sonnet
```

Or, in Claude Code, just say it:

```
/dispatch put sonnet on #41
/pick #41 #42          ← no alias memorized: choose from a short menu instead
```

Either way you get a confirmation with the worktree path and how to watch. The worker is now going
through issue #41 in its own copy of the repo at `../your-project-wt-issue-41` — your checkout is
untouched, and you can keep working in it.

## 6. Wait — don't watch

```sh
dispatch status        # all workers at a glance
dispatch wait 41       # block until #41 finishes (or:  dispatch wait --any)
dispatch logs 41 -f    # only if you're curious what it's doing right now
```

You'll get a bell and a macOS banner when it finishes either way, and a Claude worker messages
your foreman session directly — so honestly, just go do something else.

## 7. Review, then ship

The worker committed on branch `dispatch/issue-41` and stopped there. Nothing is pushed. Now the
part that's yours:

```sh
dispatch status 41                              # the worker's summary of what it did
git -C ../your-project-wt-issue-41 diff main    # the actual diff — read it
dispatch pr 41                                  # good → push + open a PR closing #41
```

Not good? Nothing to undo — your repo never changed:

```sh
dispatch clean 41 --force   # discard the worker's copy, branch, commits, and job state
# tighten the issue description, then dispatch again — maybe a stronger model
dispatch start 41 5.6
```

(`--force` is required here because the worker's commits were never shipped — plain `clean` refuses
to throw away the only copy of committed work, which is exactly what you want after a PR but not
before one.)

Want a second opinion before *you* even look? Add `--gate` when starting
(`dispatch start 41 sonnet --gate`) and a different model reviews the finished work: approval
opens the PR, rejection holds the job with written findings. It still never merges — see
[modes.md](modes.md).

## If something's off

`dispatch doctor` first — it names most problems outright. Then
[troubleshooting.md](troubleshooting.md). The three most common trip-ups:

1. Running `dispatch start` from the wrong directory — run it inside the target project.
2. A model alias that doesn't match `models.conf` — run `dispatch models` and use what's listed.
3. A provider CLI that's installed but not logged in — doctor shows install state; logins are
   `codex login`, or just having used Claude Code.

## Where next

- [Why cmd-dispatch?](why-dispatch.md) — the concept and the value, no jargon.
- [Getting started](getting-started.md) — a fuller walkthrough: gates, rework, usage limits.
- [Usage](usage.md) — every command and flag.
- [Foreman modes](modes.md) — deciding who reviews: you, a second model, or dealer's choice.
