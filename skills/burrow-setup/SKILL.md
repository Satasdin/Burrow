---
name: burrow-setup
description: Help the person install Burrow on their Mac, open a vault, link code folders and connect their AI programs (Claude Code, OpenCode, OpenClaw, Hermes Agent, n8n) to it. Use it when they ask to set up, install, connect or try Burrow, when the burrow MCP server is missing, or when a Burrow command says a folder or program is not set up.
---

# Setting up Burrow

Burrow runs on the person's Mac (Apple silicon, macOS 14 or later for the program, macOS 26 or later for the app). It
keeps their notes, documents and linked code in a vault folder, with a Ledger of decisions beside them, and every AI
program they use reaches it as an MCP server. Your job is to get them there with as few steps as possible, and to hand
back to them the steps only they may take.

## What only the person can do

Some steps refuse to run from you, on purpose: approving a linked folder, joining a team, approving a share,
`burrow connect … --write`, and confirming or overriding a decision's check. They need the person's own terminal
(Terminal.app, iTerm, their editor's terminal) or the app, and some show a code in a macOS notification. Burrow also
refuses when it sees it was started by you or another agent. Do not try to get round this. Print the exact command,
say why it needs them, and wait.

## Steps

1. **Install.** `curl -fsSL https://github.com/Satasdin/Burrow/releases/latest/download/install.sh | sh`
   (add `-s -- --app` after `sh` for the desktop app). The installer checks each download's SHA-256 and stops if one
   does not match. Check with `burrow --version`.
2. **Models.** Burrow needs Ollama for search by meaning: `ollama pull qwen3-embedding:0.6b`. A local chat model is
   only needed for Burrow's own Ask and chat, for example `ollama pull qwen3:4b-instruct-2507-q4_K_M`. Without Ollama,
   search still works by words.
3. **A vault.** Any folder of Markdown notes works, an Obsidian vault as it is:
   `burrow vault new ~/Notes` (or **Open or Create a Vault…** in the app). It builds the index.
4. **Code folders.** `burrow link ~/Notes ~/code/project` links a folder read-only and approves it. This one needs
   the person's own terminal.
5. **Connect each program.** `burrow connect <program> ~/Notes` prints exactly what it would change for
   `claude-code`, `opencode`, `openclaw`, `hermes` or `n8n`: Burrow as an MCP server, its tools kept in view, and the
   gate that checks code changes. The person runs it again with `--write` in their own terminal and types yes. The
   app's **Programs** page does the same with a button. For Claude Code, `burrow hook install claude ~/Notes` prints
   the hooks that hand over the Ledger at session start and keep the session's words at compaction.
6. **Check it works.** `burrow find ~/Notes "something they wrote about"` shows what a model would read. In the
   connected program, a new session's first Burrow tool result carries the decisions in force.

## When something is wrong

- *"N linked folders are waiting"*: a vault they were given names folders they have not approved.
  `burrow link list ~/Notes`, then the person runs `burrow link approve ~/Notes <folder>` or uses **Allow** in the app.
- *Search finds nothing by meaning*: Ollama is not running or the embedding model is missing; words still work.
- *A program does not see Burrow's tools*: run `burrow connect <program> ~/Notes` again and compare; some programs hide
  MCP tools behind a search step unless told not to.
- *Storage limit reached*: `burrow stats ~/Notes`, then `burrow config ~/Notes set storage.limit 4GB`. Nothing is ever
  deleted to make room.

Guides: `docs/getting-started.md` and `docs/connect.md` in the Burrow repository.
