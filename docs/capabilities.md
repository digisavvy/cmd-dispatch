# Worker capabilities & sandboxing

What a dispatched worker can and cannot do, per provider. Two different mechanisms enforce these
limits, and only one of them is a real boundary:

- **OS sandbox** (enforced): process-level confinement of `Bash`/shell commands. Only **claude**
  workers run under it today (Claude Code's native Seatbelt/bubblewrap sandbox). It fails closed.
- **Prompt rules** (not a boundary): every worker prompt forbids pushing, branch switching, reading
  credentials, and touching Git hooks/config. A model can ignore these — they reduce accidents, not
  attacks. See [SECURITY.md](../SECURITY.md) for the full trust model.

The worktree/branch per issue isolates concurrent jobs from each other. It is **not** a security
boundary between a worker and the rest of your machine.

## Per-provider matrix

| Capability | codex | claude | kimi | gemini |
|---|---|---|---|---|
| Runtime | `codex exec` | `claude -p` | `kimi -p` | `gemini -p` |
| OS sandbox on shell | `workspace-write` | native OS sandbox | **none** | **none** |
| Write to worktree | yes | yes | yes | yes |
| Write to shared `.git` (commit) | yes (`--add-dir`) | yes (sandbox auto-allows) | yes (`--add-dir`) | **no** — commits fail |
| Alter `.git/hooks`, `config` | yes (open) | **denied** by sandbox | yes (open) | n/a |
| Network egress from shell | **open** | **denied** (empty allowlist) | **open** | **open** |
| Read repo secrets (`.env` in checkout) | yes | yes | yes | yes |
| Read `~/.ssh`, `~/.aws` | not blocked | **denied** for sandboxed cmds | not blocked | not blocked |
| Unsandboxed-retry escape hatch | n/a | **disabled** | n/a | n/a |
| Report to foreman session | no | yes (default) | no | no |
| Status | supported | supported | supported | **unverified stub** |

Notes:

- **claude** is the only hardened profile. Its sandbox covers **`Bash` only** — the built-in Edit
  tool still has `--add-dir` write access to the shared `.git` common directory, so `acceptEdits`
  scopes edits to the worktree + `--add-dir` paths instead. Claude's own API traffic runs in the
  parent process, outside the sandbox, so the model still works with zero shell egress.
- **codex** confines writes to the worktree (`workspace-write`) but leaves network and credentials
  open. It is write-confined, not network-confined.
- **kimi** runs in non-interactive auto-approve mode with no OS sandbox. Treat it as fully capable of
  anything the shell can do on your machine.
- **gemini** is an unverified runner stub with no sandbox and no `--add-dir`; it cannot write the
  shared object store, so `git commit` fails. Not recommended until verified.

## What no worker does (all providers)

Enforced by prompt rules and the foreman workflow, not the sandbox:

- **No push, no PR, no merge.** Workers commit only. Landing happens via `dispatch pr` after review.
- **No branch switching or creation.** Each worker is pinned to its `dispatch/issue-<n>` branch.
- **No cross-repo or outside-worktree file changes** (a claude worker's shell is also OS-confined to
  the worktree; other providers rely on the prompt rule alone).

## Tools available to a worker

A worker inherits **its provider CLI's native toolset** — Bash/shell, file read/edit/write, and the
CLI's built-in agent tools. dispatch does **not** wire up any extra tooling:

- **No MCP servers.** Your interactive Claude Code MCP config (GitHub, browser, Slack, etc.) is not
  passed to workers. A dispatched claude worker cannot call MCP tools.
- **No `gh`/network-backed tools in a claude worker.** With shell egress denied, `gh`, `curl`,
  `npm install`, `pip install`, `composer install`, and any test/build step that fetches from a
  registry will fail. Pre-install or vendor dependencies before `dispatch start`. See
  [limitations.md](limitations.md).
- **No browser.** Real-browser verification is a separate path (the cowork worker), not something a
  dispatched worker can do in-sandbox. See [browser-verification.md](browser-verification.md).
- **Cross-session messaging (claude only).** By default a claude worker is a *reporting worker*: it
  messages the foreman's Claude Code session once when it finishes. This is Claude Code's native
  session-to-session channel, carried by the CLI in the parent process — it works with zero shell
  egress and is not a hole in the sandbox. A reporting worker is also started with
  `crossSessionInbound: "accept"`, so it receives foreman messages without an approval dialog.
  Opt out with `dispatch start ... --no-report`; codex, kimi, and gemini workers have no inbox and
  are always silent. See [modes.md](modes.md#a-second-axis-reporting-and-silent-workers).

## Capability implications for task routing

A task is **not sandbox-completable** — by any model — if it requires network egress, real
credentials, cross-repo changes, deploys, or a live service. For claude workers these fail hard; for
codex/kimi they may "succeed" only because those providers aren't network-confined, which is a weaker
guarantee, not a feature. Route such tasks to a non-sandboxed mode or a human rather than assuming a
stronger model will unblock them. Switching models only helps when the blocker is **difficulty**, not
**capability**.

## The gate runs sandboxed too

The optional merge gate reviews a diff and needs no writes:

- **codex** gate: `--sandbox read-only`.
- **claude** gate: same sandbox settings as the claude worker (egress denied, creds denied).
- **kimi** gate: no sandbox.
- **gemini**: no gate runner.

The gate reads untrusted issue text and diff with another model; it is not a sandbox substitute for
human review and never merges. See [gate.md](gate.md).
