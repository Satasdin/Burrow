# Session context: proof with real Claude Code, Codex and a local model (17 Nov 2026)

What was tested: D-116 (lean output, recall, steered compaction), D-117 (archive and resume anywhere) and D-118 (the
local model's cache). Each arm is a real Claude Code 2.1.322 session on Sonnet 5.5, driven one message at a time with
`claude -p --resume`. Each runs in its own scratch folder, with the person's own settings, hooks and MCP servers switched
off (`--setting-sources project,local --strict-mcp-config`). A scratch HOME was not logged in to Claude Code, so the runs
use the real login. The window is set to Claude Code's documented floor (`CLAUDE_CODE_AUTO_COMPACT_WINDOW=100000`), so a
30-message session compacts.

- **A**: Claude Code alone.
- **B**: Burrow 1.2.3 as shipped: Ledger hooks, folds, MCP.
- **C**: this branch, with every part on.

Run 1 uses `scripts/script.json`, where the model chooses how to run things. Run 2 uses `scripts/script-raw.json`: the same
session, but the heavy steps ask for raw output in the conversation and whole-file reads. Both end with the same 8-question
quiz about the session's early part. The quiz runs with Bash, Read, Grep, Glob, Edit and Write disallowed, so answers come
from the session's own memory and, in C, from Burrow's recall and tools.

## Results (`results.md`, `results.json`; raw transcripts in `raw/`)

| Arm | Run | Compactions | Peak context | Tool output the model saw (chars) | Billed tokens | Cost $ | Quiz |
|---|---|---|---|---|---|---|---|
| A | 1 | 0 | 37,686 | 15,274 | 1,717,846 | 8.32 | 8/8 |
| B | 1 | 1 | 66,445 | 56,768 | 2,654,863 | 15.31 | 8/8 |
| C | 1 | 0 | 59,835 | 21,815 | 2,555,576 | 12.21 | 8/8 |
| A | 2 | 4 | 62,538 | 472,609 | 3,488,589 | 34.59 | 8/8 |
| B | 2 | 4 | 62,680 | 472,231 | 3,536,572 | 36.28 | 7/8 |
| C | 2 | 2 | 69,756 | 136,416 | 2,892,163 | 21.29 | 8/8 |

The run 1 costs include asking the quiz again after a fix to the harness, at a later time, when the cache had expired.

## What it shows, plainly

- **Run 2, raw output in the conversation, the case Burrow is built for.** C compacted 2 times against A's 4. The model
  saw 71 % less tool output (136,416 characters against 472,609). C billed 17 % fewer tokens, and cost 38 % less ($21.29
  against $34.59). It answered the quiz 8/8. B, Burrow 1.2.3, was no better than A on context, and lost one quiz answer:
  the processed-records count, 48213.
- **Run 1, where the model chooses.** Sonnet 5.5 often wrote big output to a file and grepped it, so A never compacted.
  C's context ended higher than A's (59,835 against 37,686). The cause was Burrow's own SessionStart hook, from D-64:
  - It handed over the Ledger's head again on every resume.
  - Driven one message at a time, every message is a resume, so 23 copies sat in the context.
  - B shows the same rise.
  This is fixed on this branch (`SessionHooks.stillHasHead`), and run 2's C ran with the fix. Run 1's C did not.
- **The quiz did not separate the arms well.** Claude Code's own summary kept most planted values, and A scored 8/8 even
  after 4 compactions. Each arm ran once per script, so the quiz scores are not evidence that one arm recalls better. The
  context, compaction and cost numbers come from the transcripts and the API's own usage, and are not a matter of
  judgement.
- **Run 1 to run 2 is not like for like.** The script changed between them (raw output), so compare arms within a run,
  never across runs.

## Steered compaction and recall (smoke run, Haiku)

A manual `/compact` with Burrow's PreCompact instructions produced a summary that kept the planted port 7431, the codename
Marmot and the kept-output handle `kcd810b`. The next message brought back the person's exact words
("the deploy port is 7431 and the release codename is Marmot") through UserPromptSubmit, and the model expanded `kcd810b`
lines 470–475 through `burrow_expand`.

## Resuming in another program (`local-resume/`, `codex-resume/`)

- **Qwen3 4B through llama.cpp (`burrow chat --resume 3a9523af --llama`).** It resumed C1's archived Sonnet session and
  answered all three questions right: port 7431, shard 0x5F3A with 9c41 and 77e2, SQLite because the laptops are offline.
  - First resume, nothing saved: the first answer took 3.1 s.
  - Second resume, on a freshly started server: the saved cache loaded in 0.03 s and the first answer took 1.3 s.
  - The cache was about 300 MB for 3,800 tokens (8-bit).
  - The earlier measurement on an 8,600-token history: 7.32 s against 0.49 s.
- **Codex 0.146 (`$burrow-resume 3a9523af`) on Ollama.**
  - On gemma4:12b it called `burrow_session`, got the pack and answered all three right.
  - On qwen3:8b it reasoned about calling the tool and ended its turn without calling it. Small models pick tools
    unreliably (D-44).
  - Codex used a scratch `CODEX_HOME` and HOME. The config is in `codex-resume/config.toml`.

## Ollama's prefix cache (`scripts/otest.py`)

A 4,600-token prompt sent twice was read in 2.93 s, then 0.05 s, with 4,590 tokens cached. With another window
(`num_ctx`), the model reloaded and nothing was cached.

## Not done

- No second repetition of run 2. It would cost about $90 for all three arms.
- No competitor plugin (context-mode) as an arm: it was not approved for download.
- No test of keeping Anthropic's cache warm.
