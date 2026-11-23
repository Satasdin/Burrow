<div align="center">

# CAMR

*Capability-Adaptive Memory Retrieval* (called Burrow until 1.4)

**One memory on your Mac that every AI you use shares.**

Your notes, documents and code, and every decision you made with an AI and why,<br>
read by local and cloud models alike. Nothing you keep leaves your Mac.

[![Release](https://img.shields.io/github/v/release/Satasdin/CAMR?label=release&color=7c3aed)](https://github.com/Satasdin/CAMR/releases/latest)
[![Tests](https://img.shields.io/github/actions/workflow/status/Satasdin/CAMR/tests.yml?branch=camr&label=tests)](https://github.com/Satasdin/CAMR/actions/workflows/tests.yml)
![macOS](https://img.shields.io/badge/macOS-14%2B%20·%20Apple%20silicon-111)
![MCP](https://img.shields.io/badge/MCP-server-111)

[Website](https://satasdin.github.io/CAMR/) · [Download](https://satasdin.github.io/CAMR/download.html) · [Docs](docs/README.md) · [Skills for agents](skills/README.md) · [CAMR.md](CAMR.md)

<br>

<img src="site/media/app-ask.jpg" alt="CAMR answering a question from a vault, citing the file and line, with the files it read lit up on the map" width="900">

</div>

## Why CAMR

Every AI starts a session knowing nothing about you. A local model doesn't know your notes, and what you settle with
one model never reaches the next.

- **It replaces pasting context into every chat.** A model on your Mac answers from your own notes, documents and
  code and cites the file and line. Gemma 4 12B answered 9 of 120 questions about private material alone, and 102
  with CAMR.
- **It replaces decisions lost between sessions.** When you settle something, your AI keeps it in the **Ledger** with
  its reason and what was turned down, and every model that connects is handed it. Once reasons were kept, Claude
  Code kept an earlier decision in 9 of 9 sessions.
- **It replaces starting over in a new program.** Any program that speaks MCP picks up where the last one stopped:
  Claude Code, Codex, OpenCode, OpenClaw, Hermes Agent, n8n, LM Studio, Ollama or llama.cpp.
- **It replaces long sessions that fill up and are lost.** CAMR keeps big tool output out of Claude Code's context
  without losing a word, and keeps every Claude Code and Codex session so any program can resume it, a month later if
  need be. In real Sonnet 5.5 sessions full of raw tool output it meant 57 % fewer compactions, 74 % less tool output
  in the context and 40 % lower cost than Claude Code alone. A quiz on the session's start did not separate the two,
  so no claim about recall is made.
- **It checks before "done".** A model can read a decision and still break it, so CAMR checks each code change
  against the decisions it touches, in the agent and in git's pre-commit hook.

## Install

```bash
curl -fsSL https://github.com/Satasdin/CAMR/releases/latest/download/install.sh | sh
```

Add `-s -- --app` after `sh` for the desktop app (macOS 26 or later). The installer checks every download's SHA-256
and installs nothing if one doesn't match. CAMR uses [Ollama](https://ollama.com) for search by meaning:

```bash
ollama pull qwen3-embedding:0.6b
```

## Quick start

```bash
camr vault new ~/Notes                # make a folder of notes a vault
camr link ~/Notes ~/code/my-project   # link a code folder, read-only
camr connect claude-code ~/Notes      # show the setup; --write applies it
```

Any folder of Markdown works, an Obsidian vault as it is. Then ask your AI about your own material. It searches with `camr_find`, picks up earlier work with `camr_resume`,
keeps decisions with `camr_commit` and checks its changes with `camr_check`.
[Getting started](docs/getting-started.md) walks through it.

## What's inside

| Part | What it does |
| --- | --- |
| **Vault** | Notes, PDFs, Word documents and images, with code folders linked read-only. Search by words and by meaning, with file and line. |
| **Engine** | Decides whether the vault is needed, fits what it shows to the model, and checks what the answer cites. |
| **Ledger** | A git for what AIs understood: decisions with reasons, plans, handoffs and corrections, on branches. Nothing is ever deleted. |
| **Check** | A verdict per decision on your change: unaffected, affected, unprovable or breaks. Runs in Claude Code, OpenCode, OpenClaw, Hermes Agent and git. |
| **Teams** | Share decisions through a git or synced folder. A program's share waits until you approve it. |
| **Sessions** | Long tool output kept by handle, lost words recalled, compaction steered; every Claude Code and Codex session archived, on an external drive if you like, and resumable in any program. |
| **App** | Home, the vault's live map, glowing gold where a program is reading; Ask, the Ledger, Conversations, Programs and Sessions, in a Mac app laid out like your notes app. |

## Documentation

| Guide | For |
| --- | --- |
| [Getting started](docs/getting-started.md) | install, a first vault, connecting your first program |
| [Day to day](docs/day-to-day.md) | asking, keeping decisions, picking up tomorrow, teams, several vaults |
| [Connecting programs](docs/connect.md) | the setup line for each program |
| [The Ledger](docs/ledger.md) | decisions, the check, hooks and verdicts |
| [Sessions](docs/sessions.md) | long sessions kept lean, archived, and resumed in any program |
| [Tool reference](docs/tools.md) | every MCP tool, what it takes and returns |
| [Security and privacy](docs/security.md) | what stays on your Mac, and what CAMR defends against |
| [Skills for agents](skills/README.md) | `/plugin install camr --marketplace Satasdin/CAMR` |
| [CAMR.md](CAMR.md) | every tool, command and page in one file, for AI agents |
| [DECISIONS.md](DECISIONS.md) | why every behaviour is the way it is |

## Build from source

Needs a Mac with Xcode (Swift 6).

```bash
swift build -c release      # the camr program, at .build/release/camr
swift test                  # 589 tests; no model or network needed
app/build.sh                # the desktop app, at app/build/CAMR.app
```

## Repository

| Folder | Holds |
| --- | --- |
| `Sources/` | the engine (`CAMRCore`), the Ledger, sessions, check and teams (`CAMRTools`), the MCP server and the `camr` program |
| `Tests/` | the automated tests |
| `app/` | the desktop app |
| `integrations/` | CAMR's gate for OpenCode, OpenClaw and Hermes Agent |
| `skills/` | the skill pack for AI agents |
| `site/` | the website, deployed to GitHub Pages |
| `docs/` | the guides, the test record and the traceability record |

The final-year project report and every evaluation's scripts, transcripts and results are on the
[`docs/reports`](https://github.com/Satasdin/CAMR/tree/docs/reports) branch.
