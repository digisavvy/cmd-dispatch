# Why cmd-dispatch? The idea in plain words

## The 30-second version

You have a repo with a pile of GitHub issues. You have subscriptions to one or more AI coding
tools — Claude, ChatGPT/Codex, maybe others. cmd-dispatch lets you say, in plain English:

> "Put Claude on the auth bug, Codex on the two little docs issues."

Each issue gets its own AI worker, working in its own private copy of the repo, all at the same
time, while you do something else. When a worker finishes, it has *committed* its work but cannot
merge or push anything — you (or a second AI reviewer you choose) look at the result first, and
only then does it become a pull request.

That's the whole tool: **delegate issues, work happens in parallel and in isolation, nothing lands
without review.**

## The picture to keep in your head

It's a job site.

- **You are the owner.** You decide what gets built and what's good enough to ship.
- **The foreman is the Claude Code session you talk to.** You give it assignments in normal
  sentences; it handles the mechanics and reports back. (You can also skip the foreman and run the
  `dispatch` commands yourself — same thing.)
- **Workers are AI coding agents that run unattended** — no chat window, no questions, they just
  work the issue and commit. One worker per issue. A worker can be any provider you've set up:
  Claude, Codex, Gemini, or Kimi.
- **Every worker gets its own fenced-off copy of the repo** (git calls this a "worktree") and its
  own branch. Workers can't step on each other, and none of them ever touch the copy *you're*
  working in.
- **Nothing merges itself. Ever.** Workers commit but can't push or open pull requests. The default
  reviewer is you, reading the diff. Optionally, a second AI — ideally from a *different* provider
  than the worker — reviews first and only opens a PR if it approves. Even then, merging stays
  yours.

## What actually happens when you dispatch an issue

Say you run `dispatch start 41 sonnet` (or tell the foreman "put sonnet on #41"):

1. dispatch fetches issue #41's title and description from GitHub.
2. It creates a private copy of the repo next to your checkout and a branch for the fix.
3. It starts a Claude worker in that copy with the issue as its brief, plus standing rules:
   stay in this copy, keep the change scoped to this issue, run the tests, commit — never push.
4. You go do something else. `dispatch status` shows every worker's state at a glance;
   `dispatch wait` blocks until one finishes; `dispatch logs -f` watches one work live.
5. When it finishes you get a ping (terminal bell, macOS banner — or Slack/ntfy/anything via a
   hook). A Claude worker also messages your foreman session directly, so the foreman can tell you
   "#41 is done" without anyone polling.
6. You read the diff. Good? `dispatch pr 41` pushes and opens a pull request that closes the
   issue. Not good? Kill it, tighten the issue, dispatch again — your repo was never touched.

## What you get out of it

- **Parallel progress.** Three issues, three workers, one afternoon. Your own working copy stays
  free for whatever *you* are doing.
- **Your subscriptions, fully used.** You're probably paying for more than one AI tool. Dispatch
  lets you spend them side by side — the strongest model on the gnarly bug, the cheap fast one on
  mechanical chores — chosen per issue with a two-character alias.
- **An honest second opinion.** The optional review gate can use a different provider than the
  worker. A reviewer that didn't write the code has no stake in defending it, and in practice
  catches more.
- **Safety by construction, not by promise.** Isolation doesn't depend on the model behaving:
  workers are confined by git worktrees, OS-level sandboxing (for Claude workers: writes limited to
  their copy, no network for shell commands), and the hard rule that only `dispatch pr` — run by
  you — ever pushes.
- **Nothing to babysit, nothing to un-learn.** It's one small script plus a slash command. State is
  plain files in `.dispatch/` you can read with `cat`. If you stop using it, there's nothing to
  tear down — delete the worktrees and you're back where you were.

## What it deliberately is not

- **Not an autonomous loop.** It will never pick its own issues, chain its own tasks, or merge its
  own work. The conversational steering — "kill #52, give it to codex" — is the point.
- **Not a framework.** No YAML, no server, no database, no orchestration graph. If an issue needs
  five agents talking to each other, this is the wrong tool.
- **Not a substitute for judgment.** It moves the work; the taste stays with you. Vague issues
  produce vague results — the better the issue is written, the better the worker does.

## The words, decoded

| Term | Plain meaning |
| --- | --- |
| **foreman** | The Claude Code session you talk to. Runs the CLI for you, reports back. |
| **worker** | An AI coding agent running unattended on one issue. |
| **worktree** | Git's name for an extra working copy of a repo. Each worker gets one; yours stays untouched. |
| **headless** | Running without a chat window — the worker gets one brief and works until done. |
| **gate** | The optional AI review of a finished job. Approval opens a PR; rejection holds the work and says why. Never merges. |
| **rework** | Sending a rejection's findings back to the same worker for another attempt. |
| **reporting / silent** | Whether a finished worker messages your foreman session (Claude workers do, unless you opt out) or you check in yourself. |
| **alias** | Your shorthand for "provider + model", e.g. `sonnet` or `5.6`. Defined in `models.conf`. |

## Where next

- [Quickstart](quickstart.md) — zero to your first reviewed PR, copy-paste.
- [Getting started](getting-started.md) — the fuller 5-minute walkthrough.
- [Foreman modes](modes.md) — who reviews the work: you, a second model, or dealer's choice.
- [Security](../SECURITY.md) — the trust model, stated plainly.
