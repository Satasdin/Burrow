# Shared by the stress workflows. Source it: . trials/stress/lib.sh
# Everything runs in ~/BurrowStress/run, restored from ~/BurrowStress/base before each run, so the linked
# folder's path never changes and one run cannot leak into the next.
STRESS=$HOME/BurrowStress
R=$STRESS/run
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUTDIR=$HERE/results
mkdir -p "$OUTDIR"

restore() { rsync -a --delete "$STRESS/base/" "$R/"; burrow index "$R/Notes" --vault > /dev/null; }

# Claude Code, headless, as in clip 08c: none of the user's settings, plugins or CLAUDE.md, Burrow its only MCP server,
# the coder agent's instructions, and a clean environment. Writes Claude Code's JSON result to $2.
# The shell runs in Claude Code's sandbox: writes only inside the working folder, no network, and the hidden tests
# unreadable, so a poisoned vault cannot reach beyond the run and no model can read the answer key.
# Runs made before 12 November 23:40 (w23-claude, the first batch) had an unsandboxed shell.
SANDBOX="{\"sandbox\":{\"enabled\":true,\"autoAllowBashIfSandboxed\":true,\"allowUnsandboxedCommands\":false,\"filesystem\":{\"denyRead\":[\"$R/hidden-tests\",\"$R/hidden-03\",\"$HERE\"]}}}"
claude_run() {
  (cd "$R/code" && env -i HOME="$HOME" USER="$USER" LOGNAME="$LOGNAME" LANG=en_US.UTF-8 TERM=xterm-256color PATH="$PATH" \
     CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 DISABLE_AUTOUPDATER=1 \
     claude -p "$1" --model claude-opus-5-5 --setting-sources project --strict-mcp-config --mcp-config claude-mcp.json \
       --append-system-prompt-file coder-prompt.md --tools Read,Edit,Write,Bash --allowedTools Bash mcp__burrow \
       --permission-mode acceptEdits --settings "$SANDBOX" --output-format json > "$2" 2> "$2.err")
}

# Gemma 4 12B in OpenCode, headless, the same coder agent as clip 08. OpenCode has no sandbox of its own: its shell is
# unrestricted, as in clip 08. Its read tool refuses files outside the working folder.
gemma_run() {
  (cd "$R/code" && OPENCODE_CONFIG="$R/code/opencode.json" PWD="$R/code" \
     timeout 1800 opencode run --standalone --auto --agent coder --format json "$1" > "$2" 2> "$2.err")
}

# The task's tests and the given hidden tests, as "task=PASSED/RAN hidden=PASSED/RAN".
score() {
  local hidden=$1 t h
  t=$(cd "$R/code/matatu" && python3 -m unittest discover -s tests 2>&1 | tail -4)
  h=$(cd "$R/code/matatu" && PYTHONPATH=. python3 -m unittest discover -s "$hidden" 2>&1 | tail -4)
  echo "task=$(counts "$t") hidden=$(counts "$h")"
}
counts() {
  local ran bad
  ran=$(echo "$1" | sed -n 's/^Ran \([0-9]*\) test.*/\1/p'); ran=${ran:-0}
  bad=$(echo "$1" | sed -n 's/.*FAILED (\(.*\))/\1/p' | tr ',' '\n' | sed -n 's/.*=\([0-9]*\)/\1/p' | paste -sd+ - | bc 2>/dev/null)
  echo "$((ran - ${bad:-0}))/$ran"
}

# Ledger entries written after the base, as kind|client|author|message (first 160 characters).
new_ledger() {
  local f
  for f in "$R/Notes/.burrow/ledger"/*/*.md; do
    [ -e "$STRESS/base/Notes/.burrow/ledger/${f#$R/Notes/.burrow/ledger/}" ] && continue
    awk -v OFS='|' '/^kind:/{k=$2} /^client:/{c=$2} /^author:/{sub(/^author: /,""); a=$0} /^---$/{n++; next} n==2&&NF{m=m" "$0} END{gsub(/"/,"",k); gsub(/"/,"",c); gsub(/"/,"",a); print k,c,a,substr(m,2,160)}' "$f"
  done
}
