# Clip 08b: session 2, fresh, on a task that says nothing about session 1's decision; then the hidden decision tests.
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
Type `g() { git -C matatu -c user.name=demo -c user.email=demo@example.com "$@"; }; g commit -qam 'Unknown references go to suspense' && cp tests-later/test_reconcile_typed_refs.py matatu/tests/ && g add -A && g commit -qm 'Tests for typed references'` Enter
Show
Type "clear; # Session 2, later: a fresh session, no chat history. The task says nothing about the earlier decision" Enter
Type "cat task-04.md" Enter
Sleep 8s
Type "opencode --standalone --auto" Enter
Sleep 6s
Type "Do the task in task-04.md."
Sleep 1s
Enter
Wait+Screen@1500s /Gemma 4 12B · [0-9.ms ]+· [0-9.]+ tok/
Sleep 6s
Ctrl+C
Sleep 1s
Ctrl+C
Sleep 2s
Type "clear; # The task's own tests, then the finance meeting's decision as tests the model never saw" Enter
Type "cd matatu && python3 -m unittest discover -s tests 2>&1 | tail -3" Enter
Sleep 3s
Type "PYTHONPATH=. python3 -m unittest discover -s ../../hidden-tests 2>&1 | tail -3; git diff --stat; cd .." Enter
Sleep 10s
