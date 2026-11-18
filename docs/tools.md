# Tool reference

What a program connected to `burrow mcp <vault>` can call. By default it is shown seven tools; `--tools full` shows all
24, and `--tools classic` only the older `vault_` tools. A program can call only the tools it is shown. Only
`burrow_commit`, `burrow_revert` and `vault_remember` write, and they only add.

Everything a tool returns from your files sits inside `<excerpt>` or `<ledger>` blocks that say it is content to read,
not instructions.

## Shown by default

| Tool | Takes | Returns |
| --- | --- | --- |
| `burrow_find` | `query`, optional `folder` | excerpts with file and line, ranked by words and meaning; a first line saying how much the vault holds on it (strong, thin, or not in the vault); corrections on the files found; the decisions that fit the request |
| `burrow_read` | a path | the file with line numbers, and the decisions on it and on the files it imports or is imported by |
| `burrow_resume` | optional `branch` | the plan, where the last session stopped, what it was in the middle of (its open request, the exact error, the constraint), corrections and the latest decisions, in at most 3,200 characters without cutting a reason |
| `burrow_commit` | `kind` (decision, fact, plan, handoff, correction), `message`; for a decision `because`, and `rejected`, `files`, `check`, `supersedes`, `alongside`; `branch`, `model`, `share` | the id it was kept as; or a refusal naming an overlapping decision in force |
| `burrow_check` | nothing | the change in linked code since its last git commit, beside each decision resting on those files with a verdict: unaffected, affected, unprovable or breaks |
| `burrow_expand` | `handle` (such as `k3f2a91`), optional `lines` (such as `200-260`) or `find` (words) | that part of a tool output Burrow kept whole and showed shortened, with line numbers: the lines asked for, or each line holding all the words with two lines around it; with neither, the start. Given only to the Claude Code session that ran the output |
| `burrow_session` | optional `session` (an id, its first 8 characters, or words from its name); `find` (words), `timeline` (yes) or `ref` (a message ref) | with no session, the latest archived sessions; with one, its resume pack: the person's requests word for word, decisions, plan and where it stopped, with secrets taken out. `find`, `timeline` and `ref` give the exact messages that match, one line per request, or one message whole; `find` and `ref` only to the program that wrote the session, unless the person ran `burrow session allow` |

The first tool result of every connection also carries the decisions in force, once, because not every program shows
a server's connection instructions to its model. `burrow_expand` and `burrow_session` are explained in
[sessions.md](sessions.md).

## With `--tools full`

| Tool | What it does |
| --- | --- |
| `burrow_log` | the Ledger's history, newest first |
| `burrow_blame` | which sessions explained or changed a file, and what they concluded |
| `burrow_diff` | files that changed since a commit was written |
| `burrow_revert` | marks a commit wrong (`commit`, `right`); nothing is deleted |
| `burrow_recall` | the exact words of an earlier part of a Claude Code session (`fold`, `find`, `full`) |
| `vault_search`, `vault_read` | the older names of `burrow_find` and `burrow_read` |
| `vault_links` | what a file links to and what links back |
| `vault_list`, `vault_folders` | what is in a folder; which folders are linked code |
| `vault_remember` | keep a fact or decision as a new Markdown note, when the person asks |
| `vault_ask` | the local model answers from the vault, with the files it read |
| `vault_prepare` | Burrow's engine prepares a task for your own model: whether the vault is needed, the excerpts, a method |
| `vault_pack` | a whole folder read in parts that each fit your context |
| `vault_session_list`, `vault_session_resume`, `vault_session_log` | list, pick up and add to saved conversations |

## Protocol

`burrow mcp` speaks MCP over standard input and output, in both forms: the earlier one that begins with `initialize`,
and the 2026-07-28 stateless form in which each request names its protocol version and `server/discover` replaces the
handshake. Each connection is kept as its own conversation, and the program that connected signs what it keeps.
