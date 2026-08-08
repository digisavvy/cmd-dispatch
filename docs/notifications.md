# Notifications

Each generated `run.sh` writes the worker's `exitcode`, then calls `dispatch notify` with `DONE` or
`FAILED(code)`. Notification delivery is best-effort and does not change the worker result.

`dispatch notify` also supports `STALLED`. The status command detects and displays that state, but
does not itself send a notification; a caller that wants a stalled alert must invoke
`dispatch notify <issue#> STALLED`.

The merge gate sends its own notifications on every verdict: `APPROVE` (with the PR URL),
`REJECT` (pointing at the saved report), and `REWORK` when a rejection is fed back to the worker
for another attempt (see [gate.md](gate.md)).

Every channel described below targets a **human**: the terminal bell, the macOS banner, and whatever
`DISPATCH_NOTIFY_CMD` routes to. None of them reach the *foreman Claude session* that started the
job.

## The foreman channel

A **reporting** `claude` worker closes that gap by messaging the foreman's session directly when it
finishes, using [cross-session messaging](https://code.claude.com/docs/en/cross-session-messaging)
— the session-to-session channel introduced in Claude Code v2.1.224 (August 2026). This is a second, independent channel — it does not replace or alter anything above, and
it exists only for `claude` workers on a local foreman. See [modes.md](modes.md) for the full
requirements and the `bypassPermissions` trap; the short version:

- `dispatch start` resolves the foreman's session name and bakes it into the worker's prompt. The
  worker sends one line — `#<n> DONE — …` or `#<n> BLOCKED — …` — as its last action.
- Opt out per job with `dispatch start <n> <model> --no-report`, which restores the previous
  invocation exactly.
- Non-`claude` workers are always silent. Nothing about their notifications changed.
- Run the foreman in a prompting mode. A `bypassPermissions` foreman **holds the report instead of
  delivering it** — measured never to arrive at a non-interactive one — and the worker still sees its
  send succeed either way. See [modes.md](modes.md) for the exact scope of that measurement.

The channel is not a substitute for the human ones. It is best-effort by construction: the worker is
told that a failed send is not a task failure, so an unreachable, disabled, or renamed foreman costs
nothing. `dispatch doctor` reports whether reporting is actually available.

### Ordering

The human path is unchanged and still holds its guarantee exactly: `run.sh` writes the worker's
`exitcode`, then the ledger line, then calls `dispatch notify`. Nothing was inserted into that
sequence.

The foreman report is different, and the difference is worth stating plainly. The worker sends it
itself, with its own `SendMessage` tool, so it goes out **before** the worker process exits — and
therefore before `exitcode` is on disk. There is no way around this: a shell script cannot write to
a session's inbox (see [messaging-research.md](messaging-research.md)), so the only supported sender
is the worker's own Claude.

What that does and does not cost:

- It cannot corrupt job state or change a worker's result, and it cannot make a *completed* job look
  unfinished — the report is one tool call inside a run that was happening anyway.
- **The worst case is a stalled worker, and it is worth naming.** If the send were to hang rather
  than fail, the worker session would not exit, so `exitcode` would never be written, `dispatch wait`
  would keep blocking, and the job would sit `RUNNING` and then read `STALLED`. That is the same
  failure shape as any other wedged tool call in a worker, and `dispatch status`'s stall detection
  is what surfaces it. It is *not* covered by the exit-code-first guarantee, because that guarantee
  only ever covered the channels `run.sh` fires after the worker is already gone.
- The prompt bounds the exposure rather than eliminating it: exactly one message, at most one retry
  with the ref, no further attempts, and an explicit instruction that a failed send is not a task
  failure. `--no-report` removes the exposure entirely, which is one reason the opt-out exists.
- Every on-disk signal — `exitcode`, the ledger, `dispatch status`, `dispatch wait` — remains the
  authority on whether a job finished. The report is a convenience, never the source of truth.

## Banner layout

A banner reliably shows only its first lines, so the notification is split across
`terminal-notifier`'s three fields, most important first — **which job, what outcome, what to do
now**:

```text
#43 DONE · cmd-dispatch            <- title:    issue, state, repo
Notifications: issue title in ba…  <- subtitle: the issue title, truncated to 45 characters
opus5 · Review & merge: dispatch pr 43   <- message: worker alias, then the next human action
```

The issue title comes from `title` in the job's `meta`, which `dispatch start` records from the
issue JSON it already fetches — `dispatch notify` never hits the network. Jobs started before that
field existed have no `title`, and degrade to the previous layout: the worker alias in the subtitle
(the model slug when `meta` has no alias) and the bare action in the message. The alias is also
dropped from the message whenever the combined line would exceed 60 characters, so a long action —
a gate report path, say — is never pushed out of view by the worker's name.

Default actions are:

- `DONE`: `Review & merge: dispatch pr <n>`
- `FAILED(code)`: `Worker errored — inspect: dispatch logs <n>`
- `STALLED`: `May be stuck / awaiting something — check: dispatch logs <n> -f`

Gate notifications pass their own action text (the PR URL on `APPROVE`, the report path on
`REJECT`, the attempt count on `REWORK`).

Each banner is sent with `-group dispatch-<repo>-<n>`, so a later round for the same job — a
rework attempt, then a gate verdict — replaces its earlier banner instead of stacking a new one.

The issue title is untrusted text ([SECURITY.md](../SECURITY.md)). `dispatch start` collapses its
whitespace and truncates it before it reaches `meta`, and it is used as a display field only: it is
passed to `terminal-notifier` as a single `-subtitle` argument, or through the same AppleScript
escaping as every other field for the `osascript` fallback. It is never interpolated into a shell
string, and dispatch ships no click action that could carry it anywhere (see below).

## Click behavior

Banners have no click action. Clicking one launches `terminal-notifier` and nothing else.

That is deliberate. Every `terminal-notifier` 2.0.0 mechanism that could carry a click was tested on
macOS 26.3.1 (build 25D771280a) with the Homebrew binary at `/opt/homebrew/bin/terminal-notifier`,
by sending a notification and clicking it in Notification Center:

| Mechanism | Result |
| --- | --- |
| `-execute '/usr/bin/touch <marker>'` | No marker file; no process launch in `log show`. |
| `-open 'file://<marker>.html'` | No browser tab opened; frontmost app unchanged. |
| `-activate com.apple.Terminal` | Terminal.app was neither launched nor fronted (checked twice). |
| `-sender com.apple.Terminal` | Notification not delivered at all — absent from `-list ALL`. |

The clicks did register — some of them brought `terminal-notifier.app` to the front — but no
advertised action ran, and the notifications stayed in Notification Center afterwards. The binary is
unsigned (`codesign -dv` reports "code object is not signed at all"), which is the usual reason its
activation handler never runs on current macOS. A button that only dismisses is worse than none, so
dispatch wires no action rather than implying one.

If you want working click actions, [`alerter`](https://github.com/vjeantet/alerter) is the opt-in
alternative: it stays in the foreground until the notification is answered and prints which button
was pressed, so a wrapper can decide what to do. Drive it from `DISPATCH_NOTIFY_CMD`, where the
job's state and PR URL are already in the environment:

```sh
#!/bin/sh
# dispatch-alerter — on PATH, then: export DISPATCH_NOTIFY_CMD=dispatch-alerter
answer=$(alerter -title "#$DISPATCH_ISSUE $DISPATCH_STATE · $DISPATCH_REPO" \
  -message "$DISPATCH_NEXT_ACTION" -actions Open -timeout 30)
[ "$answer" = "Open" ] || exit 0
case "$DISPATCH_STATE" in
  APPROVE) [ -n "$DISPATCH_PR_URL" ] && open "$DISPATCH_PR_URL" ;;
  *)       open -a Terminal "$DISPATCH_REPO_ROOT" ;;
esac
```

Have the click navigate to the decision, never past it: open the PR, the issue, or the repo, but
never run a `dispatch` command on the human's behalf. `alerter` blocks until answered or timed out,
so always pass `-timeout` — the hook runs synchronously (see below).

`[VERIFY]` `alerter` is not installed here, so unlike the table above its flags and its exit
behaviour come from its own documentation rather than a local test. Check `alerter -help` after
installing. The `DISPATCH_*` values the snippet reads are dispatch's own and are verified.

## Channels

Every notification attempts a terminal bell. On macOS it also uses `terminal-notifier`, or
`osascript` (`display notification ... with title ... subtitle ...`) when `terminal-notifier` is
unavailable. If `DISPATCH_NOTIFY_CMD` names a trusted local executable, dispatch runs it with three
arguments: issue number, state, and the one-line headline. Use a wrapper script when fixed flags
are needed. The headline flattens the same fields in the same order:

```text
#<n> <state> · <repo> — <action>
```

The hook also receives `DISPATCH_ISSUE`, `DISPATCH_STATE`, `DISPATCH_PROVIDER`, `DISPATCH_MODEL`,
`DISPATCH_REPO`, `DISPATCH_REPO_ROOT`, `DISPATCH_NEXT_ACTION`, `DISPATCH_PR_URL` (written by
`dispatch pr`, empty until a PR exists), and `DISPATCH_MESSAGE` (the headline). Treat these values as untrusted data. Hook failures are ignored. Set
`DISPATCH_NOTIFY=off` to disable every channel.

## ntfy hook

Put this executable on `PATH` as `dispatch-ntfy`:

```sh
#!/bin/sh
curl -fsS \
  -H "Title: #$DISPATCH_ISSUE $DISPATCH_STATE · $DISPATCH_REPO" \
  -d "$DISPATCH_NEXT_ACTION" \
  "https://ntfy.sh/your-private-topic"
```

The push mirrors the banner: job and outcome in the notification title, next action in the body.
Use `-d "$DISPATCH_MESSAGE"` instead if you want the whole headline in one line.

Then start dispatch with:

```sh
export DISPATCH_NOTIFY_CMD=dispatch-ntfy
```

The hook runs synchronously, so keep it fast. The exit code is already on disk before the hook
runs.
