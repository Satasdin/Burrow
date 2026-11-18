# Connecting a model to Burrow

Burrow is the memory. The chat program is whatever you already use: Claude Code, Codex, OpenCode, LM Studio, or a model
served by Ollama or llama.cpp. They all reach Burrow the same way, as an MCP server:

```
burrow mcp ~/Notes
```

That one command shows the program seven tools: `burrow_find`, `burrow_read`, `burrow_resume`, `burrow_commit`,
`burrow_check`, `burrow_expand` and `burrow_session`. `--tools full` lists all 24 (the Ledger's history tools and the
older `vault_` tools as well). A program can call only the tools it is shown; `vault_search` and `vault_read` still
answer as the old names of `burrow_find` and `burrow_read`. When the program connects, its instructions carry the
decisions in force on the vault's current branch, each with its reason; a decision resting on a file that changed
since comes marked "check again". See [ledger.md](ledger.md).

Each connection is kept in the vault as its own conversation. Burrow writes down what the program searched for and which
files it read as it happens, so another program can pick the conversation up later even if the model never saves
anything. When the model does call `vault_session_log`, its questions and answers are kept too. A new connection is a
new conversation, even from the same program a minute later; a connection that only lists the tools leaves none (n8n
opens one of those per model turn). Commits are signed with the name the program gives when it connects
(`claude-code`, `opencode`, `@n8n/n8n-nodes-langchain.mcpClientTool`); a model's own name for itself is kept beside it,
marked as its claim.

To pick a conversation up anywhere, ask: *"Pick up my last conversation; it is saved in Burrow."*

## One command: burrow connect

```
burrow connect <program> ~/Notes            # shows the setup, writes nothing
burrow connect <program> ~/Notes --write    # writes it, in your own terminal, after you type yes
```

Programs: `claude-code`, `codex`, `opencode`, `openclaw`, `hermes`, `n8n`. It sets up three things, each the way that
program allows:

1. **Burrow as an MCP server**, started with the full path of this `burrow`, on this vault.
2. **Burrow's tools always in view.** OpenClaw and Hermes hide MCP tools behind a search step by default, OpenCode 2
   behind its `execute` tool, Claude Code behind its tool search once there are many. With a small local model that
   step is where Burrow gets lost: gemma4:12b found Burrow 2 times in 9 with it on, and almost every time with it off.
3. **Burrow's gate inside the program.** A small model can read a decision and still break it, and rarely calls
   `burrow_check`. The gate is a hook the model can't skip: when the model edits or finishes, it runs
   `burrow check <vault> --json`, and a change that rests on a decision not yet shown goes back to the model with the
   decisions and their reasons, to answer before it is done. Once per change, so it can't loop. The plugins are in
   [integrations/](../integrations).

It never edits a file without showing the change first: a new file is printed whole, a changed settings file as the
settings that change (`+` added, `~` changed). `--write` keeps each file it changes beside it, as `.before-burrow` the first time (the file as it was before
Burrow, never replaced) and as `.before-burrow-<date>-<time>` every time (the file as it was just before that write), and
only writes when run in a terminal by you: through a pipe, or from a program's own shell tool, it refuses. A settings
file it can't read safely (JSON with comments, a YAML setting already set to something else) is left alone, and it says
what to add by hand. If you use `BURROW_STATE_DIR`, it is carried into the settings so the server and the gate see the
same approved folders. `--home <dir>` puts everything under another folder, for trying it out.

What it did in real runs (gemma4:12b, the Matatu task of adding a phone-and-amount fallback the Ledger had turned
down, D-108): with these settings Burrow's tools were listed to the model by name in every run of OpenClaw, Hermes and
OpenCode. The gate fired every time the model edited (10 of 10) and every time the model then told the person which
decision the change went against. Hermes put the code back 2 of 2, OpenCode 3 of 6, OpenClaw 0 of 2. Details:
`burrow-film/v4/runs/gates-d108/RUN.md`.

| Program | Settings it changes | Tools in view | The gate |
| --- | --- | --- | --- |
| Claude Code | `~/.claude.json` (`mcpServers.burrow`), `~/.claude/settings.json` (hooks), `~/.claude/skills/burrow-resume/` | `"alwaysLoad": true` on Burrow's server | the Stop hook, `burrow hook claude <vault> --gate` (D-93) |
| Codex | `~/.codex/config.toml` (`[mcp_servers.burrow]`), `~/.codex/hooks.json`, `~/.agents/skills/burrow-resume/` | no setting written | the Stop hook, the same command |
| OpenCode | `~/.config/opencode/opencode.json`, `plugins/burrow-gate/` | `"codemode": false` on Burrow's server | plugin, when the session goes idle |
| OpenClaw | `~/.openclaw/openclaw.json`, `~/.openclaw/burrow-gate/` | `tools.toolSearch: false` (no per-server setting) | plugin, after each edit or command |
| Hermes Agent | `~/.hermes/config.yaml`, `~/.hermes/plugins/burrow-gate/` | `tools.tool_search.enabled: "off"` (no per-server setting) | plugin, after each edit or command, and before the final answer of a turn that edited files |
| n8n | nothing (n8n keeps settings in its database) | n8n has no tool search | none: n8n can't hold an agent's reply; it prints a check step to add |

## From the app

The Programs page (⌘4) shows each program as a line running into the vault. It reads each program's own settings and
says whether it starts Burrow on this vault, on another vault, only from a project folder, or not at all. Hover a line
to see the conversations, the last question and the files that program read most today; click it to open its
conversations. **Connect** shows the setup line with this vault's path filled in, and for Claude Code, OpenCode and LM
Studio, **Add for Me** writes it into the program's settings, keeping the old file beside it the same way.

The lines the app gives use the full path of the `burrow` command. Programs opened from the Dock, such as LM Studio, do
not get the shell's PATH, so a bare `burrow` would not start there. The app carries its own copy of the command and
points the lines at it, or at a command on the PATH that links to it; **Install Command** makes that link in
`~/.local/bin`. `burrow --version` says which version a copy is.

## Claude Code

For every project (what **Add for Me** writes):

```
claude mcp add --scope user burrow -- /full/path/to/burrow mcp ~/Notes
```

For one project only, run it in that project's folder with `--scope local` (just you) or `--scope project` (written to
the project's `.mcp.json`, shared with whoever uses the project). Claude Code then lists Burrow only there.

With `burrow connect claude-code ~/Notes --write` the server is added with `"alwaysLoad": true`, so Claude Code never
defers Burrow's tools behind its tool search, and the hooks are added beside any you have: session start, compaction
and session end keep a handoff in the Ledger, and Stop runs the gate (D-93). Three more keep the session lean (D-116):
PostToolUse after Bash, Read and Grep keeps a long output and shows the model a short form with a handle,
UserPromptSubmit hands back words that have left the context, and PostCompact notes each compaction for the meter. The
`burrow-resume` skill is added in `~/.claude/skills/`, so `/burrow-resume <name>` picks up any archived session. See
[sessions.md](sessions.md). Claude Code can stay open, even the
session you are setting up from: when Claude Code's `claude` command is installed, Burrow adds the server with
`claude mcp add-json`, which writes `~/.claude.json` the way Claude Code itself does, and checks the file afterwards
(D-114). The server and hooks load when a session starts: type `/exit`, then `claude --continue` to pick up the same
conversation with Burrow. Without the `claude` command Burrow writes the file itself, and then Claude Code must be
closed first, since it keeps `~/.claude.json` open and can write over a change made while it runs.

## Codex

```
burrow connect codex ~/Notes --write
```

This writes three things (D-117):

1. `[mcp_servers.burrow]` in `~/.codex/config.toml` (or `$CODEX_HOME/config.toml`), added at the end. A table of that
   name you already have is left as it is: Burrow does not rewrite TOML it did not write.
2. Burrow's hooks in `~/.codex/hooks.json`, beside any you have: session start, compaction, session end (at 3 seconds,
   because Codex cuts it there), Stop with the gate, UserPromptSubmit for recall and PostCompact for the meter. Every
   session is archived from them.
3. The `burrow-resume` skill in `~/.agents/skills/burrow-resume/`, the folder Codex reads skills from, so
   `$burrow-resume <name>` picks up any archived session, from Codex or Claude Code.

Codex asks you to trust new hooks: open `/hooks` in Codex once and approve Burrow's. Codex can't be given a shorter tool
output, so lean output stays Claude Code only. See [sessions.md](sessions.md).

## OpenCode

`burrow connect opencode ~/Notes --write` does all of this for you: Burrow's server with `"codemode": false`, and the
gate plugin in `~/.config/opencode/plugins/burrow-gate/`. OpenCode 2 puts every MCP server's tools behind one `execute`
tool ("Code Mode") unless the server says `"codemode": false`; with it, `burrow_find` and the others are listed to the
model by name. The gate runs when the model is done and the session is about to go idle: a change that rests on a
decision not yet shown goes back into the session as a message, and OpenCode runs another step so the model answers it.
See [integrations/opencode](../integrations/opencode).

By hand, in `opencode.json` (in the project, or `~/.config/opencode/opencode.json`):

```json
{
  "mcp": { "burrow": { "type": "local", "command": ["burrow", "mcp", "/Users/you/Notes"], "enabled": true } },
  "agent": {
    "burrow": {
      "description": "Answers from the Burrow vault only",
      "mode": "primary",
      "prompt": "You answer from the user's Burrow vault. Use the burrow tools; name the file for each fact. If the vault does not hold the answer, say so.",
      "tools": { "*": false, "burrow_*": true }
    }
  }
}
```

Use the `burrow` agent with small local models. OpenCode's own agent sends about 25,000 tokens of prompt and tools
before the question, which overflows a 16k context and buries Burrow among twenty other tools: in testing, a 4B model
on the default agent searched the web five times, never called Burrow, and made an answer up. On the `burrow` agent the
same model called Burrow first every time.

To use a local server as OpenCode's model, add it as a provider:

```json
"provider": {
  "llamacpp": { "npm": "@ai-sdk/openai-compatible", "options": { "baseURL": "http://127.0.0.1:8080/v1" },
                "models": { "qwen3-4b": { "tools": true } } },
  "ollama":   { "npm": "@ai-sdk/openai-compatible", "options": { "baseURL": "http://127.0.0.1:11434/v1" },
                "models": { "gemma4:12b": { "tools": true } } },
  "lmstudio": { "npm": "@ai-sdk/openai-compatible", "options": { "baseURL": "http://127.0.0.1:1234/v1" },
                "models": { "qwen2.5-coder-7b-instruct": { "tools": true } } }
}
```

## OpenClaw

```
burrow connect openclaw ~/Notes --write
```

This adds Burrow to `~/.openclaw/openclaw.json` as `mcp.servers.burrow`, turns tool search off (`tools.toolSearch:
false`), and installs the gate plugin in `~/.openclaw/burrow-gate/`, listed under `plugins.load.paths` and enabled under
`plugins.entries.burrow-gate`. OpenClaw has no setting to keep one server's tools in view, so tool search goes off for
all of them; with it on, gemma4:12b called `tool_search` with arguments it got wrong and never found Burrow (0 of 3).

The gate sits after the edit, not at the end of the turn: after `edit`, `write`, `apply_patch` or `exec`, it runs
`burrow check`, and a change that rests on a decision not yet shown gets the decisions added to that tool's result, so
the model reads them before its next step. (OpenClaw's end-of-turn hook can ask for a revision, but OpenClaw drops that
request once any tool has changed something.) See [integrations/openclaw](../integrations/openclaw).

OpenClaw never shows Burrow's connect-time instructions to the model; the decisions in force come with the first tool
result instead (D-103).

## Hermes Agent

```
burrow connect hermes ~/Notes --write
```

This adds three blocks to `~/.hermes/config.yaml` (or `$HERMES_HOME/config.yaml`), leaving every other line as it was:
`mcp_servers.burrow`, `tools.tool_search.enabled: "off"`, and `burrow-gate` in `plugins.enabled`; and installs the gate
plugin in `~/.hermes/plugins/burrow-gate/`. Hermes has no setting to keep one server's tools in view either, so tool
search goes off for all; with it on, gemma4:12b answered through Burrow 2 times in 6. If one of these is already set to
something else, nothing is written and it says what to set.

The gate checks after each edit (`write_file`, `patch`) and shell command, adding the decisions to that tool's result
when the change rests on one not yet shown, and then uses Hermes' `pre_verify` hook: when the model has edited files
and is about to answer, the decisions go back to it as a message it must answer, and Hermes runs another step. See [integrations/hermes](../integrations/hermes).

Two things to know about Hermes with a local model: it refuses a model whose window is under 64,000 tokens (set
`model.ollama_num_ctx: 65536`), and turn its app connections off (`tools.connectors: false`): in one run the model
called `manage_connections` itself and Hermes created an anonymous account with its maker.

## n8n

`burrow connect n8n ~/Notes` prints what to set; n8n keeps workflows in its own database, so there is nothing to write.
n8n's MCP Client Tool speaks HTTP and Burrow speaks stdio, so a bridge (supergateway, a separate npm program) serves
`burrow mcp` on `http://127.0.0.1:8790/mcp`; the node then uses that endpoint, HTTP Streamable, no authentication, and
"Tools to Include: All". n8n has no tool search. It also has no hook that can hold an agent's reply: a workflow that
changes code can add an Execute Command step running `burrow check <vault> --json` and branch on exit 2 or 3.

## LM Studio

In `~/.lmstudio/mcp.json` (or Program, then Install, then Edit mcp.json):

```json
{ "mcpServers": { "burrow": { "command": "/opt/homebrew/bin/burrow", "args": ["mcp", "/Users/you/Notes"] } } }
```

## llama.cpp

Serve the model with its chat template and room for tools:

```
llama-server -m model.gguf --jinja -c 32768
```

`--jinja` is what makes tool calls work. Then use it from any MCP program above, for example OpenCode's `llamacpp`
provider.

## Ollama

Ollama serves the model; the MCP program is OpenCode (above) or Burrow's own `burrow chat`. One thing to know: Ollama's
OpenAI-format route (`/v1`) ignores the context size a program asks for and loads the model with its full window. For
Qwen3 4B that was 262,144 tokens, 43 GB, and 90 to 140 seconds an answer. Make a copy with a set context instead:

```
printf 'FROM qwen3:4b-instruct-2507-q4_K_M\nPARAMETER num_ctx 16384\n' > Modelfile
ollama create qwen3-4b-16k -f Modelfile
```

## What a vault can hold

Notes and code are read as text. Documents are read into Markdown with a heading per page, using only what macOS
already has, and kept in `~/Library/Caches/Burrow/extracted` by content so each is read once:

| Kind | Read with | Excerpts say |
| --- | --- | --- |
| PDF | PDFKit; pages with no text layer are read by Vision text recognition | the page |
| Word (.docx, .doc), RTF, OpenDocument | the system's text readers | the document |
| Images (PNG, JPEG, HEIC, TIFF, GIF, WebP) | Vision text recognition | text in the image |

## Working memory on disk (llama.cpp)

Text is the format every model reads. A KV cache is the format one model loads: the work it already did reading a
document. Burrow keeps both, filed by model and by the exact files it was built from, so a cache is never loaded into
another model or after its files changed.

```
llama-server -m model.gguf --jinja -c 32768 --slot-save-path ~/Notes/.burrow/kv
burrow kv ~/Notes save Documents/proposal.pdf --vault          read it once and keep the cache
burrow kv ~/Notes ask Documents/proposal.pdf "What are the research questions?" --vault
burrow kv ~/Notes ask Documents/proposal.pdf "..." --vault --cold   read everything again, to compare
burrow kv ~/Notes list --vault
```

## The Burrow skill

`skills/burrow/SKILL.md` teaches an agent how to use the vault: search first, cite file and line, carry conversations
between models, write only when asked. Claude Code: link it into `~/.claude/skills/burrow`. OpenCode reads skills from
`.opencode/skills/` in the project.
