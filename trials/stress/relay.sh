#!/bin/bash
# Workflow 1: one project handed between three models in three programs, sharing nothing but Burrow.
#   1. Gemma 4 12B in OpenCode does session 1 and keeps the finance decision.
#   2. Claude Code (Opus 5.5) does session 2, the typed references.
#   3. Qwen3 4B in llama.cpp's chat page is asked what was decided, by whom, and what the last session changed.
# Usage: relay.sh
set -e
. "$(dirname "$0")/lib.sh"
OUT=$OUTDIR/relay; mkdir -p "$OUT"
restore
# Back to before session 1: the first commit of the code, and an empty Ledger.
git -C "$R/code/matatu" reset -q --hard HEAD~2
find "$R/Notes/.burrow/ledger" "$R/Notes/.burrow/sessions" -type f -delete
burrow index "$R/Notes" --vault > /dev/null

echo "leg 1: Gemma in OpenCode, session 1"; s=$(date +%s)
gemma_run "Do the task in task-01.md." "$OUT/leg1-gemma.json"
echo "  $(( $(date +%s) - s )) s, $(score "$R/hidden-tests" | cut -d' ' -f1)"
ollama stop burrow-gemma4-12b-32k 2>/dev/null || true
g() { git -C "$R/code/matatu" -c user.name=demo -c user.email=demo@example.com "$@"; }
find "$R/code/matatu" -name __pycache__ -type d -prune -exec rm -r {} +
g diff > "$OUT/leg1.diff"; g add -A; g commit -qm 'Session 1' || true
cp "$R/code/tests-later/test_reconcile_typed_refs.py" "$R/code/matatu/tests/" && g add -A && g commit -qm 'Tests for typed references'
burrow log "$R/Notes" > "$OUT/after-leg1.log"
# Session 1's brief leaves the folder with session 1: from here on the decision can only come through Burrow.
# (The first relay run, 12 November, left it there, and Claude Code read it with cat instead of asking Burrow.)
rm "$R/code/task-01.md"

echo "leg 2: Claude Code, session 2"; s=$(date +%s)
claude_run "Do the task in task-04.md." "$OUT/leg2-claude.json"
echo "  $(( $(date +%s) - s )) s, $(score "$R/hidden-tests")"
g diff > "$OUT/leg2.diff"
burrow log "$R/Notes" > "$OUT/after-leg2.log"

echo "leg 3: Qwen in llama.cpp"
MODEL=~/.ollama/models/blobs/sha256-85e4a5b7b8ef0e48af0e8658f5aaab9c2324c76c1641493f4d1e25fce54b18b9   # Qwen3 4B Instruct 2507 Q4_K_M
printf '{"mcpServers": {"burrow": {"command": "%s", "args": ["mcp", "%s", "--llama", "http://127.0.0.1:8080"]}}}\n' "$(command -v burrow)" "$R/Notes" > "$OUT/llama-mcp.json"
pkill -f "llama-server.*--port 8080" || true; sleep 2
llama-server -m $MODEL -a qwen3-4b-instruct --jinja -c 65536 -np 2 -fa on -ctk q8_0 -ctv q8_0 --temp 0 --seed 7 --port 8080 \
  --mcp-servers-config "$OUT/llama-mcp.json" > "$OUT/llama-server.log" 2>&1 &
until curl -s localhost:8080/health | grep -q ok; do sleep 1; done
QUESTIONS='["Using my Burrow vault: pick up the Matatu project where the last sessions stopped. What was decided about matching statement lines to tickets, what was rejected, and which model and program kept each decision?", "What did the most recent session change, and does that change keep to the earlier decision? Name the file."]' \
  OUT="$OUT/leg3" PLAYWRIGHT=${PLAYWRIGHT:-$HOME/lemo-opuscar/node_modules/playwright-core} node "$HERE/llama-ask.mjs"
pkill -f "llama-server.*--port 8080" || true
burrow log "$R/Notes" > "$OUT/after-leg3.log"
echo "relay done"
