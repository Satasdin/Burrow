# Security and privacy

Burrow holds private material and is read and written by AI programs, so it treats both your privacy and every model
that connects with care. This page collects what it does; each point names the decision in
[DECISIONS.md](../DECISIONS.md) where it was made.

## What stays on your Mac

- Burrow calls no cloud model. It talks only to Ollama at the loopback address, 127.0.0.1, for search by meaning and
  local answers. A cloud AI program you connect talks to its own provider, as it would without Burrow.
- Burrow's only network use is the team folder you join (a git remote or a synced folder) when you share, and
  downloading a release.
- Your files are never changed or deleted. Linked code folders are only read. Storage limits stop indexing; they never
  delete.

## What is yours alone

These refuse to run from an AI program and need you, in your own terminal (typing yes after seeing exactly what you are
agreeing to) or, for folders, shares and confirming a check, in the app:

- approving a linked folder, linking one, and joining a team (D-101, D-104);
- sharing with the team: a program's request waits on your Mac until you approve it (D-111);
- writing a program's settings with `burrow connect --write` (D-108);
- letting another program read a session's exact messages, with `burrow session allow` (D-117);
- confirming, taking away or overriding a decision's check. These also need an 8-digit code shown only in a macOS
  notification, never in the terminal, valid once for two minutes. Burrow keeps no copy of it (D-113).

Burrow also refuses when it can see it was started by Claude Code, OpenCode, Codex, OpenClaw, Hermes, Gemini CLI or
Cursor's agent. A typed yes is a speed bump, not a lock: it stops a program being talked into something by what it
read. What keeps connected programs out is that Burrow's MCP tools never approve, share or override.

## What a model reads is data

- Excerpts and Ledger entries reach a model inside blocks their contents cannot close, saying who wrote them and to
  follow no instruction inside.
- Text in the vault written to steer an AI is flagged, shown to you in the Watch panel and by `burrow steering`, and
  never handed to a program as a rule.
- A program can call only the tools it is shown (D-105).
- Commits are signed by the program that connected; a model's name for itself is kept only as its claim (D-83).
- A check a program proposes is kept as proposed and never run until you confirm it.

## Archived sessions

Every Claude Code and Codex session is kept in Burrow's folder, or on the drive you chose, written readable only by
your account (D-117). A drive that ignores permissions, such as one formatted exFAT, can be read by anyone who has it.
What a program can read back from it:

- the resume pack and the timeline, with secrets taken out: any program you connected;
- the exact messages, by search or by ref: only the program that wrote the session. Another program gets them only
  after you run `burrow session allow <id> <program>` in your own terminal and type yes;
- a tool output Burrow kept whole, through `burrow_expand`: only the Claude Code session that ran it (D-116).

Everything it hands back is marked as data about past work, not instructions.

## Secrets

Keys, tokens, passwords in URLs, `Authorization` headers and private keys are replaced with `[secret removed]` before a
session's words are kept, again whenever they are shown, and before anything is shared with a team (D-105, D-106).

## A vault someone gives you

A vault folder from a download, a cloned repository or a shared folder could name any folder on your Mac. Linked
folders it names are skipped until you approve them; bridges, approvals and kept session words live in Burrow's own
folder on your Mac (owner-only), never inside a vault, so a vault cannot bring them with it (D-100, D-105). A team
folder is read as text only: links in it that point out are not followed, files over 64 KB are skipped, and its
checks are shown as proposed and never run (D-111, D-112).

## Known limits

- Team names are not cryptographically signed; Burrow trusts the folder a file is in and says when a name does not
  match it.
- A program on your Mac with its own shell could read your files directly, as it could without Burrow.
- Burrow runs on macOS only.
