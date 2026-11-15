# Burrow

Private project memory for local language models. Burrow keeps a software project's code linked, along with the decisions, rejected fixes and past bugs the code can't show, and hands a local Ollama model only the parts it needs. Nothing leaves the Mac.

Burrow is a private vault for everything: notes in Markdown, with code folders linked in read-only, and any local Ollama model can read it. There is a Mac app, a terminal version and an MCP server, all on the same engine. Pick a folder as your vault, and an Obsidian vault works as it is.

Beside the files, Burrow keeps the **Ledger**: what AI sessions decided and why, what they were corrected on, and where each one stopped, so the next program, cloud or local, starts from it. Programs connected over MCP get the decisions in force when they connect, `burrow_resume` to pick up where the last session stopped, and `burrow_check` to see their code change beside the decisions it touches. The app's **Watch** panel shows the same three things to you. [docs/day-to-day.md](docs/day-to-day.md) walks through a normal day.

Which Mac: the terminal version and the MCP server run on Apple silicon with macOS 14 or later. The desktop app needs macOS 26 or later; build it with `app/build.sh`, then open `app/build/Burrow.app`.

## Install

The terminal version, from the [landing page](https://satasdin.github.io/Burrow/) or with:

```bash
curl -fsSL https://github.com/Satasdin/Burrow/releases/latest/download/install.sh | sh
```

Add `-s -- --app` after `sh` to install the desktop app as well.

## Needs to build from source

- A Mac with Xcode
- [Ollama](https://ollama.com) with a chat model and the embedding model:

```bash
ollama pull qwen3:4b-instruct-2507-q4_K_M
```

```bash
ollama pull qwen3-embedding:0.6b
```

## Build and test

```bash
swift build -c release
```

```bash
swift test
```

## Use

```bash
.build/release/burrow index ~/code/my-project
```

```bash
.build/release/burrow ask ~/code/my-project "Where is a payment retried?"
```

```bash
.build/release/burrow note ~/code/my-project "We rejected caching sessions in app/auth.py because logout must be instant." --kind rejected
```

Other commands: `find` shows what would be read without asking a model, `links` shows what a file connects to, and `stats` shows the size of the memory. Add `--mode none`, `--mode search` or `--mode walk` to compare the three ways of giving a model memory.

## The engine

Burrow does more than find excerpts. On every question it decides whether the vault is needed, fits what it shows to the model, checks what the answer cites, and can hand the model a method for the task.

```
.build/release/burrow fit ~/vault --vault --model gemma4:12b        # measure a model once
.build/release/burrow skills ~/vault --vault --install               # add the starter skills to <vault>/Skills
.build/release/burrow ask ~/vault "When is rent due?" --mode engine --model gemma4:12b --vault
.build/release/burrow brief ~/vault "When is rent due?" --vault --json   # the same question packed for any other model
.build/release/burrow learn ~/vault conversation.json --vault        # keep what a conversation decided
```

`ask --mode engine` prints what it decided, the skill it used, what it read, and how many cited places were not among what it read. A skill is a Markdown file in the vault's `Skills` folder with a `when:` line; edit them or add your own. In `burrow chat`, `/keep` proposes notes from the conversation and asks before writing each one. MCP clients get the same preparation from the `vault_prepare` tool.

## In the terminal

A vault is a folder of Markdown notes, with code folders linked in read-only. The first command below is once per code folder and the second opens the folder as a vault and builds its index with meaning search; it is also how to open a vault from the terminal without the app.

```bash
.build/release/burrow link ~/notes ~/code/my-project
```

```bash
.build/release/burrow index ~/notes --vault
```

Full-screen view. Press `?` inside for every key. With no arguments it opens the folder you are in if it has a `.burrow` index, or else the last vault you opened.

```bash
.build/release/burrow tui ~/notes
```

A code folder in iCloud Drive has to be downloaded to be indexed, and the index waits for it, so keep linked folders outside iCloud or set them to stay downloaded.

It needs a real terminal of at least 40 by 12, with UTF-8. Colour is optional and `NO_COLOR` is respected. Right-to-left text is passed through unchanged, so it depends on your terminal.

Terminal chat with a local model. It streams the answer and prints each tool call on a dim line. `ollama run` has no tool support, so this talks to Ollama directly.

```bash
.build/release/burrow chat ~/notes --folder my-project
```

By default the chat searches the vault before the model is asked, and labels that search, because small models often skip their tools (see D-32). `--tools-only` leaves it entirely to the model. Add `--model NAME` for another model.

## Connect an MCP client

`burrow mcp <vault-folder>` is an MCP server on stdin and stdout. A program is shown five tools: `burrow_find` (search), `burrow_read`, `burrow_resume` (where earlier sessions stopped), `burrow_commit` (keep a decision with its reason, a fact, a plan or a handoff) and `burrow_check` (your code change beside the decisions it touches). `--tools full` lists all 22, including `burrow_log`, `burrow_blame`, `burrow_diff`, `burrow_revert`, `burrow_recall` and the older `vault_` tools; `--tools classic` lists only the 12 `vault_` tools, for runs that must match earlier ones. A program can call only the tools it is shown (the old `vault_search` and `vault_read` names still answer); a fold's original messages go only to the Claude Code session that wrote it. Only `burrow_commit`, `burrow_revert` and `vault_remember` write, and they only add. When a program connects it is handed the decisions in force, with their reasons; each connection is kept as its own conversation, and when it closes Burrow writes a handoff. Point a client at the built binary, using full paths ([docs/connect.md](docs/connect.md) has the line for each program):

```json
{
  "mcpServers": {
    "burrow": {
      "command": "/full/path/to/burrow/.build/release/burrow",
      "args": ["mcp", "/full/path/to/your/vault"]
    }
  }
}
```

Excerpts are marked as project content, so a client shouldn't take instructions from them. Search uses meaning when the vault has vectors and falls back to words if Ollama is off. Logs go to stderr.

## The Ledger and the Watch

```bash
.build/release/burrow log ~/notes                 # what earlier sessions decided, newest first
.build/release/burrow resume ~/notes              # what the next program is handed
.build/release/burrow confirm ~/notes <commit>    # a file it rests on changed, and it still holds
```

A decision is kept with its reason and the files it rests on. When one of those files changes, programs are still handed the decision, marked "check again", until someone confirms it (`burrow confirm`, or **Still Right** in the app) or marks it wrong (`burrow revert`). In the app, the Ledger page opens with the Watch: the rules every program gets when it connects, what `burrow_check` would show for the code changed right now, and any text in the vault written to steer an AI. [docs/ledger.md](docs/ledger.md) has the details.

## Several vaults, and how much Burrow keeps

```bash
.build/release/burrow vault new ~/Work --name Work         # a new vault
.build/release/burrow bridge ~/notes ~/Work                 # ~/notes reads Work, one way and read-only
.build/release/burrow config ~/notes set storage.limit 2GB  # how much Burrow's own store may hold; --global for all vaults
```

A bridge lets one vault read another: search, ask, the MCP tools and the app's Library also look in the bridged vault, each result marked with its name (`Work › notes/plan.md`). Nothing is written into it, bridges are not followed onwards, and its decisions stay private unless the bridge is made `--with-ledger`. A storage limit counts Burrow's own store, never your files: when indexing would go over it, Burrow stops adding, says what to do, and deletes nothing. `burrow stats` shows the usage. [docs/day-to-day.md](docs/day-to-day.md) has more, and D-97 and D-98 in [DECISIONS.md](DECISIONS.md) the reasons.

## Where it lives

The memory lives in `.burrow` inside the project. Notes are ordinary Markdown files. The index can be deleted and rebuilt at any time.

See [DECISIONS.md](DECISIONS.md) for why it works this way.
