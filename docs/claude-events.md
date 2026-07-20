# Claude `--output-format stream-json` event vocabulary

Captured from a real `claude -p "say ok" --output-format stream-json --verbose` run with Claude Code
2.1.170 on 2026-07-20. This CLI requires `--verbose` with stream JSON. The local CLI was not
authenticated, so the observed assistant and result records contain the login error; their envelope is
still the real stream emitted by the CLI.

## Observed top-level events

| `.type` | Relevant fields |
|---|---|
| `system` | `.subtype == "init"`, `.cwd`, `.session_id`, `.model`, `.tools[]` |
| `assistant` | `.message.content[]`, whose text blocks have `{type:"text", text}` |
| `result` | `.subtype`, `.is_error`, `.result`, `.usage`, `.session_id` |

The observed lifecycle was `system` → `assistant` → `result`. Assistant content is an array. Dispatch
also recognizes a `tool_use` content block by its `.name` when one appears in that content envelope.

```json
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Not logged in · Please run /login"}]},"error":"authentication_failed"}
{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login","num_turns":1}
```

Claude writes stream JSON to stdout and diagnostics to stderr. The final message is the last `.result`
(falling back to `.text`) from a `result` record.
