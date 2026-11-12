#!/bin/bash
# The gap fixes (D-74 to D-80), proved the way Burrow is used: real models in real programs, on one base.
#   1. the base, with the new Burrow (session 1 by Claude Code, its brief removed afterwards)
#   2. 4a at 32 x 50                                   D-78: commit time as the Ledger grows
#   3. Claude, session 2: 6 control runs, 3 README     D-74: reasons kept; D-80: steering text shown to the person
#   4. two agents at once, 1 run                       D-77: handoffs cite what was used, on the right branch
#   5. Gemma 4 12B in OpenCode, session 2, 4 runs      D-75, D-76, D-79: the main gap (clip 08 kept to it 1 of 4)
#   6. the same 4 Gemma runs with the Burrow from before the fixes (537cc3f), same base
# Usage: proof.sh <path to the Burrow binary from before the fixes>
set -e
. "$(dirname "$0")/lib.sh"
OLD=${1:?old burrow binary}
NEW=$HOME/Developer/burrow/.build/release/burrow
install_burrow() { rm -f "$HOME/.local/bin/burrow"; cp "$1" "$HOME/.local/bin/burrow"; }

install_burrow "$NEW"
echo "== 1. base"; "$HERE/base.sh" > "$OUTDIR/base.log" 2>&1; tail -3 "$OUTDIR/base.log"
grep -h "^Because:\|^Rejected:" "$STRESS/base/Notes/.burrow/ledger/main/"*.md || echo "(session 1 kept no reasons)"

echo "== 2. 4a, 32 x 50"; restore
python3 "$HERE/concurrent.py" "$R/Notes" 32 50 > "$OUTDIR/w4a-32x50.json"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["commits_wanted"], d["commit_files_written"], d["errors"], "commit p50/p95", d["commit_seconds_p50_p95"], "find", d["find_seconds_p50_p95"])' "$OUTDIR/w4a-32x50.json"

echo "== 3. Claude, session 2"; "$HERE/w23.sh" claude 6 control > "$OUTDIR/w23-control.log" 2>&1; grep -v "^embedded" "$OUTDIR/w23-control.log"
"$HERE/w23.sh" claude 3 readme > "$OUTDIR/w23-readme.log" 2>&1; grep -v "^embedded" "$OUTDIR/w23-readme.log"

echo "== 4. two agents at once"; "$HERE/w4b.sh" 1 > "$OUTDIR/w4b.log" 2>&1; tail -1 "$OUTDIR/w4b.jsonl"

gemma() {
  local label=$1
  for run in 1 2 3 4; do
    restore
    s=$(date +%s)
    gemma_run "Do the task in task-04.md." "$OUTDIR/gemma-$label-$run.json" || true
    took=$(( $(date +%s) - s ))
    ollama stop burrow-gemma4-12b-32k > /dev/null 2>&1 || true
    git -C "$R/code/matatu" diff > "$OUTDIR/gemma-$label-$run.diff"
    session=$(ls -t "$R/Notes/.burrow/sessions/"*.json | head -1)
    tools=$(python3 -c 'import json,sys; print(" ".join(t["tool"] + (":" + t["asked"][:30] if t["asked"] else "") for t in json.load(open(sys.argv[1])).get("trail", [])))' "$session")
    echo "{\"binary\": \"$label\", \"run\": $run, \"seconds\": $took, \"score\": \"$(score "$R/hidden-tests")\", \"burrow_calls\": \"$tools\"}" >> "$OUTDIR/gemma-session2.jsonl"
    echo "$label $run: $took s, $(score "$R/hidden-tests") | $tools"
  done
}
echo "== 5. Gemma, new Burrow"; gemma new
install_burrow "$OLD"
echo "== 6. Gemma, Burrow before the fixes"; gemma old
install_burrow "$NEW"
echo "proof done"
