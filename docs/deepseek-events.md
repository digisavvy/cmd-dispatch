# DeepSeek `--output-format stream-json` event vocabulary

DeepSeek has no CLI of its own. A deepseek worker runs the **claude CLI** with the env prelude from
`deepseek_env_prelude()` (`bin/dispatch:89`) pointing it at DeepSeek's Anthropic-compatible endpoint,
so the stream arrives off the same `--output-format stream-json --verbose` flags a claude worker uses.

The flags are shared; the vocabulary is **not**. This file is the ground truth for parsing a deepseek
worker's event stream (`.dispatch/jobs/<n>/events.jsonl`) — do not reuse claude's assumptions.

Captured from a completed `deepseek-flash[1m]` job on 2026-09-18.

## Observed top-level events

`.type | .subtype` over a whole job, by count:

| `.type` | `.subtype` | count | notes |
|---|---|---|---|
| `system` | `thinking_tokens` | 19055 | one record per thinking batch — the stream is dominated by these |
| `assistant` | – | 67 | `.message.content[]` (shared claude envelope) |
| `user` | – | 38 | tool results echoed back |
| `system` | `init` | 1 | session preamble |
| `system` | `vcs_state_changed` | 1 | |
| `system` | `permission_denied` | 1 | |
| — | `hook_started` / `hook_response` | 1 | recorded as a pair in this capture |
| `result` | `success` | 1 | terminal record |

The hook pair above was recorded without a distinct `.type` in the capture summary; the rows that
matter for dispatch are `system`, `assistant`, `user`, and `result`.

`[VERIFY]` Only `.type` and `.subtype` were captured verbatim. The payload internals of
`system`/`thinking_tokens`, `system`/`vcs_state_changed`, `system`/`permission_denied`, and the hook
pair are unconfirmed — dispatch reads none of them, so nothing here depends on their shape.

## Lifecycle

`system`/`init` → a long, mostly-`thinking_tokens` run of `system` records interleaved with
`assistant` and `user` → `system`/`permission_denied` and `system`/`vcs_state_changed` where they
occur → one `result`.

The `result` record is the terminal event and the only one carrying the worker's prose:

```json
{"type":"result","subtype":"success","result":"…"}
```

`[VERIFY]` Again, only `.type` and `.subtype` were captured verbatim for this record. `.result` is
populated — `bin/dispatch:552` reads it successfully to write `last_message.txt` — but the other
payload fields dispatch does not read are unconfirmed.

## Where the vocabulary diverges from claude's

- **`system` is a high-frequency record type, not a one-shot.** Claude's documented stream carries a
  single `system` record — `init` ([claude-events.md](claude-events.md)). DeepSeek emits one per
  thinking batch. Any consumer that keys on `.type == "system"` alone will treat ~19k thinking
  records and the `init` record as the same thing.
- **Thinking is surfaced as `system` events, not as assistant content.** The 19055
  `thinking_tokens` records carry no message text, so a window of the stream can contain no readable
  progress at all while the worker is working.
- **`user` records are common**, not occasional — tool results are echoed back as top-level `user`
  events (38 here).
- **Extra `system` subtypes appear** that claude's documented vocabulary does not list:
  `vcs_state_changed`, `permission_denied`.
- **The `result` record is unchanged**, which is why the final-message extraction in `bin/dispatch`
  is shared verbatim between claude and deepseek — and why deepseek inherits its multi-line
  limitation rather than trading for a different one.

## What dispatch extracts

`render_event()` (`bin/dispatch:181`) picks its branch from `provider=` in the job's `meta`
(`bin/dispatch:183`). deepseek shares the claude branch (`bin/dispatch:197`):

| record | rendered as | line |
|---|---|---|
| `assistant` | `msg: …` (first 120 chars) or `tool: <name>` | `bin/dispatch:200` |
| `result` | `result: …` (first 120 chars) | `bin/dispatch:201` |
| `system` | the literal string `started` — `.subtype` is never read | `bin/dispatch:202` |
| anything else | the bare `.type` | `bin/dispatch:202` |

The final message is written to `.dispatch/jobs/<n>/last_message.txt` by `bin/dispatch:552`.
Liveness (`RUNNING` vs `STALLED`) is decided from the mtime of `events.jsonl`, not from its contents
(`bin/dispatch:165`).

## Worker invocation (in `bin/dispatch`)

```
(
<deepseek_env_prelude>
  cd "$wt" && claude -p "$(cat prompt.txt)" --model deepseek-flash[1m] \
    --output-format stream-json --verbose --add-dir "$gitcommon" \
    --permission-mode acceptEdits ) \
  > events.jsonl 2> worker.log
```

## Gotchas

- **`system` records poison both `logs --events` and the status line.** The renderer collapses every
  one of them to `started`, so a log window fills with identical lines that name no tool and no
  message. See [troubleshooting.md](troubleshooting.md).
- **A multi-paragraph `result` is truncated to its last line** by the `tail -1` at
  `bin/dispatch:552`; read `.result` directly if you need the whole report. See
  [troubleshooting.md](troubleshooting.md).
- **The prelude lives inside the worker's subshell.** It reaches the worker and nothing else — not
  the foreman's shell, and not an auto-gate spawned further down `run.sh`. That containment keeps
  cross-provider gating honest; do not hoist it out (`bin/dispatch:544`).
