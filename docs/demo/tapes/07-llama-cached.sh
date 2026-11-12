#!/bin/bash
# Clip 07: starts llama-server fresh, with Burrow as its MCP server, then records the chat page headless.
# Temperature 0 and seed 7, as in the KV trial (trials/results/kv-1), so a run can be repeated.
# Usage: tapes/07-llama-cached.sh <out-folder> [turns]
set -e
OUT=${1:?out folder}; mkdir -p "$OUT"
MODEL=~/.ollama/models/blobs/sha256-85e4a5b7b8ef0e48af0e8658f5aaab9c2324c76c1641493f4d1e25fce54b18b9   # Qwen3 4B Instruct 2507 Q4_K_M
cat > ~/BurrowDemo/llama-mcp.json <<JSON
{"mcpServers": {"burrow": {"command": "$HOME/.local/bin/burrow", "args": ["mcp", "$HOME/BurrowDemo/Notes", "--llama", "http://127.0.0.1:8080"]}}}
JSON
pkill -f "llama-server.*--port 8080" || true; sleep 2
llama-server -m $MODEL -a qwen3-4b-instruct --jinja -c 65536 -np 2 -fa on -ctk q8_0 -ctv q8_0 --temp 0 --seed 7 --port 8080 \
  --slot-save-path ~/BurrowDemo/Notes/.burrow/kv --mcp-servers-config ~/BurrowDemo/llama-mcp.json > "$OUT/llama-server.log" 2>&1 &
until curl -s localhost:8080/health | grep -q ok; do sleep 1; done
PLAYWRIGHT=${PLAYWRIGHT:-$HOME/lemo-opuscar/node_modules/playwright-core} OUT="$OUT" TURNS=${2:-3} node "$(dirname "$0")/07-llama-cached.mjs"
pkill -f "llama-server.*--port 8080" || true
ffmpeg -loglevel error -y -i "$OUT/07-llama-cached.webm" -c:v libx264 -pix_fmt yuv420p -crf 18 "$OUT/07-llama-cached.mp4"
