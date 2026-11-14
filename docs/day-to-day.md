# Burrow day to day

What a normal day with Burrow looks like, once a vault is set up. The examples use `~/Notes` as the vault and a code
folder linked into it as `matatu`.

## Once

```
burrow link ~/Notes ~/code/matatu      # the code stays where it is, read-only; linking it here also approves it
burrow index ~/Notes --vault           # opens the folder as a vault and builds the index
claude mcp add --scope user burrow -- /full/path/to/burrow mcp ~/Notes
```

Or open the folder in the app, then **Programs → Connect** for the line with your paths filled in. Other programs are
in [connect.md](connect.md).

## Asking about your own things

Ask your usual program a question the vault can answer ("What did the landlord agree about the deposit?"). It calls
`burrow_find`, reads the excerpts with their file and line, and says when the vault does not hold the answer. In the
app, **Ask** does the same with a model on this Mac, and lists the files it read and any decisions from the Ledger it
used.

## Keeping a decision

When you settle something, say so: "Make this the decision and keep it in Burrow, with the reason." The program calls
`burrow_commit` with the decision, why (`because`) and what was turned down (`rejected`), naming the files it rests on.
Burrow refuses a decision without a reason. You will see it on the app's **Ledger** page, signed with the program's
name.

## Picking up tomorrow, in any program

A new session, a different program or a small local model starts with what was kept:

- On connecting, every program is handed the decisions in force, each with its reason.
- `burrow_resume` gives the plan, where the last session stopped and the latest decisions.
- Claude Code's hooks (`burrow hook install claude ~/Notes`) hand this over at session start and write a handoff when
  it compacts or ends.

Each connection is kept as its own conversation; the app's **Conversations** page shows what each one looked up, read
and kept.

## Before calling a code change done

The program calls `burrow_check`: Burrow reads what changed in the linked code since its last git commit and puts the
decisions resting on those files beside the diff. The program then keeps to each decision, undoes that part, or tells
you which decision the change goes against. Files a build leaves (`__pycache__`, `.pyc`, `node_modules`) are named on
one line, not counted.

A program that never calls it is still stopped: Claude Code's Stop hook and git's pre-commit hook
(`burrow hook install git-gate ~/Notes`) run the same check, and hold a change that touches a decision until it has
been shown once. `burrow check ~/Notes` does it by hand.

## When a file a decision rests on changes

The decision is not dropped. Programs are still handed it, marked **check again**, and the app's **Watch** panel shows
it amber with **Still Right**. Look at the change, then:

- it still holds: **Still Right** in the app, or `burrow confirm ~/Notes <commit>`;
- it no longer holds: **Mark Wrong…** in the app, or `burrow revert ~/Notes <commit> "what is right now"`.

Nothing is deleted either way.

## Glancing at it

- The status bar light: green when nothing needs a look, amber when changed code rests on a decision, red when the
  vault holds text written to steer an AI.
- `burrow log ~/Notes` lists what was kept, newest first; `burrow --version` says which `burrow` you are running.

## More than one vault

Keep a vault for each part of your life (`~/Notes` for home, `~/Work` for the job) and let one read another:

```
burrow vault new ~/Work --name Work     # makes the folder a vault and builds its index
burrow bridge ~/Notes ~/Work            # ~/Notes can now read Work; Work can't read ~/Notes
burrow bridge list ~/Notes
burrow unbridge ~/Notes Work
```

Through the bridge, `burrow find`, `burrow ask`, a connected program's `burrow_find` and `burrow_read`, and the app's
Library, search and Ask also look in Work. Everything from it is marked with its name, like
`Work › Projects/launch.md`, and is only ever read: Burrow never writes into Work from `~/Notes`. A bridge only goes
one step: if Work bridges to a Team vault, `~/Notes` still can't see Team. Work's decisions stay private unless you add
`--with-ledger`. In the app, the Library shows Work as its own section, and **Bridges** at its top adds or removes one.

Bridges are kept in Burrow's own folder on your Mac, never inside a vault, so a vault folder someone gives you (a
download, a cloned repo, a shared folder) can't bring bridges to your other vaults with it. If `burrow bridge list` says
it found bridges written inside a vault folder, they are ignored; if you made them with an early build, add them again
with `burrow bridge`. Through a bridge, Work's linked code is found by search but not opened from disk.

## Linked folders you haven't approved

A vault's list of linked folders lives inside the vault folder, so a vault someone gives you could name any folder on
your Mac. Burrow reads a linked folder only once you have approved it, on this Mac, for that vault. A folder you link
yourself, with `burrow link` or **Link a Folder…** in the app, is approved as you link it, so there is nothing more to do.

The first time a vault opens with a linked folder you haven't approved, the app shows the folders and asks: **Allow**
reads them from then on, **Not now** leaves them out and asks again next time. In Terminal, any command that opens the
vault says in one line which folders it skipped, with each one's real path; run through a pipe, or by a program you've
connected, it only says how many. Until you say yes, nothing in them is indexed, searched, read, checked by
`burrow check`, or shown to a connected program, which is only told how many are waiting.

Approving, and linking (which approves), only work in your own Terminal window: Burrow shows each folder's real path
and asks you to type yes. Run from Claude Code or any other program, or through a pipe, they refuse and say to use the
app or your own terminal, so a vault someone gave you can't talk a connected program into approving its folders.

```
burrow link list ~/Notes                                  # each linked folder, approved or not, with its real path
burrow link approve ~/Notes /Users/me/code/matatu         # one, by its real path from the list (or its name); asks, type yes
```

Names and paths from a vault's list are printed with control characters taken out, so a list someone else wrote can't
rewrite your terminal. Burrow never follows a linked folder that is the vault itself, holds the vault, or is or holds
its `.burrow` store, whoever approved it. If an approved folder's path is a symlink that is later pointed somewhere
else, the new place isn't approved: it is skipped until you approve it.

A vault you linked folders into with an earlier build needs this once: approvals are new (D-101), and Burrow can't tell a link
you made from one someone else wrote into the list. Approvals are kept in Burrow's own folder, never in the vault, and
belong to the vault where it is: a copy of the vault somewhere else, or a link that now leads to another folder, asks
again.

## How much Burrow keeps

Burrow's own store (the index, meaning search, conversations, the Ledger) lives in `.burrow`. Your own files are never
counted against a limit and never deleted.

```
burrow stats ~/Notes                              # what the store holds, against any limit, and your files beside it
burrow config ~/Notes set storage.limit 2GB       # this vault
burrow config --global set storage.limit 20GB     # every vault Burrow knows, together
burrow config ~/Notes set index.maxFileSize 5MB   # leave bigger files out of the index
burrow config ~/Notes list
```

When indexing would go over a limit, Burrow stops adding to the index and says which limit, by how much, which files
were left out and the command to raise it. Nothing is deleted, and what is already indexed keeps working. The app's
Library shows a bar for this vault and one for all vaults, amber when nearly full.
