# Getting Started

A 5-minute walkthrough of *using* cmd-dispatch. Already installed? Good — if not, see
[Usage → Install](usage.md#install). This assumes your provider CLIs are logged in
(`dispatch doctor` will tell you).

## The mental model

You are the boss. **Claude Code is the foreman** — you talk to it, it dispatches **workers**
(headless `codex`/`claude` runs), one per GitHub issue, each in its own git worktree/branch.
Workers commit but never push. **You review before anything merges.** That's the whole loop.

Two ways to drive it: talk to the foreman with `/dispatch`, or call the `dispatch` CLI yourself.
They do the same thing — the foreman just runs the CLI for you.

## Your first dispatch

From **inside the repo that has the issues** (not from cmd-dispatch itself):

```
cd ~/code/my-project        # a repo with open GitHub issues
dispatch doctor             # sanity check: providers installed + logged in?
```

Now put a worker on an issue. Pick a model by its alias — the provider comes along with it
(`5.6` is codex, `sonnet` is claude):

```
dispatch start 41 5.6       # codex gpt-5.6-sol on issue #41
```

Or hand the foreman plain English and let it do the mechanics:

```
/dispatch put 5.6 on #41, sonnet on #42
```

Don't want to remember aliases? Use **`/pick`** — it shows a short plain-English menu
(Codex / Claude × Best / Balanced / Fast) and dispatches your choice:

```
/pick #41 #42
```

(`/dispatch #41 #42` with no model does the same thing inline. Run `dispatch models` anytime to see
every alias and what it maps to.)

## Watch it work

```
dispatch status                 # every job at a glance: RUNNING / DONE / FAILED / KILLED
dispatch wait 41                # block until #41 finishes (no busy-polling)
dispatch wait --any             # ...or until whichever job finishes first
dispatch logs 41 -f --events    # live-tail what the worker is actually doing
```

`dispatch wait` is the one to lean on — it returns the moment the worker is done (exit code
mirrors the job), so you're not guessing when to check back.

## Land it (you're the merge gate)

When a job is `DONE`, review before it goes anywhere:

```
dispatch status 41              # see the worker's final message
git -C ../my-project-wt-issue-41 diff main   # read the actual diff
```

Happy with it? Open the PR:

```
dispatch pr 41                  # pushes the branch, opens a PR that closes #41
```

Not happy? Don't merge — redo it with better guidance (see steering).

## Steer mid-flight

```
dispatch stop 52                        # kill a worker (keeps its worktree)
dispatch clean 52 && dispatch start 52 5.6   # reassign #52 to a different model
```

Reassigning is always `clean` then `start` — one job per issue.

## Check your limits

```
dispatch usage                  # codex usage % + reset windows (free, no API call)
dispatch usage --probe          # also probe claude for its reset/status (one live call)
```

## A full example

Two issues, two providers, hands-off until they're done:

```
cd ~/code/my-project
dispatch start 41 5.6           # codex on the hard one
dispatch start 42 sonnet        # claude on the other
dispatch wait --any             # go get coffee; returns when the first finishes
dispatch status                 # check both
dispatch pr 41                  # review + ship #41
dispatch clean 41               # tidy the worktree (PR/branch survive)
```

## Where to go next

- [Usage](usage.md) — full per-command reference and the `/dispatch` slash command.
- [Architecture](architecture.md) — how workers, worktrees, and state actually work.
- [Limitations](limitations.md) — what it deliberately doesn't do.
