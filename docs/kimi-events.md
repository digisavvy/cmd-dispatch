# Kimi Code `--output-format stream-json` event vocabulary

Captured from a real `kimi -p … --output-format stream-json` run (kimi-code 0.28.1, model
`moonshot-ai/kimi-k3`, 2026-07-21). Kimi is wired as a native dispatch provider via the
**kimi-code CLI** (`~/.kimi-code/bin/kimi`, API key configured in `~/.kimi-code/config.toml`).

## Events key on `role` (not `type` like claude)

| `.role` | fields | meaning |
|---|---|---|
| `assistant` | `.content` (string) | model message; the **final message** is the last `assistant` `.content` |
| `tool` | tool call payload | a tool invocation (file edit, shell, git) |
| `meta` | `.type` (e.g. `session.resume_hint`), `.session_id` | session metadata |

```json
{"role":"assistant","content":"ok"}
{"role":"tool", ...}
{"role":"meta","type":"session.resume_hint","session_id":"session_…","command":"kimi -r …"}
```

## Worker invocation (in `bin/dispatch`)

```
( cd "$wt" && kimi -p "$(cat prompt.txt)" -m moonshot-ai/kimi-k3 \
    --output-format stream-json --add-dir "$gitcommon" ) > events.jsonl 2> worker.log
```

## Gotchas

- **Model alias is provider-prefixed:** `moonshot-ai/kimi-k3`, not bare `kimi-k3` — must match a
  `[models."…"]` entry in `~/.kimi-code/config.toml`.
- **`-p` mode auto-runs tools** — it rejects `-y`/`--auto` ("cannot combine with --prompt") because
  prompt mode is already non-interactive; tools execute without an approval flag.
- Runs in **cwd** (no `-C` flag) → `cd` into the worktree. `--add-dir <git-common-dir>` lets it commit
  inside a worktree (same as codex/claude).
- Final message derived as `jq -r 'select(.role=="assistant") | .content' | tail -1`.
