# Clip 08c: session 2 of clip 08 again, Claude Code in place of Gemma, same vault, same code, same task.
# Filled in and run by tapes/08c-claude-session.sh. The user's own Claude Code setup stays out of it:
# no user settings, plugins or CLAUDE.md, and Burrow is the only MCP server. Claude Code runs full-screen
# (CLAUDE_CODE_NO_FLICKER): drawn inline, its screen outgrows the terminal and vhs never sees the turn end.
Output "{OUT}"
Set Shell "bash"
Set FontSize 26
Set Width 1600
Set Height 1000
Set Padding 30
Set Theme "Builtin Dark"
Set TypingSpeed 25ms
Set Framerate 15
Hide
Type `export PS1='$ ' PATH=$HOME/.local/bin:$PATH CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 CLAUDE_CODE_HIDE_ACCOUNT_INFO=1 CLAUDE_CODE_NO_FLICKER=1 DISABLE_AUTOUPDATER=1; cd {CODE}; clear` Enter
Show
Sleep 1s
Type "# Session 2 again, now in Claude Code: same vault, same code, same task as Gemma had" Enter
Type "cat task-04.md" Enter
Sleep 8s
Type "clear; # Same instructions as OpenCode's coder agent; read, edit, write, shell and Burrow, nothing else" Enter
Type "claude --model claude-opus-5-5 --setting-sources project --strict-mcp-config --mcp-config claude-mcp.json --append-system-prompt-file coder-prompt.md --tools Read,Edit,Write,Bash --allowedTools Bash mcp__burrow --permission-mode acceptEdits" Enter
Sleep 8s
Type "Do the task in task-04.md."
Sleep 1s
Enter
Wait+Screen@1200s /[a-z]+ed for [0-9]+[hms]/
Sleep 8s
Type "/context"
Sleep 1s
Enter
Sleep 10s
Type "/exit"
Sleep 1s
Enter
Sleep 4s
Type "clear; # The task's own tests, then the finance meeting's decision as tests the model never saw" Enter
Type "cd matatu && python3 -m unittest discover -s tests 2>&1 | tail -3" Enter
Sleep 3s
Type "PYTHONPATH=. python3 -m unittest discover -s ../../hidden-tests 2>&1 | tail -3; git diff --stat; cd .." Enter
Sleep 8s
Type "clear; # What Burrow's Ledger holds after session 2" Enter
Type "burrow log {VAULT} --limit 3" Enter
Sleep 10s
