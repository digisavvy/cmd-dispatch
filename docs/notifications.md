# Notifications

Each generated `run.sh` writes the worker's `exitcode`, then calls `dispatch notify` with `DONE` or
`FAILED(code)`. Notification delivery is best-effort and does not change the worker result.

`dispatch notify` also supports `STALLED`. The status command detects and displays that state, but
does not itself send a notification; a caller that wants a stalled alert must invoke
`dispatch notify <issue#> STALLED`.

The merge gate sends its own notifications on every verdict: `APPROVE` (with the PR URL),
`REJECT` (pointing at the saved report), and `REWORK` when a rejection is fed back to the worker
for another attempt (see [gate.md](gate.md)).

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
