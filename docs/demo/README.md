# Demonstration clips

Raw clips for the final presentation, each from a real run on a copy of the evaluation vault, to be edited together.
Nothing is staged: the models answered live, and every number on screen was measured in that run.

| Clip | Shows | Length | Recorded with |
|---|---|---|---|
| 01-app-tour-live-lookup.mp4 | The app: library, a note with its properties, the map, then the Programs page lighting up while Gemma 4 12B in OpenCode asks the vault about breach notice; its conversation and the Ledger | 73 s | `BURROW_RECORD=<folder>` frames from the app, driven from its menus; `ffmpeg -framerate 10` |
| 02-install-and-connect.mp4 | Install from the release in one command, index the vault, connect it to Claude Code, `claude mcp get burrow` shows Connected | 32 s | `vhs tapes/02-install-connect.tape` |
| 03-memory-stored-and-fetched.mp4 | Session 1: Claude Code fetches the 72-hour rule through Burrow and keeps a decision in the Ledger; `burrow log`; session 2, with no chat history, recalls the decision and why | 79 s | `vhs tapes/03-store-fetch.tape` |
| 04-what-the-model-reads.mp4 | `find` (which files and lines, 0.05 s), `brief` (the exact text handed to the model), `ask` with Gemma 4 12B citing line 133, time to first word and tokens read | 38 s | `vhs tapes/04-what-the-model-reads.tape` |
| 05-speed-time-to-first-word.mp4 | The shelf: the same question cold (2,773 tokens read, 1.66 s to first word) and from saved working memory (20 tokens, 0.18 s), Qwen3 4B in llama.cpp | 34 s | `vhs tapes/05-speed-ttfw.tape`, with llama-server on port 8080 and `--slot-save-path` set to the vault's `.burrow/kv` |
| 06-weaknesses-burrow-covers.mp4 | Reasoning: plain retrieval makes Gemma refuse a sum, the engine leaves the vault out and gets 756. Hallucination: Ugandan law, "I don't know from what you were shown". Stale memory: the cited Act is edited and the Ledger says check again | 60 s | `vhs tapes/06-weaknesses.tape` |
| 07-llama-session-cached.mp4 | llama.cpp's own chat page with Burrow as its MCP server, Qwen3 4B: it fetches the 72-hour rule (section 43(1)(a), line 133), answers the follow-up from what is still in its working memory, and keeps a decision in the Ledger | 74 s | `tapes/07-llama-cached.sh`: a fresh llama-server (`-np 2`, q8_0 caches, temperature 0, seed 7) with `--mcp-servers-config`, the page driven headless by Playwright |
| 08-coding-session.mp4 | A two-session coding week on the Matatu project, Gemma 4 12B in OpenCode with Burrow holding the code. Session 1 fixes unknown references and keeps the finance meeting's decision in the Ledger; session 2, fresh, gets a task that tempts it to undo that decision. It calls `burrow_resume` and gets the decision back, then matches on phone and amount anyway: the task's tests pass 6 of 6, the decision's hidden tests fail 2 of 2 | 18 min 33 s (session 2 runs 15 min, five compactions at a 32k window) | `tapes/08-coding-session.sh`: setup, then `08a` and `08b` recorded apart and joined |
| 08c-claude-session.mp4 | Session 2 of clip 08 again, Claude Code (Opus 5.5) in place of Gemma: same vault, same code after session 1, same task and the coder agent's instructions word for word, Burrow its only MCP server. It calls `burrow_resume`, says the earlier decision rules out the phone, and matches mistyped references by the reference alone (case, spaces and punctuation ignored, one ticket or suspense); task tests 12 of 12 (6 its own), hidden decision tests 2 of 2; the decision and, on `/exit`, Burrow's handoff are in the Ledger | 2 min 1 s (the turn: 36 s) | `tapes/08c-claude-session.sh`, after `08-coding-session.sh`; Claude Code full-screen, in a clean environment, none of the user's settings, plugins or CLAUDE.md |

The clips are kept out of git (see `.gitignore`); the tapes re-record them. The demo vault lives in `~/BurrowDemo/Notes`.

Note for the edit: in clip 4 the first word came after 0.12 s because Ollama still held the same excerpts from a run a
minute earlier; the cold figure on that question was 7.34 s. Clip 5 is the deliberate comparison.

## Stills for the report (Section 5.4.7)

One still per use case, in `docs/report/figures/workflow/`, 1600 px wide and cropped to the chat so it reads at 6.2 inches.

- `llama-cached-session.png` (clip 07, 12 November): a session that stays cached. Two frames of one run, stacked.
  The first question read 6,175 tokens in 4.5 s (Burrow's excerpts); the follow-up read 21 tokens in 0.1 s, with the same server log.

Note on clip 07: the Ledger commit it made was signed `claude-opus-5-5`, a name Qwen copied from the commit before it.
It carries a correction (`20261112-101708-fd7b`), and Burrow now signs a commit with the model the server reports.

- `coding-session-gemma.png` (clip 08, 12 November): a codebase held in Burrow across two sessions, with a small local model.
  Session 1 kept the decision in the Ledger; in session 2 the 32k window filled and compacted five times and `burrow_resume` returned the decision three times, yet the hidden decision tests failed 2 of 2 (task tests 6 of 6).

Note on clip 08: Burrow delivered the decision; Gemma 4 12B did not keep to it. Across four runs of session 2 it kept to it once.
None of its searches named `reconcile.py`, the file the decision cites, because it edited `matcher.py`; so the file match of D-69 never fired.

- `coding-session-claude.png` (clip 08c, 12 November): the same session 2 with Claude Code, for comparison.
  One `burrow_resume` brought the decision back; it kept to it in 36 s with 30.4k of a 1M window used (3%), the hidden decision tests passed 2 of 2 (task tests 12 of 12), and Burrow wrote the handoff when it exited.

Note on clip 08c: this is the fourth take; all four kept to the decision. Take 1 lost its video (vhs never saw the turn end); in take 2
Ctrl+C did not close Claude Code, so the closing commands went to the model; take 3 was clean but left no handoff, because Claude Code
stops its MCP servers with SIGINT and Burrow died before writing it (fixed in D-70). All three are in `clips/08c-attempt-{1,2,3}/`, and their Ledger entries were taken out of the vault before the next take.
The grey "add the phone check too" in the prompt box after the turn is Claude Code's own suggested next prompt; nobody typed it.

