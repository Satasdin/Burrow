# Burrow documentation

Burrow is one memory on your Mac that every AI model you use shares. It keeps your notes, documents and code, and a
Ledger of the decisions made with your models and why, so a private local model knows what you know and the next
model, in any program, starts from what was settled.

## Start here

| Guide | For |
| --- | --- |
| [Getting started](getting-started.md) | installing, a first vault, connecting your first program, checking it works |
| [Day to day](day-to-day.md) | a normal day: asking, keeping a decision, picking up tomorrow, teams, several vaults |
| [The desktop app](app.md) | every page of Burrow.app |
| [Connecting programs](connect.md) | Claude Code, OpenCode, OpenClaw, Hermes Agent, n8n, LM Studio, Ollama, llama.cpp |
| [The Ledger](ledger.md) | decisions, the check of new work, hooks, verdicts, folds |
| [The engine](engine.md) | how Burrow answers from your material: decide, fit, answer, check, learn |
| [Tool reference](tools.md) | every MCP tool, what it takes and returns |
| [Security and privacy](security.md) | what stays on your Mac, and what Burrow defends against |
| [Model working memory](kv.md) | keeping a llama.cpp model's cache on disk |
| [Skills for agents](../skills/README.md) | the skill pack that teaches an AI program to use Burrow well |

## Everything Burrow does

Each capability, where to use it, and where it is explained. **App** is Burrow.app, **Terminal** the `burrow` command,
**Programs** what a connected AI program calls over MCP.

### Your material

| Capability | App | Terminal | Programs | Guide |
| --- | --- | --- | --- | --- |
| Open any folder of Markdown as a vault (an Obsidian vault works as it is) | Open or Create a Vault… | `burrow vault new`, `burrow index --vault` | | [Getting started](getting-started.md) |
| Link code folders read-only, approved by you on this Mac | Link a Folder…, Allow | `burrow link`, `link list`, `link approve` | | [Day to day](day-to-day.md#linked-folders-you-havent-approved) |
| Search by words and by meaning together, with file and line | Search, Library | `burrow find` | `burrow_find` | [Engine](engine.md) |
| Read a file with the decisions resting on it and its neighbours | any note | | `burrow_read` | [Tools](tools.md) |
| Links between notes and code, and a map of the vault | Map, Graph | `burrow links` | `vault_links` | [App](app.md) |
| Answer a question with a local model, citing file and line | Ask | `burrow ask`, `burrow chat`, `burrow tui` | `vault_ask` | [Engine](engine.md) |
| Prepare a question for any other model | | `burrow brief` | `vault_prepare` | [Engine](engine.md) |
| Fit how much a model is shown to what it can read in time | | `burrow fit` | | [Engine](engine.md) |
| Methods for kinds of task (skills in the vault) | | `burrow skills` | | [Engine](engine.md) |
| Read another vault, one way and read-only | Library, Bridges | `burrow bridge`, `unbridge` | through `burrow_find` | [Day to day](day-to-day.md#more-than-one-vault) |
| Storage limits that never delete | Library | `burrow stats`, `burrow config` | | [Day to day](day-to-day.md#how-much-burrow-keeps) |
| A model's working memory kept on disk | Shelf | `burrow kv` | | [kv.md](kv.md) |

### Decisions and the Ledger

| Capability | App | Terminal | Programs | Guide |
| --- | --- | --- | --- | --- |
| Keep a decision only with its reason, what was rejected and the files it rests on | Keep | `burrow commit`, `burrow note` | `burrow_commit` | [Ledger](ledger.md) |
| Hand the decisions in force to every program when it connects | Watch | `burrow resume` | first tool result | [Ledger](ledger.md) |
| Attach the decisions that fit a search or a read | | | `burrow_find`, `burrow_read` | [Tools](tools.md) |
| Catch a decision that overlaps one in force | Keep newer, Keep both | `--supersedes`, `--alongside` | `supersedes`, `alongside` | [Ledger](ledger.md) |
| Mark a decision to check again when its file changes | Still Right, Mark Wrong… | `burrow confirm`, `burrow revert` | `burrow_revert` | [Day to day](day-to-day.md#when-a-file-a-decision-rests-on-changes) |
| History, blame and diff of what AIs understood | Ledger | `burrow log`, `blame`, `diff`, `branch` | `burrow_log`, `burrow_blame`, `burrow_diff` | [Ledger](ledger.md) |
| Keep what a conversation decided, with your consent | Keep as Note | `burrow learn`, `/keep` in chat | `vault_remember` | [Engine](engine.md) |
| Lines written to steer an AI, flagged and never handed over | Watch | `burrow steering` | flagged in results | [Security](security.md) |

### Checking new work

| Capability | App | Terminal | Programs | Guide |
| --- | --- | --- | --- | --- |
| A verdict per decision on your change: unaffected, affected, unprovable, breaks | Watch | `burrow check` | `burrow_check` | [Ledger](ledger.md#the-gate-burrow-check) |
| A test or forbidden pattern that enforces a decision | Confirm Check | `burrow decision check` | proposes with `check` | [Ledger](ledger.md#the-gate-burrow-check) |
| Hold a change in Claude Code before it says done | | `burrow hook install claude` | Stop hook | [Ledger](ledger.md#claude-code) |
| Refuse a git commit that breaks a decision | | `burrow hook install git-gate` | pre-commit | [Ledger](ledger.md#git) |
| The same gate inside OpenCode, OpenClaw and Hermes Agent | Programs | `burrow connect` | plugins | [integrations](../integrations/README.md) |
| Override a broken decision, only by you, with a code from a notification | | `burrow decision override` | refused | [Security](security.md) |

### Carrying work on

| Capability | App | Terminal | Programs | Guide |
| --- | --- | --- | --- | --- |
| Each connection kept as its own conversation, with a handoff when it ends | Conversations | | automatic | [Connecting](connect.md) |
| Resume where the last session stopped, what it was in the middle of | Resume | `burrow resume` | `burrow_resume` | [Tools](tools.md) |
| Claude Code's exact words kept at every compaction and handed back | | `burrow recall` | `burrow_recall` | [Ledger](ledger.md#claude-code) |
| Pick up a conversation another program started | Open Conversation | | `vault_session_list`, `vault_session_resume` | [Tools](tools.md) |

### Programs and teams

| Capability | App | Terminal | Programs | Guide |
| --- | --- | --- | --- | --- |
| Set up a program in one command: server, tools in view, gate | Programs, Connect | `burrow connect` | | [Connecting](connect.md) |
| Both forms of MCP, with and without the handshake | | `burrow mcp` | | [Tools](tools.md) |
| Share decisions with a team through a git or synced folder | Ledger | `burrow team join`, `log`, `leave` | `share: team` | [Day to day](day-to-day.md#sharing-with-a-team) |
| A program's share waits until you approve it | Share with Team, Drop | `burrow team pending`, `approve`, `discard` | waits | [Day to day](day-to-day.md#sharing-with-a-team) |

## Why it works this way

Every behaviour above has a numbered entry in [DECISIONS.md](../DECISIONS.md) with the run or review that caused it and
the evidence after the change. The test record is in [evaluation/test-cases.md](evaluation/test-cases.md), and the
requirements are traced to their code in [evaluation/traceability.md](evaluation/traceability.md).
