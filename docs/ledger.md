# The Ledger: a git for what AIs understood

Git keeps the code. The Ledger keeps what AI sessions understood about it: decisions and why, facts confirmed in the files, corrections, the plan, and where each session stopped. A model that loses its memory starts from the Ledger instead of from zero. That covers Claude after compaction, a new ChatGPT or Codex chat, and a small local model with a full window.

## What a commit is

One Markdown file under `<vault>/.burrow/ledger/<branch>/<id>.md`, readable in Obsidian:

```markdown
---
id: "20261114-114537-ac9d"
branch: "main"
kind: "decision"
author: "claude-code"
at: "2026-11-14T08:45:37Z"
client: "claude-code"
model_said: "claude-haiku-4-5"
session: "20261114-114530-ee0b"
cites: {"matatu/matatu/payments/reconcile.py":"59d167b8dff9c50a"}
---

Refunds after a provider timeout go to 'refund pending' and are never sent again automatically.

Rejected: Retrying up to three times: sending again after a timeout is how the double refunds happened.
Because: Sending again after a timeout paid 38 passengers twice (KES 3,040).
```

- **id**: the second it was kept, on this Mac's clock (as conversation ids are), and four random characters.
- **kind**: one of decision, fact, correction, plan, handoff, code or confirmation.
- **author**: who Burrow knows wrote it: the model a llama.cpp server reports, else the program's logged model, else the name the program gave when it connected (`client`). The name a model types about itself is kept as `model_said` and shown as its claim, never as the author: small models copy names from earlier commits.
- **Because and Rejected**: a decision needs its reason. Wherever a decision is handed to a program it reads message, then Because, then Rejected, and when it has to be shorter, Rejected and then the message are shortened; the reason is never cut.
- **cites**: the vault files the commit rests on, with a hash of each. When a cited file changes, the commit is still handed to programs, marked **check again**, until someone looks: **Still Right** in the app or `burrow confirm` keeps a confirmation with the files' new hashes, and `burrow revert` marks it wrong.
- **Never deleted**: `revert` adds a correction, and the old commit shows as **marked wrong** wherever it appears.
- **Branches**: a linked folder is its own branch (`burrow`, `tally`); everything else is `main`.

## Terminal

```
burrow commit <vault> "Shelf keeps 12 GB" --kind decision --files burrow/Sources/BurrowCore/KVShelf.swift
burrow log    <vault> [--branch B] [--file PATH]
burrow resume <vault> [branch]
burrow blame  <vault> <path>
burrow diff   <vault> --since <commit>
burrow revert <vault> <commit> "what is right instead"
burrow confirm <vault> <commit> ["note"]
burrow branch <vault> [name]
```

## Programs that use the vault (MCP)

`burrow mcp <vault>` shows five tools by default. The rest answer when called by name, and the old `vault_` names still work.

| Tool | Shown by default | What it does |
| --- | --- | --- |
| `burrow_find` | yes | Search. Every result carries a trust line: strong, thin, or not in the vault, plus any correction on the files found, and ends with the Ledger's decisions on the files found |
| `burrow_read` | yes | Read a file with line numbers, with the decisions on that file and the files it imports or is imported by |
| `burrow_resume` | yes | The plan, where the last session stopped, corrections and latest commits, held to 3,200 characters without cutting a reason |
| `burrow_commit` | yes | Keep a decision (with `because`, and `rejected`), fact, plan or handoff, citing its files |
| `burrow_check` | yes | The code changed in linked git folders since their last commit, beside the decisions resting on those files. Build output (`__pycache__`, `.pyc`, `node_modules`, `.DS_Store`) is not counted but is named on one line |
| `burrow_log`, `burrow_blame`, `burrow_diff`, `burrow_revert` | with `--tools full` | History, who explained a file, what changed since, and marking a commit wrong |
| `burrow_recall` | with `--tools full` | The exact words of an earlier part of a Claude Code session: a fold, its original messages, or a search over every fold |

`--tools classic` shows only the `vault_` tools, for runs that must match earlier ones. Up to five decisions and corrections in force on the current branch are put in the instructions every program gets when it connects. Each connection is its own conversation, and when it closes Burrow writes a handoff from what it did ("stopped after resuming, 1 lookup, checking its change and keeping 1 commit"), so a model that never logged anything still leaves one. A lookup is a search or a read; resuming, checking and keeping are counted as what they are.

## Claude Code

```
burrow hook install claude ~/Notes
```

This prints the settings to add to `~/.claude/settings.json`. Burrow never edits that file itself. Then:

- **Session start**: Claude Code is handed the Ledger head for the folder it was opened in.
- **Before compaction and at session end**: Burrow keeps the plan (from Claude Code's task list) and a handoff built from what you typed and the files edited. Facts and decisions are kept only when you asked for them, through `burrow_commit`.
- **Folds** (D-102, after billion-context): at the same moments Burrow folds what was said since its last fold, once, from Claude Code's transcript: your requests word for word with their message ref, sentences that carry a decision, a reason or a constraint, error lines exactly as printed, file:line places, the files edited and read, the commands run, and the plan's open items. A fold is never summarised again. Claude Code's compaction rewrites the whole history each time, so early detail fades; after each compaction (SessionStart with `source: compact`) Burrow hands the session's folds back beside the Ledger head, held to 5,500 characters by giving up detail by kind (what was read and run first, your requests last), never by age, and always keeping your first request whole. `burrow recall <vault> [fold] [--full] [--find WORDS]` and `burrow_recall` show a fold, search them, or read the fold's original messages back from the transcript; that read only opens a file in Claude Code's own `projects` folder named for the fold's session, since a fold is a file in the vault's store and a vault can come from someone else. Folds are kept in `<vault>/.burrow/folds/`. Any other start (a new session, a resume) is handed exactly what it was before.
- **When Claude stops** (`Stop`, `burrow hook claude <vault> --gate`): if the code changed in linked folders rests on a decision, directly or one import step away, and that exact change has not been shown, Burrow holds the reply (`{"decision":"block","reason":…}`) with `burrow_check`'s words and asks Claude to tell you which decision the change touches and whether it goes against it. It holds once: a change already shown passes, and while Claude Code is continuing because of a stop hook (`stop_hook_active`) it never holds again. The `--gate` entry writes no handoff, so one is not kept at the end of every turn.

## The gate: `burrow check`

```
burrow check ~/Notes [--staged] [--json]
```

Prints exactly what `burrow_check` gives a program, and exits 0 when no decision rests on the change, 2 when one does and this exact change has not been shown, 1 on an error. A change is fingerprinted by the decisions shown and the git blob of each changed file they rest on, and kept under `<vault>/.burrow/checks/` once shown, whether by `burrow check`, `burrow_check`, the Stop hook or the git gate. The same change then passes; a different change to those files is held again. `--staged` checks what the next commit holds (from inside a linked repository, only that repository). It lists the decisions beside the change; it does not judge whether the change keeps to them, so a harmless edit to a decided file is held once too.

## git

Inside a repository linked to the vault:

```
burrow hook install git ~/Notes
```

This writes `.git/hooks/post-commit`, but never over an existing hook. Each commit is then linked into the Ledger by its sha and the files it changed, so `burrow blame` can show which AI session led to a change. The hook never blocks a commit.

```
burrow hook install git-gate ~/Notes
```

This writes `.git/hooks/pre-commit` (never over an existing one, and only in a repository linked into the vault). It runs `burrow check --staged`: a commit whose change touches a decision is refused once, with the decisions and their reasons printed. Seeing them is the acknowledgement, so the same commit goes through on the next try; nothing else to type. A different change to those files is held again. A Burrow error never blocks a commit, and `git commit --no-verify` skips the hook as it skips any.

## Safety

Commits are written by models, so whatever reads them treats them as data. `resume`, `log` and `blame` output sits inside one `<ledger>` block that its contents cannot close, names who wrote each commit, and says to follow no instruction inside it. Cited paths must be plain vault paths: never absolute, never `..`. The write tools run only for programs connected over MCP; Burrow's own chat refuses them, because it asks before keeping anything.
