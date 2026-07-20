#!/usr/bin/env bash
# Install dispatch: put the CLI on PATH and the slash command where Claude Code finds it.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BIN_DIR="${DISPATCH_BIN_DIR:-$HOME/.local/bin}"
CMD_DIR="${DISPATCH_CMD_DIR:-$HOME/.claude/commands}"

mkdir -p "$BIN_DIR" "$CMD_DIR"
ln -sf "$SRC/bin/dispatch" "$BIN_DIR/dispatch"
ln -sf "$SRC/commands/dispatch.md" "$CMD_DIR/dispatch.md"

# models.conf: copy (don't symlink) so edits don't collide with git updates, unless it exists.
if [[ ! -f "$SRC/models.conf" ]]; then cp "$SRC/models.conf.example" "$SRC/models.conf" 2>/dev/null || true; fi

echo "installed:"
echo "  CLI:     $BIN_DIR/dispatch  ->  $SRC/bin/dispatch"
echo "  command: $CMD_DIR/dispatch.md  (use /dispatch in Claude Code)"
echo
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) echo "NOTE: $BIN_DIR is not on your PATH. Add to ~/.zshrc:"; echo "      export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
echo "next: codex login   then:  dispatch doctor"
