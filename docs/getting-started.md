# Getting started

Ten minutes from nothing to an AI program that answers from your notes and keeps your decisions.

## What you need

- A Mac with Apple silicon. The `camr` program and its MCP server need macOS 14 or later; the desktop app needs
  macOS 26 or later.
- [Ollama](https://ollama.com), for search by meaning and for CAMR's own answers. Without it, search still works by
  words.

## 1. Install

```bash
curl -fsSL https://github.com/Satasdin/CAMR/releases/latest/download/install.sh | sh
```

Add `-s -- --app` after `sh` to install the desktop app as well. The installer downloads the latest release, checks
each file against its SHA-256 checksum, and stops if one does not match. It puts `camr` in `~/.local/bin` and, in a
terminal, offers to add that folder to your PATH in `~/.zshrc`; it ends by saying whether your shell can find `camr`,
and if not, the exact line to add. An app installed this way opens straight away. CAMR isn't notarised by Apple, so
an app downloaded with a browser (the DMG on the download page) is stopped the first time: open **System Settings ›
Privacy & Security** and choose **Open Anyway**, once. Then:

```bash
camr --version
```

To build from source instead: `swift build -c release` and `swift test` in a clone of the repository (Xcode needed).

## 2. Models

```bash
ollama pull qwen3-embedding:0.6b
```

```bash
ollama pull qwen3:4b-instruct-2507-q4_K_M
```

The first turns text into vectors for search by meaning. The second is a small chat model for the app's Ask and
`camr chat`; any Ollama chat model works, and a 12-billion-parameter model such as `gemma4:12b` answers better if
your Mac has the memory.

## 3. A vault

Any folder of Markdown notes is a vault, an Obsidian vault as it is.

```bash
camr vault new ~/Notes
```

This builds the index in `~/Notes/.camr`. Your files are never changed. In the app: **Open or Create a Vault…**.

## 4. Link your code (optional)

```bash
camr link ~/Notes ~/code/my-project
```

The code stays where it is and is only ever read. Run this in your own terminal: it shows the folder's real path and
asks you to type yes, because approving a folder is yours to do.

## 5. Connect a program

```bash
camr connect claude-code ~/Notes
```

This prints exactly what it would set up, and writes nothing. Read it, then run it again with `--write` in your own
terminal. Programs: `claude-code`, `opencode`, `openclaw`, `hermes`, `n8n`; others are in [connect.md](connect.md).
In the app, **Programs → Connect** does the same.

For Claude Code, also print the hooks that hand over your decisions at the start of a session and keep its exact words
when it compacts:

```bash
camr hook install claude ~/Notes
```

## 6. Check it works

```bash
camr find ~/Notes "something you wrote about"
```

This shows what a model would read, with file and line, without calling a model. Then open your program and ask it
something your notes answer. To keep a decision, tell it: "Make this the decision and keep it in CAMR, with the
reason." It appears on the app's **Ledger** page, signed with the program's name, and every program you connect is
handed it from then on.

## 7. Teach your agent (optional)

The [skill pack](../skills/README.md) teaches an AI program to resume, keep decisions and answer a held change well.
In Claude Code:

```
/plugin install camr --marketplace Satasdin/CAMR
```

Next: [Day to day](day-to-day.md).
