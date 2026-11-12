#!/bin/bash
# Workflow 4b: two Claude Code agents at once on one vault and one checkout.
#   A: session 2 (task-04, typed references, payments/) on the Ledger's main branch, where session 1's decision is.
#   B: session 03 (luggage charge, fares/), told to keep its decision on the Ledger branch "luggage".
# Checks: both tasks pass their tests, A keeps session 1's decision, each handoff cites only its own session's files,
# the luggage decision stays off main, and `burrow resume` on each branch shows the right work.
# Usage: w4b.sh <runs>
set -e
. "$(dirname "$0")/lib.sh"
P=~/Developer/burrow/trials/projects/matatu
OUT=$OUTDIR/w4b.jsonl
for run in $(seq 1 "${1:-1}"); do
  restore
  { echo "# Task"; cat $P/sessions/03/brief.md
    echo "When the tests pass, keep what you decided about the luggage charge in Burrow's Ledger on the branch luggage, citing the file you changed."; } > "$R/code/task-03.md"
  mkdir -p "$R/hidden-03"; cp $P/sessions/03/tests/test_task.py "$R/hidden-03/test_luggage.py"
  started=$(date +%s)
  claude_run "Do the task in task-04.md." "$OUTDIR/w4b-$run-A.json" & a=$!
  sleep 2
  claude_run "Do the task in task-03.md." "$OUTDIR/w4b-$run-B.json" & b=$!
  wait $a; wait $b
  took=$(( $(date +%s) - started ))
  python3 - "$R/Notes" "$OUT" "$run" "$took" "$(score "$R/hidden-tests")" "$(score "$R/hidden-03" | cut -d' ' -f2)" <<'EOF'
import glob, json, os, re, subprocess, sys
vault, out, run, took, scoreA, luggage = sys.argv[1:]
burrow = os.path.expanduser("~/.local/bin/burrow")
def read(f):
    t = open(f).read(); field = lambda k: (re.search(rf'^{k}: (.*)$', t, re.M) or [None, ""])[1].strip('"')
    return {"file": f, "branch": f.split("/")[-2], "kind": field("kind"), "session": field("session"), "cites": json.loads(field("cites") or "{}"), "text": t.split("---", 2)[-1].strip()[:200]}
entries = [read(f) for f in glob.glob(f"{vault}/.burrow/ledger/*/*.md")]
sessions = {}
for f in glob.glob(f"{vault}/.burrow/sessions/*.json"):
    d = json.load(open(f)); sessions[d["id"]] = sorted({p.split(":")[0] for t in d.get("trail", []) for p in t.get("files", [])})
handoffs = [e for e in entries if e["kind"] == "handoff"]
crossed = []
for h in handoffs:
    own = {k for e in entries if e["session"] == h["session"] and e["kind"] != "handoff" for k in e["cites"]}
    stray = [c for c in h["cites"] if c not in own and c not in sessions.get(h["session"], [])]
    if stray: crossed.append({"handoff": h["file"].split("/")[-1], "stray": stray})
resume_main = subprocess.run([burrow, "resume", vault, "main"], capture_output=True, text=True).stdout
resume_luggage = subprocess.run([burrow, "resume", vault, "luggage"], capture_output=True, text=True).stdout
row = {"run": run, "seconds": int(took), "A": scoreA, "B_luggage_tests": luggage.removeprefix("hidden="),
       "branches": sorted({e["branch"] for e in entries}),
       "ledger": [(e["branch"], e["kind"], e["text"][:90]) for e in sorted(entries, key=lambda e: e["file"])],
       "handoffs_with_stray_files": crossed,
       "luggage_on_main": "luggage" in resume_main.lower() or "bag" in resume_main.lower(),
       "resume_luggage_has_it": "bag" in resume_luggage.lower() or "luggage" in resume_luggage.lower()}
open(out, "a").write(json.dumps(row) + "\n"); print(json.dumps(row, indent=1))
EOF
done
