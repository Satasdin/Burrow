#!/bin/bash
# Clip 08c: session 2 of clip 08 again, with Claude Code in place of Gemma, on the same vault and the same code.
# Run after tapes/08-coding-session.sh. It saves session 2's change as a patch, puts the code back to where
# session 1 left it, and records Claude Code doing the same task with the same instructions and the same
# four kinds of tool (read, edit, write, shell) plus Burrow. Burrow's Ledger is not touched: it still holds
# session 1's decision, as it did when Gemma started session 2.
# Usage: tapes/08c-claude-session.sh <vault> <code-folder> <output.mp4>
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
VAULT=$(cd "$1" && pwd); CODE=$(cd "$2" && pwd); OUT=$3
[ -z "$(git -C "$CODE/matatu" status --porcelain)" ] || git -C "$CODE/matatu" diff > "${OUT%.mp4}-gemma-session2.diff"
git -C "$CODE/matatu" checkout -- .
burrow index "$VAULT" --vault | tail -1

# The same instructions OpenCode's coder agent had, word for word.
python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["agent"]["coder"]["prompt"])' "$CODE/opencode.json" > "$CODE/coder-prompt.md"
# Burrow is the only MCP server Claude Code sees.
printf '{"mcpServers": {"burrow": {"command": "%s", "args": ["mcp", "%s"]}}}\n' "$(command -v burrow)" "$VAULT" > "$CODE/claude-mcp.json"

sed -e "s|{CODE}|$CODE|g" -e "s|{VAULT}|$VAULT|g" -e "s|{OUT}|$OUT|" "$HERE/08c-claude-session.tape" > "$CODE/08c.tape"
# A clean environment, as from a fresh terminal: nothing from the shell this is started in reaches Claude Code.
env -i HOME="$HOME" USER="$USER" LOGNAME="$LOGNAME" LANG=en_US.UTF-8 TERM=xterm-256color PATH="$PATH" vhs "$CODE/08c.tape"
