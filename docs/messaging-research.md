# Cross-session messaging for the dispatch foreman

Research date: 2026-08-08. Research only — no behavior changed by this note. Nothing in `bin/dispatch`,
the skill, or the commands was modified.

Claude Code v2.1.224 added [cross-session messaging](https://code.claude.com/docs/en/cross-session-messaging):
one Claude Code session can deliver a plain-text message to another. The obvious fit for dispatch is
the gap this tool has always had — a finished worker pings a *human* (bell, macOS banner,
`DISPATCH_NOTIFY_CMD`) but has no way to tell the *foreman Claude* anything, so the foreman only
learns a job finished when someone tells it or it polls `dispatch status`.

This note evaluates whether that gap can now be closed, and concludes that **the obvious
implementation is not available on supported ground, but an inverted one is.** The headline finding
is negative and worth reading before any code is written.

## The blocking finding: no supported push path from a shell script

The natural design is a `DISPATCH_NOTIFY_CMD` wrapper that writes the completion headline into the
foreman's inbox socket. `cmd_notify` already has the extension point (`bin/dispatch:1175`), and
Claude Code exports the socket path to Bash commands and hooks as `CLAUDE_CODE_MESSAGING_SOCKET`.
The docs even name the use case: *"Read this section when a session you expect isn't in the agent
list, when you want a script or hook to post into a session, or when a sandboxed command can't reach
the socket."*

**But no wire format for that socket is documented anywhere, and no CLI surface exists for it.**

| Checked | Result |
| --- | --- |
| `cross-session-messaging` docs page, in full | Describes *how messages arriving on the socket are treated* (inbound controls, own-child verification), never how to write one. No payload schema, no example command. |
| `cli-reference` docs page | No flag or subcommand sends a message or posts to a session inbox. `--name`, `-n` and `--settings` exist as documented. |
| `env-vars` docs page | The variables table is truncated upstream at the point `CLAUDE_CODE_MESSAGING_SOCKET` would appear. `[VERIFY]` — could not confirm whether the full table documents a format. |
| Sending is done by | The `SendMessage` tool, called by Claude. Discovery is `ListAgents`. Both are model-facing tools, not shell-callable. |

### Probes against a live socket

Verified locally in this session (Claude Code 2.1.226, Linux container, `claude` at PID 510, so not
the PID-1 case the docs call out):

```
CLAUDE_CODE_MESSAGING_SOCKET=/tmp/cc-socks/510.sock
srw------- 1 root root 0 Aug  8 17:53 /tmp/cc-socks/510.sock
```

Mode `0600`, matching the documented "restricted to your operating-system user". Five framings were
sent to it, each on a fresh connection:

| Framing | Result |
| --- | --- |
| `{"type":"message","text":…}` + `\n` | connection accepted, no reply, nothing delivered |
| `{"type":"peer_message","message":…}` + `\n` | same |
| `{"v":1,"type":"ping"}` + `\n` | same |
| `u32`-big-endian length prefix + JSON | same |
| `HTTP/1.1` `GET /`, `POST /`, `POST /message` | same (a plain `curl --unix-socket` GET times out) |

The socket accepts the connection and silently discards non-conforming input. No message ever
appeared in the session. So the protocol requires an undocumented handshake — consistent with the
registry advertising `"peerProtocol":1`, an explicitly versioned wire format.

### The session registry

Discovery is a directory of per-process JSON files. This session's:

```json
{"pid":510,"sessionId":"8920dbe5-…","cwd":"/home/user/cmd-dispatch","startedAt":1786211607044,
 "procStart":"475","version":"2.1.226","peerProtocol":1,"kind":"interactive",
 "entrypoint":"remote_mobile","messagingSocketPath":"/tmp/cc-socks/510.sock",
 "name":"cmd-dispatch-d6","nameSource":"derived"}
```

`~/.claude/sessions/<pid>.json`. This confirms the documented "each session registers itself in
files on disk", and would let dispatch enumerate reachable sessions — including `kind` and `name` —
without `ListAgents`. The layout is undocumented, so reading it is a soft dependency: if it moves,
a feature that reads it degrades to nothing. Writing the protocol is a hard dependency: if
`peerProtocol` increments, a reimplementation breaks or, worse, silently stops delivering.

### Why the sender's identity is the real obstacle

The inbound default is decided by *the sending session's asserted permission class*:

> **The receiving session prompts for permissions**: Claude Code delivers each message. It holds one
> for your approval only when the sending session identifies itself as bypassing permission prompts.

A shell script has no permission class to assert. The docs describe exactly where that lands:
*"it treats the message like any other that asserts no permission class, so a session that bypasses
permission prompts holds it for your approval."* So even a perfectly reverse-engineered client would
be in the weakest trust bucket by construction. The own-child exemption only partly rescues it, and
not portably:

- It applies **only when no `crossSessionInbound` value applies**.
- On Linux it verifies even an exited child; **on macOS only while the posting process still runs**.
- **In containers where Claude Code is PID 1, it cannot verify at all.**
- Dispatch's worker is a detached grandchild (`nohup bash "$jd/run.sh" &`, `bin/dispatch:426`), so
  whether it is still "the session's own child process" at notify time is untested. `[VERIFY]`

**Verdict: do not build the socket-writing wrapper.** Reverse-engineering a versioned internal
protocol is the wrong foundation for a tool whose entire value proposition is being thin and
predictable, and it would land in the weakest delivery class even if it worked.

## The inverted design, which is supported

The worker is itself a Claude session. It *has* `SendMessage`. So the message should travel
**worker → foreman**, sent by the worker's own Claude at the end of its run, rather than
**run.sh → foreman**, written by a shell script.

Everything this needs is documented, and the load-bearing parts were verified by running real
`claude -p` workers in this environment (see below):

- *"Claude Code binds an inbox socket for a `claude -p` session like an interactive one, so a
  long-running `-p` worker can receive messages and appears in the listing."* **Confirmed by probe.**
  The worker is a first-class peer, in both directions.
- **`SendMessage` and `ListAgents` are present in a `-p` worker's tool list. Confirmed by probe.**
  This is the assumption the whole design rests on.
- Bare mode is the exception that does **not** bind a socket. Dispatch does not use bare mode.
- The sandbox blob at `bin/dispatch:339` confines **Bash** writes and network egress. `SendMessage`
  is a built-in tool running in the parent process, so the sandbox does not gate it. The
  documented sandbox interaction (`sandbox.network.allowUnixSockets`) concerns *Bash commands*
  reaching the socket — not the tool.
- The worker runs `--permission-mode acceptEdits` (`bin/dispatch:338`), which the docs place in the
  **prompting** class, not the bypassing one. That is the favourable direction: a prompting sender
  is delivered to a prompting receiver without a dialog.

### Worker-side behavior, verified by probe

Three `claude -p` runs, Claude Code 2.1.226, with `--name` and `--permission-mode acceptEdits`:

| Question | Result |
| --- | --- |
| Does a `-p` worker bind an inbox socket? | **Yes.** While alive: `"messagingSocketPath":"/tmp/cc-socks/5170.sock"`, and the socket file existed. Removed on exit — so it is only addressable *while running*. |
| Does it have `SendMessage` / `ListAgents`? | **Yes**, both in the `system`/`init` event's tool list. |
| Is `--name` honored? | **Yes.** `"name":"dispatch-probe-43"`, and `nameSource` is **absent** when set explicitly, versus `"derived"` for an unnamed session — a usable discriminator. |
| Does `kind` distinguish a `-p` worker? | **No.** It registers as `"kind":"interactive"`, same as a normal session. Identify workers by `name`, not `kind`. |
| Is `sessionId` per-process? | **No — it is inherited from the parent environment.** Every worker spawned by a foreman reported the *foreman's* `sessionId`. **Never key a worker on `sessionId`;** use `pid` or `name`. |

One environment note from the same probes: with the dispatch sandbox blob, `claude -p` **refuses to
start** where `bubblewrap` and `socat` are absent — `sandbox.failIfUnavailable` failing closed, as
designed (`bin/dispatch:339`). The process still writes a registry entry before exiting non-zero, so
a registry entry alone does not mean a worker is healthy.

Because the socket disappears when the worker exits, **foreman→worker steering is inherently a
race**: `dispatch tell` would have to handle "worker already gone" as a normal outcome, falling back
to the prompt-append path `rework` already uses (`bin/dispatch:930`).

Three changes would be needed, none of them written here:

1. **Name the worker.** `claude -p … --name dispatch-issue-<n>` at `bin/dispatch:336`, so the
   foreman can address it deterministically instead of relying on a `cwd`-derived name like
   `myapp-wt-issue-41-3f`.
2. **Accept inbound on the worker.** Add `"crossSessionInbound":"accept"` to the `--settings` JSON
   at `bin/dispatch:339`. This is **required** for foreman→worker steering, because *"a `-p` session
   can't show the approval dialog. A held message stays held there."* Without it, a `dispatch tell`
   would silently do nothing whenever the default holds.
3. **Tell the worker who to report to.** Record the foreman's session name in job `meta`
   (`bin/dispatch:409`) and add a line to `prompt.base.txt` instructing the worker to `SendMessage`
   a one-line summary to that name before finishing.

### Delivery matrix for the combinations dispatch actually produces

Derived from the documented default, for when no `crossSessionInbound` applies. `acceptEdits`,
`auto`, and `dontAsk` all count as *prompting*; only `bypassPermissions` (and `plan` where bypass is
available) counts as *bypassing*.

| Foreman mode | Direction | Outcome |
| --- | --- | --- |
| prompting (`default`, `acceptEdits`, `dontAsk`, `auto`) | worker → foreman | **Delivered.** The working case. |
| `bypassPermissions` | worker → foreman | **Held** for approval; the foreman is interactive so the dialog can be answered — but it **expires after `dialogExpiry`, default five minutes, and is then dropped.** |
| prompting | foreman → worker | Delivered **only** if the worker sets `crossSessionInbound: accept`; otherwise a hold is permanent in `-p`. |
| `bypassPermissions` | foreman → worker | Same, and the hold is more likely. `accept` on the worker is the fix in both rows. |

**The footgun to document loudly:** a foreman running in `bypassPermissions` — plausible for this
workflow — gets job notifications **held**, and a hold left unanswered for five minutes is
**dropped silently**. That failure mode is invisible: no error, no retry, just a notification that
never arrives. Any implementation must state the recommended foreman configuration rather than
leaving it to chance.

## What this would change in the existing docs

Two current claims become provider-conditional rather than flatly true, and should not be edited
until the feature actually ships:

- `docs/limitations.md:6` — *"No mid-run steering channel. To change direction, stop/clean the job
  and start a new one."* For **`claude` workers only**, a live steering channel is now possible.
  Codex, Gemini, and Kimi workers have no inbox, so the limitation stands for them. Any rewrite must
  keep that asymmetry explicit rather than implying dispatch gained steering across the board.
- `skills/dispatch/SKILL.md:105` — *"you cannot steer one mid-run — kill and re-dispatch."* Same
  qualification.

`docs/notifications.md` would gain the channel; `README.md`'s notifications section would need a
line; `SECURITY.md` would need the trust discussion below.

## Security implications

- **Inbound acceptance is a new injection surface into a deliberately confined process.** The worker
  prompt already treats the issue body as untrusted (`bin/dispatch:277-289`). Setting
  `crossSessionInbound: accept` means any process able to reach that socket can inject text into a
  sandboxed worker mid-run. The socket is mode `0600` and same-user, so the practical boundary is
  unchanged — anything that could post there could already write the worktree directly — but it
  should be stated, not assumed.
- **What a message provably cannot do** is load-bearing here and worth citing in `SECURITY.md`: a
  peer message *"can't approve anything"* (never counts as consent for a pending permission prompt),
  *"can't change configuration"* (permissions, `CLAUDE.md`), and commands in its text *"arrive as
  plain text — Claude Code never executes it"*. Permission prompts still fire normally.
- **`crossSessionInbound: accept` should stay on the worker's `--settings`, not the target repo's
  project settings.** A project-scope `accept` applies to *every* peer message in that repo, for the
  foreman too; the `--settings` form scopes it to the one confined process that needs it.
- **Message loops are throttled by Claude Code** — per-sender rate limiting, identical repeats within
  a short window dropped, and at most 50 accepted-unread messages per session. A foreman/worker
  chatter loop stops on its own, so dispatch needs no loop-breaker of its own.
- **Cross-machine sends** are reply-only and route through Anthropic servers.
  `isolatePeerMachines: true` forces explicit approval before any message leaves the machine, even
  in `bypassPermissions`. Worth recommending for anyone dispatching in a repo they don't own.

## The container caveat

*"A container has its own filesystem, so a session inside it and a session on the host can't reach
each other."* Consequences for dispatch:

- A foreman in **Claude Code on the web** (or any containerized session) **cannot** exchange messages
  with a `dispatch` worker running on the user's machine. This is a **local-foreman feature only**.
- Cross-machine peers are **reply-only** — a local session cannot open an exchange with a web
  session at all.
- Two sessions inside the *same* container can message each other, so a self-hosted runner that runs
  both foreman and workers keeps the feature.

## Availability gates worth surfacing in `dispatch doctor`

- **v2.1.224 minimum.** `claude --version` is already invoked in `cmd_doctor`'s probe path
  (`bin/dispatch:1257`), so a version comparison is cheap to add.
- **macOS and Linux only** (including WSL 2). Not on native Windows.
- **Not available** on Amazon Bedrock, Claude Platform on AWS, Google Cloud's Agent Platform, or
  Microsoft Foundry.
- **Silently disabled** when `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_TELEMETRY`,
  `DO_NOT_TRACK`, or `DISABLE_GROWTHBOOK` turns off the feature-flag evaluation it depends on. This
  is the nastiest gate: a privacy-conscious user has messaging off with no visible signal, and
  `DISABLE_TELEMETRY`/`DO_NOT_TRACK` are common in exactly the kind of environment this tool runs in.
- The documented self-check is `/list-agents` (alias `/peers`): unrecognized means the session lacks
  the feature; recognized-but-undelivered means something narrower (a deny rule, the receiver's
  inbound controls, or a reply-only peer).

## Recommendation

1. **Do not** build a socket-writing `DISPATCH_NOTIFY_CMD` wrapper. The protocol is undocumented and
   versioned, a shell sender lands in the weakest trust class, and the own-child exemption is not
   portable across macOS, Linux, and containers.
2. **Keep the existing human notification path unchanged.** Bell, banner, and `DISPATCH_NOTIFY_CMD`
   remain the right channel for human attention, and remain the only channel that works for Codex,
   Gemini, and Kimi workers.
3. If a foreman-facing channel is wanted, build the **inverted, worker-sends design** — `--name`,
   `crossSessionInbound: accept` on the worker's `--settings`, foreman session name in `meta`, and a
   reporting instruction in `prompt.base.txt`. It is supported, needs no reverse engineering, is
   roughly three small edits, and its load-bearing assumption — that a `-p` worker has `SendMessage`
   and binds an inbox — is verified above rather than assumed.
4. Gate any of it behind an explicit flag. Point 3 changes the worker's isolation posture, and this
   tool's users chose it partly *because* the worker is confined and non-interactive.
5. Treat the `bypassPermissions`-foreman hold-then-drop behavior as the primary documentation
   burden, not a footnote.

## Open questions

Resolved by the probes above: a `-p` worker binds a socket, has `SendMessage`/`ListAgents`, honors
`--name`, registers as `kind: "interactive"`, and inherits its parent's `sessionId`.

Still open:

- `[VERIFY]` Whether the full `env-vars` table documents a payload format for
  `CLAUDE_CODE_MESSAGING_SOCKET`. The upstream page truncates before that row.
- `[VERIFY]` Whether a detached grandchild (`nohup bash run.sh &`) still satisfies own-child
  verification at notify time, on Linux and on macOS. Untested; only matters if point 1 is revisited.
- `[VERIFY]` Whether `SendMessage` behaves identically **with the sandbox blob applied**. The tool is
  present in an unsandboxed `-p` run, but this container lacks `bubblewrap`/`socat`, so the sandboxed
  variant could not be started here. Retest on a machine with both installed before building.
- `[VERIFY]` End-to-end delivery of a worker→foreman message, including what the foreman actually
  sees, and the `bypassPermissions` hold-then-expire path. Requires two cooperating sessions on one
  machine with a working sandbox.
- Unresolved by design: nothing here gives Codex, Gemini, or Kimi workers a foreman channel. Any
  feature built on this is Claude-worker-only, in a tool whose premise is cross-provider.
