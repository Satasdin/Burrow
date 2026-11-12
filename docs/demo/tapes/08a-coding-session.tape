# Clip 08a: session 1 on the Matatu project, Gemma 4 12B in OpenCode, the code held in Burrow; the Ledger after it.
# Filled in and run by tapes/08-coding-session.sh.
Output "{OUT}"
Set Shell "bash"
Set FontSize 20
Set Width 1600
Set Height 1000
Set Padding 30
Set Theme "Builtin Dark"
Set TypingSpeed 30ms
Set Framerate 15
Hide
Type "export PS1='$ ' PATH=$HOME/.local/bin:$PATH OPENCODE_CONFIG={CODE}/opencode.json; cd {CODE}; export PWD={CODE}; clear" Enter
Show
Sleep 1s
Type "# Matatu: a minibus operator's back office. Burrow holds its code, linked read-only into the vault" Enter
Type "burrow stats {VAULT} | tail -1; ls matatu/matatu" Enter
Sleep 4s
Type "# Session 1, Monday: the task, with a decision from the finance meeting at the end" Enter
Type "tail -6 task-01.md" Enter
Sleep 8s
Type "opencode --standalone --auto" Enter
Sleep 6s
Type "Do the task in task-01.md."
Sleep 1s
Enter
Wait+Screen@900s /Gemma 4 12B · [0-9.ms ]+· [0-9.]+ tok/
Sleep 6s
Ctrl+C
Sleep 1s
Ctrl+C
Sleep 2s
Type "clear; # What Session 1 left in Burrow's Ledger: the decision, and a handoff Burrow wrote when it closed" Enter
Type "burrow log {VAULT} --limit 2" Enter
Sleep 8s
