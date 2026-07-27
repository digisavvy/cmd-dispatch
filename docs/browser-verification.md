# Browser verification

The cowork browser worker is an autonomous agent running as a launchd service
(`cowork-code-mcp-server`) that drives a headless Playwright browser via Helium with pre-seeded
admin sessions. It accepts tasks from the shared queue, executes them in a real browser, and writes
results — including screenshot evidence paths under `~/.cowork-code-mcp/evidence/` — back to the
task row. Setup instructions are in the
[cowork-code-mcp-server README](https://github.com/DigiSavvy-Inc/cowork-code-mcp-server).

## What it can do

- Load authenticated admin pages (WordPress wp-admin, app dashboards, protected routes)
- Verify visible content, UI state, form values, and error/success messages
- Capture screenshots as evidence, cited by path in the `result` field
- Execute read-only user flows (navigate, assert, inspect) — not write operations unless the
  issue explicitly authorizes them

## Queueing a task (sqlite3)

Workers that cannot reach the cowork-bridge MCP tools (Codex, Kimi) write directly to the
SQLite database:

```sh
TASK_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

sqlite3 ~/.cowork-code-mcp/messages.db "
  INSERT INTO tasks (id, sender, recipient, title, status, description, created_at, updated_at)
  VALUES (
    '$TASK_ID',
    'code',
    'cowork',
    'Verify site title (read-only)',
    'pending',
    'READ-ONLY. Navigate to https://example.com/wp-admin/options-general.php and confirm the
     site title field reads \"My Site\". Capture a full-page screenshot. Put pass/fail and the
     evidence path in result.',
    '$NOW',
    '$NOW'
  );"

# Poll until completed or failed (typically < 5 min; stuck in_progress auto-fails after 60 min)
while true; do
  STATUS=$(sqlite3 ~/.cowork-code-mcp/messages.db \
    "SELECT status FROM tasks WHERE id='$TASK_ID';")
  [ "$STATUS" = "completed" ] || [ "$STATUS" = "failed" ] && break
  sleep 30
done

sqlite3 ~/.cowork-code-mcp/messages.db \
  "SELECT status, result FROM tasks WHERE id='$TASK_ID';"
```

## Task-writing rules

Write the `description` field as if you will never see the worker again — it must be
self-contained:

- **URL and exact expectations.** State the full URL, the specific element or value to verify,
  and the expected outcome. Avoid "check if it looks right."
- **Read-only by default.** Start the description with `READ-ONLY.` unless the issue explicitly
  authorizes browser writes. State the blast radius explicitly when changes are allowed.
- **Request screenshot evidence.** Say "Capture a screenshot" and ask for the evidence path in
  `result`. Without this, a passing run leaves no proof.
- **One goal per task.** Split multi-page verification into separate tasks so a failure on one
  page doesn't silently skip the others.
- **What goes in `result`.** Tell the worker exactly what to put there: pass/fail verdict,
  evidence path, any extracted value. The foreman reads `result` raw.

## MCP alternative (Claude workers)

Claude workers inherit the cowork-bridge MCP tools and can queue tasks without touching sqlite3:

```
create_task(recipient="cowork", description="READ-ONLY. ...")
```

Poll with `get_tasks` until `status` is `completed` or `failed`, then read the `result` field.
The queue is the same — sqlite3 and MCP writes land in the same database.
