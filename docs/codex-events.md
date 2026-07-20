# Codex `exec --json` event vocabulary

Captured from a real `codex exec --json` run (codex-cli 0.144.6, gpt-5.6/5.4 family, 2026-07-20)
on a task that wrote a file and ran a shell command. This is the ground truth for parsing worker
event streams (`.dispatch/jobs/<n>/events.jsonl`) — build TUIs/status on these, not assumptions.

## Top-level events (`.type`)

Ordered lifecycle of one worker turn:

```
thread.started      { thread_id }
turn.started        {}
item.started        { item }      ← item.status: "in_progress"  (live "currently doing X")
item.completed      { item }      ← item.status: "completed"
… (item.started/completed repeat per action) …
turn.completed      { usage: { input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens } }
```

## Item payloads (`.item.type`)

| item.type           | key fields                                                        |
|---------------------|-------------------------------------------------------------------|
| `agent_message`     | `.item.text` — the model's prose                                  |
| `file_change`       | `.item.changes[]` = `{ path, kind: add\|modify\|delete }`, `.item.status` |
| `command_execution` | `.item.command`, `.item.aggregated_output`, `.item.exit_code`, `.item.status` |

### Sample lines

```json
{"type":"item.started","item":{"id":"item_1","type":"file_change","changes":[{"path":".../util.py","kind":"add"}],"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"/bin/zsh -lc \"python3 -c 'import util; print(util.add(2,3))'\"","aggregated_output":"5\n","exit_code":0,"status":"completed"}}
{"type":"turn.completed","usage":{"input_tokens":26622,"cached_input_tokens":19968,"output_tokens":218,"reasoning_output_tokens":0}}
```

## Gotchas

- **stdin must be closed.** `codex exec "<prompt>"` with a non-TTY stdin *also reads stdin* and
  will hang ("Reading additional input from stdin…") waiting for EOF. Dispatch workers are safe
  because `nohup` supplies `/dev/null`; any manual/ad-hoc `codex exec` needs `< /dev/null`.
- **`--json` puts events on stdout, human progress on stderr.** Dispatch splits these into
  `events.jsonl` (stdout) and `worker.log` (stderr).
- No `ApprovalRequested`-style events in our flow — workers run `--sandbox workspace-write`
  non-interactively, so nothing pauses for approval.
- Event taxonomy here is coarser than the richer `ToolOutputDelta`/`AssistantMessageDelta` set
  Codex's *interactive/app-server* interface exposes; `exec --json` is what we get.
