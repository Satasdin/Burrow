# Long sessions, kept lean and resumable anywhere

A long Claude Code session fills its context with tool output, compacts, and loses words on the way. A month later its
transcript is gone: Claude Code deletes transcripts after 30 days by default. CAMR 1.3 looks after both.

- **It replaces raw tool output filling the context.** A long Bash or Grep result is kept whole by CAMR, and the
  model sees its start, its end, every error line and a handle to fetch the rest. Nothing is summarised, so no exact
  word is lost.
- **It replaces sessions lost to compaction and to time.** Every Claude Code and Codex session is kept in an archive,
  compressed, and any program can pick it up later: Claude Code, Codex, or a local model through `camr chat`.

`camr connect claude-code ~/Notes --write` sets up all of it; `camr connect codex ~/Notes --write` sets up
everything Codex allows (see [connect.md](connect.md)). The session hooks run wherever the session is, inside the
vault's folder or not, and never write into the vault: what they keep lives in CAMR's own folder, readable only by
your account.

## What CAMR does during a session

**Lean output (Claude Code only).** A Bash or Grep result over 6,000 characters is kept whole, and the model sees:

- its first and last 30 lines;
- every error line from the middle, exactly as printed;
- a footer saying it is the real output shortened, with a handle such as `kcd810b`.

The model fetches any part with `camr_expand`: a line range, or the lines matching some words. A whole-file Read of a
file over 1,500 lines shows its first 120 lines and the file's outline, and asks the model to read a range before
editing. A read that gave a range, a command left running in the background, Edit and Write are never shortened.
Claude Code cuts Bash output at about 30,000 characters before any hook sees it, so CAMR can keep no more than that,
and the footer says so. Codex can't be given a shorter tool output, so this part is Claude Code only.

**Recall.** On each message you type, CAMR searches what has left the context: the outputs it kept, and this
session's messages from before its last compaction. Up to 3 pieces and 1,500 characters come back, with where they came
from, marked as data. Nothing comes back when nothing matches. It matches words, with no model, so the hook stays fast.

**Steered compaction.** Before Claude Code compacts, CAMR tells the summary what to keep: your requests in quotes,
values, errors and decisions with their reasons word for word, and the handles of kept output.

**The meter.** Every action is written down per session, so you can see what was kept out of the context, what came
back and when it compacted: the app's **Sessions** page (⌘6), or `camr session meter`.

## The archive

Each session is kept as one compressed transcript and a small record, in `sessions/` in CAMR's folder
(`~/Library/Application Support/CAMR`). It is kept before compacting, when the session ends, and at most every ten
minutes while you work. On the author's Mac, 7.2 GB of transcripts became 1.9 GB.

```
camr session sync                          # keep every Claude Code and Codex session still on this Mac
camr session                               # the latest archived sessions
camr session timeline <name|id>            # one line per request
camr session find <name|id> "words"        # the exact messages that match
```

`sync` reads Claude Code's transcripts (`~/.claude/projects`, and `CLAUDE_CONFIG_DIR`) and Codex's (`~/.codex/sessions`).
It leaves out Codex's own copies of Claude Code sessions, and does not read again a file unchanged since it was kept.

**On an external drive.** To keep the archive on a drive:

```
camr session settings archive-folder /Volumes/YourSSD/CAMR
camr session settings archive-folder default     # back to CAMR's own folder
```

When that drive is not connected, CAMR keeps sessions in its own folder instead of failing to write them, and says
so: the app's Sessions page shows "YourSSD not connected", and `camr session settings` prints it. Your setting stays
as you set it.

## Picking a session up in any program

A session is resumed from its **resume pack**, about 6,000 tokens: your requests word for word (all of them, or the first
three and the last twelve when there are many), decisions, constraints, errors and files, the plan, and where it
stopped. It is made the same, byte for byte, every time, so a model that cached it can load that cache again.

| Where | How |
| --- | --- |
| Claude Code | `/camr-resume <name or id>` |
| Codex | `$camr-resume <name or id>` |
| CAMR's own chat, with Ollama | `camr chat ~/Notes --resume <name or id>` |
| CAMR's own chat, with llama.cpp | `camr chat ~/Notes --resume <name or id> --llama http://127.0.0.1:8080` |
| Any program connected over MCP | `camr_session` with `session` |
| Terminal | `camr session resume <name or id>` |

A session is named by its id, its first 8 characters, or words from its name; when several match, you are shown them
and asked which. The app's Sessions page gives the Claude Code, Codex and `camr chat` lines for each session, ready
to copy.

With `--llama`, the model's cache of the pack is saved to the vault's shelf after every reply and loaded on the next
resume, so it is not read again. Start llama.cpp with `--slot-save-path` on the shelf, as in [kv.md](kv.md).

When Claude Code resumes a session of 40,000 tokens or more whose cache has probably expired, CAMR shows you the size
and Claude Code's own estimate of rewriting it, and the lighter way back: `/clear`, then `/camr-resume`.

## Who reads what

- **The resume pack and the timeline**, with secrets taken out, go to any program you connected.
- **The exact messages** (a search, or one message whole) go only to the program that wrote the session. Another
  program gets them only after you run this in your own terminal and type yes:

  ```
  camr session allow <name|id> codex          # or claude-code
  ```

- **Kept tool output** goes back only to the Claude Code session that ran it.

## Settings

Each part has a switch, kept in `session-context.json` in CAMR's folder:

```
camr session settings                          # show them, and where the archive is
camr session settings lean-bash off            # also lean-read, lean-grep, recall, steer, archive: on or off
camr session settings lean-characters 8000     # how long an output must be to be kept (at least 1,000)
camr session settings lean-read-lines 2000     # how long a file must be for a whole read to be shortened (at least 200)
```

The app's Sessions page shows them; for now they are changed with `camr session settings`.

## What it measured

Real Claude Code sessions on Sonnet 5.5 with a 100,000-token window, one run per arm per round, where the heavy steps
put raw output in the conversation. Averaged over two rounds, against Claude Code alone:

| | Claude Code alone | CAMR 1.3 |
| --- | --- | --- |
| Compactions | 3.5 | 1.5 (−57 %) |
| Tool output the model saw | 419,999 characters | 111,077 characters (−74 %) |
| Billed tokens | 3.29 M | 2.93 M (−11 %) |
| Cost | $31.96 | $19.24 (−40 %) |

Most of the cost saving is the cache rewrite each compaction costs. In a run where the model chose how to run things
and mostly grepped files, Claude Code alone never compacted, so there was nothing to save. Each arm also took an
8-question quiz about the session's early part; Claude Code's own summary kept most planted values, so the quiz did not
separate the arms and no claim about recall is made from it.

Resuming in another program: Qwen3 4B through llama.cpp answered 3 of 3 questions about an archived Sonnet session, and
with its saved cache loaded the first answer came in 1.3 s instead of 3.1 s. Codex on gemma4:12b answered 3 of 3 with
`$camr-resume`; on qwen3:8b it never called the tool.

The scripts, raw transcripts and results are in [evidence/session-context/](evidence/session-context/README.md).
