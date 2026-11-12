#!/bin/bash
# Builds ~/BurrowStress/base: the demo vault (without its KV cache, Ledger or saved sessions), the Matatu code linked into it,
# and session 1 done by Claude Code, which keeps the finance decision in the Ledger. Every stress workflow starts from here.
set -e
. "$(dirname "$0")/lib.sh"
# A fresh run folder: rsync's --exclude below also protects excluded paths from --delete, so an old Ledger or saved
# sessions left in the run folder would otherwise leak into the base (13 November).
rm -rf "$R/Notes/.burrow/ledger" "$R/Notes/.burrow/sessions" "$R/Notes/.burrow/notes" "$R/Notes/.burrow/kv"
mkdir -p "$R"
rsync -a --delete --exclude .burrow/kv --exclude .burrow/ledger --exclude .burrow/sessions --exclude .burrow/notes \
  "$HOME/BurrowDemo/Notes/" "$R/Notes/"
echo '[]' > "$R/Notes/.burrow/folders.json"
~/Developer/burrow/docs/demo/tapes/08-coding-setup.sh "$R/Notes" "$R/code"
python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["agent"]["coder"]["prompt"])' "$R/code/opencode.json" > "$R/code/coder-prompt.md"
printf '{"mcpServers": {"burrow": {"command": "%s", "args": ["mcp", "%s"]}}}\n' "$(command -v burrow)" "$R/Notes" > "$R/code/claude-mcp.json"

claude_run "Do the task in task-01.md." "$OUTDIR/base-session1.json"
echo "session 1: $(score "$R/hidden-tests" | cut -d' ' -f1)"
cat "$R/Notes/.burrow/ledger/main/"*.md
# As in clip 08: session 1's work is committed and the typed-reference tests arrive before session 2.
g() { git -C "$R/code/matatu" -c user.name=demo -c user.email=demo@example.com "$@"; }
find "$R/code/matatu" -name __pycache__ -type d -prune -exec rm -r {} +
g add -A && g commit -qm 'Unknown references go to suspense'
cp "$R/code/tests-later/test_reconcile_typed_refs.py" "$R/code/matatu/tests/" && g add -A && g commit -qm 'Tests for typed references'
# Session 1's brief leaves with session 1, so a later session can learn the decision only through Burrow
# (the first relay run read it with cat instead).
rm "$R/code/task-01.md"
mkdir -p "$STRESS/base"
rsync -a --delete "$R/" "$STRESS/base/"
echo "base ready"
