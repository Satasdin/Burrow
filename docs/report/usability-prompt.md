You're helping me test Burrow, a Mac app from my friend Ibrahim's final-year project: https://satasdin.github.io/Burrow/ . It gives AI programs one shared memory: my notes and code, and the decisions I make with an AI and why. You set things up and keep notes. I do the things only I may do, and I give my own opinions; never answer the opinion questions for me.

Rules:
- You need to run commands on my Mac (Claude Code, the Claude desktop app's Code tab, or OpenCode). If you can't, tell me and stop.
- Privacy: don't read my personal files, and leave my username, computer name, serial number and email out of everything you write. Nothing is uploaded; I'll send the final report myself.
- Before every step, say in one line what you're about to do. When Burrow says only the person may do something, give me the exact command for my own Terminal app and wait.
- Copy any error exactly. Write down the time each task starts and ends.
- Keep all notes in ~/BurrowTest-results.md, and add to it after every task.

PART 1 (this session)

0. My Mac. Collect: the chip (sysctl -n machdep.cpu.brand_string), memory in GB (sysctl -n hw.memsize), the macOS version (sw_vers), free disk space (df -h ~), whether Ollama is installed (ollama --version), and which AI programs I have (claude, opencode, openclaw, hermes). If it isn't Apple silicon, write that down and stop. If Ollama is missing, ask me to install it from https://ollama.com and wait.

1. Install. Ask me to open https://satasdin.github.io/Burrow/ , press "Download for Mac" and open the app. Note whether macOS blocked it and whether I found "Open Anyway" in System Settings > Privacy & Security. The app needs macOS 26; on older macOS, skip the app and note it. Then install the terminal version yourself: curl -fsSL https://github.com/Satasdin/Burrow/releases/latest/download/install.sh | sh , and check it with: burrow --version

2. Models. Pull the embedding model: ollama pull qwen3-embedding:0.6b . Then pick ONE chat model by my memory, so testers cover different sizes:
   - under 16 GB: qwen3:4b-instruct-2507-q4_K_M
   - 16 to 23 GB: qwen3.5:4b
   - 24 GB or more: gemma4:12b
   Pull it, and note which one and how long the download took.

3. A vault. Ask me: use a copy of a few of my own notes, or a fresh folder? For a fresh one, make ~/BurrowTest and, with me, write three short Markdown notes about something real in my life (a club, a trip, a project, a course), in my words. Then run: burrow vault new ~/BurrowTest , and try: burrow find ~/BurrowTest "<a question about those notes>" . Note whether the right note came back.

4. Connect. Use the AI program you're running in, or another one I name. Run: burrow connect <program> ~/BurrowTest (program is one of claude-code, opencode, openclaw, hermes). Show me what it would change, then ask me to run the same line with --write at the end in my own Terminal app and type yes. In the app I can use the Programs page and Connect instead; note which one I used.

Then write "PART 1 done" in the results file and tell me: "Start a NEW session of <program> and say: Continue the Burrow test from ~/BurrowTest-results.md, part 2."

PART 2 (a new session)

5. Keep a decision. Read the results file first. Check that the burrow tools (burrow_find, burrow_commit and the rest) are available to you, and note it if they aren't. Ask me for one real question about my notes, answer it with burrow_find, and note whether you cited the file. Then ask me to state a small decision with its reason in my own words (for example "we meet on Thursdays, because two of us work weekends"), and keep it with burrow_commit, kind decision, with the reason in because. Ask me to open the app's Ledger page and say whether it shows there. Without the app, use: burrow log ~/BurrowTest

Then write "PART 2 done" and tell me: "Start ANOTHER new session and say: Continue the Burrow test from ~/BurrowTest-results.md, part 3."

PART 3 (another new session)

6. Pick it up. Read the results file, but don't read the decision out of it. Ask me to ask you, in my own words, what we decided and why. Answer only from Burrow (burrow_resume or burrow_find). Note whether you got the decision and its reason right.

7. A local model. Run: burrow ask ~/BurrowTest "<my question about the decision>" --model <the chat model from step 2> . Note whether the local model gave the decision and its reason, and how many seconds it took.

8. My opinions. Ask me these one at a time and write my answers word for word:
   - From 1 (very hard, or not at all) to 5 (very easy, or completely): how easy was installing? connecting? did the new session remember the decision and the reason? how clear was the app? how likely am I to keep using it?
   - What was the most confusing moment, and what did I expect?
   - What did Burrow do that was useful to me?
   - What would I change first?

9. The report. Put this together as plain text I can paste into WhatsApp:
   BURROW TEST REPORT
   Mac: chip, memory, macOS version
   Program used, chat model, Ollama version
   For each task 1 to 7: done alone / done with help / not done; minutes; what got in the way; exact errors
   Answers to step 8, word for word
   Show it to me, save it as ~/BurrowTest-report.txt , and tell me to send it to Ibrahim.

Afterwards, if I want to remove everything: delete ~/BurrowTest, the burrow program from ~/.local/bin, and the app. Ask me before deleting anything.
