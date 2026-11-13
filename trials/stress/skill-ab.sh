#!/bin/bash
# Is the MCP server enough, or does the burrow skill help? Claude Code answers one question about the project from the
# stress base, twice with the skill in the project's .claude/skills and twice without. Same tools in both arms.
set -e
. "$(dirname "$0")/lib.sh"
Q="Before I touch reconciliation again: what did we decide about matching statement lines to tickets, what was turned down, and why? Then tell me whether matatu/payments/matcher.py as it is now keeps to it."
ask() {
  (cd "$R/code" && env -i HOME="$HOME" USER="$USER" LOGNAME="$LOGNAME" LANG=en_US.UTF-8 TERM=xterm-256color PATH="$PATH" \
     CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 DISABLE_AUTOUPDATER=1 \
     claude -p "$Q" --model claude-opus-5-5 --setting-sources project --strict-mcp-config --mcp-config claude-mcp.json \
       --tools Read,Bash,Skill --allowedTools Bash mcp__burrow Skill --settings "$SANDBOX" --output-format json > "$1" 2> "$1.err")
}
for arm in skill none; do
  for run in 1 2; do
    restore
    if [ $arm = skill ]; then mkdir -p "$R/code/.claude/skills/burrow"; cp "$HERE/../../skills/burrow/SKILL.md" "$R/code/.claude/skills/burrow/"; fi
    s=$(date +%s); ask "$OUTDIR/skill-$arm-$run.json"; echo "$arm $run: $(( $(date +%s) - s )) s"
  done
done
