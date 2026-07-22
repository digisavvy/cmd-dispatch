# Notifications

Each generated `run.sh` writes the worker's `exitcode`, then calls `dispatch notify` with `DONE` or
`FAILED(code)`. Notification delivery is best-effort and does not change the worker result.

`dispatch notify` also supports `STALLED`. The status command detects and displays that state, but
does not itself send a notification; a caller that wants a stalled alert must invoke
`dispatch notify <issue#> STALLED`.

## Payload and channels

The payload names the job and next action:

```text
[dispatch] #<n> <state> — <model> on <repo>. Next: <action>
```

Default actions are:

- `DONE`: `review & merge: dispatch pr <n>`
- `FAILED(code)`: `worker errored — inspect: dispatch logs <n>`
- `STALLED`: `may be stuck / awaiting something — check: dispatch logs <n> -f`

Every notification attempts a terminal bell. On macOS it also uses `terminal-notifier`, or
`osascript` when `terminal-notifier` is unavailable. If `DISPATCH_NOTIFY_CMD` is set, dispatch runs
that command with three arguments: issue number, state, and the full payload.

The hook also receives `DISPATCH_ISSUE`, `DISPATCH_STATE`, `DISPATCH_PROVIDER`, `DISPATCH_MODEL`,
`DISPATCH_REPO`, `DISPATCH_REPO_ROOT`, `DISPATCH_NEXT_ACTION`, `DISPATCH_PR_URL`, and
`DISPATCH_MESSAGE`. Hook failures are ignored. Set `DISPATCH_NOTIFY=off` to disable every channel.

## ntfy hook

Put this executable on `PATH` as `dispatch-ntfy`:

```sh
#!/bin/sh
curl -fsS \
  -H "Title: dispatch #$DISPATCH_ISSUE $DISPATCH_STATE" \
  -d "$DISPATCH_MESSAGE" \
  "https://ntfy.sh/your-private-topic"
```

Then start dispatch with:

```sh
export DISPATCH_NOTIFY_CMD=dispatch-ntfy
```

The hook runs synchronously, so keep it fast. The exit code is already on disk before the hook
runs.
