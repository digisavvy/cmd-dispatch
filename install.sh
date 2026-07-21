#!/usr/bin/env bash
# Install dispatch: put the CLI on PATH and the slash command where Claude Code finds it.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="${DISPATCH_BIN_DIR:-$HOME/.local/bin}"
CMD_DIR="${DISPATCH_CMD_DIR:-$HOME/.claude/commands}"

mkdir -p "$BIN_DIR" "$CMD_DIR"
ln -sf "$SRC/bin/dispatch" "$BIN_DIR/dispatch"
# Symlink every slash command (dispatch, pick, …)
for cmd in "$SRC"/commands/*.md; do ln -sf "$cmd" "$CMD_DIR/$(basename "$cmd")"; done

# Symlink skills (dispatch, …) into Claude Code's skills dir
SKILL_DIR="${DISPATCH_SKILL_DIR:-$HOME/.claude/skills}"
mkdir -p "$SKILL_DIR"
for s in "$SRC"/skills/*/; do [ -d "$s" ] && ln -sfn "${s%/}" "$SKILL_DIR/$(basename "$s")"; done

# Kimi Code lives at ~/.kimi-code/bin/kimi (separate install); symlink it onto PATH if present,
# so the 'kimi' provider is detected by 'dispatch doctor'.
if [ -x "$HOME/.kimi-code/bin/kimi" ] && ! command -v kimi >/dev/null 2>&1; then
  ln -sf "$HOME/.kimi-code/bin/kimi" "$BIN_DIR/kimi" && echo "  linked: $BIN_DIR/kimi -> ~/.kimi-code/bin/kimi"
fi

# models.conf: copy (don't symlink) so edits don't collide with git updates, unless it exists.
if [[ ! -f "$SRC/models.conf" ]]; then cp "$SRC/models.conf.example" "$SRC/models.conf" 2>/dev/null || true; fi

echo "installed:"
echo "  CLI:     $BIN_DIR/dispatch  ->  $SRC/bin/dispatch"
echo "  commands: $CMD_DIR/{dispatch,pick}.md  (use /dispatch and /pick in Claude Code)"
echo
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) echo "NOTE: $BIN_DIR is not on your PATH. Add to ~/.zshrc:"; echo "      export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
echo "next: codex login   then:  dispatch doctor"
