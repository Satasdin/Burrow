#!/bin/bash
# Clip 08 setup: the Matatu trial project as a git repository in <code>/matatu, linked read-only into the vault,
# and an OpenCode config with a coder agent on Gemma 4 12B (32k window, declared so OpenCode compacts).
# OpenCode runs in <code>, so a file's path there is the same as its path in the vault (matatu/matatu/...).
# Usage: tapes/08-coding-setup.sh <vault> <code-folder>
set -e
VAULT=$(cd "$1" && pwd); mkdir -p "$2"; CODE=$(cd "$2" && pwd)
P=~/Developer/burrow/trials/projects/matatu
rm -rf "$CODE/matatu"; cp -R $P/base "$CODE/matatu"
mkdir -p "$CODE/matatu/tests"; touch "$CODE/matatu/tests/__init__.py"
cp $P/sessions/01/tests/test_task.py "$CODE/matatu/tests/test_reconcile_unknown.py"
git -C "$CODE/matatu" init -q && git -C "$CODE/matatu" add -A
git -C "$CODE/matatu" -c user.name=demo -c user.email=demo@example.com commit -qm "Matatu back office"
burrow link "$VAULT" "$CODE/matatu"
burrow index "$VAULT" --vault | tail -1
# Tests added before session 2, and the hidden check of the session 1 decision (run only after session 2).
# The hidden tests sit beside the code folder, out of the model's reach.
JUDGE="$(dirname "$CODE")/hidden-tests"; rm -rf "$JUDGE"
mkdir -p "$CODE/tests-later" "$JUDGE"
cp $P/sessions/04/tests/test_task.py "$CODE/tests-later/test_reconcile_typed_refs.py"
cp $P/sessions/04/tests/test_decisions.py "$JUDGE/test_decisions.py"
for n in 01 04; do { echo "# Task"; cat $P/sessions/$n/brief.md; } > "$CODE/task-$n.md"; done
echo "When the tests pass, keep the decision from the Discussion in Burrow's Ledger: what was decided and what was rejected, citing the file you changed." >> "$CODE/task-01.md"
cat > "$CODE/opencode.json" <<JSON
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "ollama/burrow-gemma4-12b-32k",
  "default_agent": "coder",
  "provider": {"ollama": {"npm": "@ai-sdk/openai-compatible", "name": "Ollama", "options": {"baseURL": "http://127.0.0.1:11434/v1"},
    "models": {"burrow-gemma4-12b-32k": {"name": "Gemma 4 12B", "tools": true, "limit": {"context": 32768, "output": 4096}}}}},
  "mcp": {"burrow": {"type": "local", "command": ["$HOME/.local/bin/burrow", "mcp", "$VAULT"], "enabled": true}},
  "agent": {"coder": {
    "description": "Codes in the Matatu repository, with the project held in Burrow.",
    "mode": "primary",
    "temperature": 0,
    "prompt": "You work on the Matatu codebase in the folder matatu. Burrow holds the same folder, with the same paths, and what earlier sessions decided. Find code and decisions with the burrow tools, read and edit files with their paths as Burrow gives them, and run the tests with: cd matatu && python3 -m unittest discover -s tests. Do not change the existing tests; add new test files if you need them, and delete any scratch files you make.",
    "tools": {"*": false, "burrow_*": true, "read": true, "edit": true, "write": true, "bash": true},
    "steps": 40}}
}
JSON
echo "ready: $CODE"
