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
(`burrow hook install git-gate ~/Notes`) run the same check, and hold a change that touches what a decision rests on
until it has been shown once. A change elsewhere in the same file passes. Give a decision a check (a test, or a pattern
no added line may match) with `burrow decision check ~/Notes <id> --set "…"`, and a change that fails it is held every
time, not just once. `burrow check ~/Notes` does it by hand. See the Ledger guide.

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

## Sharing with a team

A team shares one folder: a git repository each of you clones, or a folder iCloud Drive or Dropbox keeps in step.
Each of you keeps your own vault and joins the team folder from it. It replaces pasting decisions into a chat thread
and hoping everyone's AI reads it: a decision one of you keeps is handed to every teammate's programs, with who kept it
and why.

```
burrow team join ~/Notes ~/code/matatu-team --name Team --as "Wanjiru Kamau"   # in your own Terminal; type yes
burrow commit ~/Notes "Refunds after a provider timeout are never sent again automatically." \
  --kind decision --because "Sending again after a timeout paid 38 passengers twice." --team
cd ~/code/matatu-team && git add -A && git commit -m "Refund decision" && git push         # or let the folder sync
burrow team log ~/Notes          # what the team shared, newest first, with who kept each
burrow team list ~/Notes         # the teams this vault reads, and the name you sign with
burrow team leave ~/Notes Team   # stop reading it; nothing in the team folder is touched
```

- **Searching**: the team folder's notes come up in `burrow find`, `burrow ask`, `burrow chat`, a connected program's
  `burrow_find` and `burrow_read`, and the app, marked `Team › Plans/refunds.md`. Your own vault stays yours: your
  teammates' Burrows never read it.
- **Sharing a decision**: tell your program to share it with the team (it calls `burrow_commit` with `share: team`),
  add `--team` to `burrow commit`, or tick **Share with Team** where you keep a decision in the app. It goes into the
  team folder, not your own Ledger, signed with your name and the program: "kept by Wanjiru Kamau with Claude Code".
  Your name comes from `--as`, else git's `user.name` in the team folder, else your Mac's full name, and is set once.
- **What your programs are told**: when a program connects, your own decisions come first, then the team's, eight in
  all at most (three to five from the team). A search hands over team decisions that match it, the same way.
- **Two people at once**: each person and Mac writes their own files in their own folder inside the team folder
  (`.burrow/ledger/wanjiru-kamau-7939/`), and never changes one. So `git pull` never has a conflict to resolve, and a
  synced folder never makes a "conflicted copy".
- **Disagreeing**: you never delete a teammate's decision. Mark it wrong with `burrow team revert ~/Notes <id> "what is
  right"`, or keep a new one that supersedes it; their file stays as it was, and everyone's programs stop being
  handed it.
- **What the team folder can't do**: it is your teammates' writing, so Burrow treats it as text to read and nothing
  more. A list of linked folders, bridges or settings inside it is never followed, a link inside it that points out of
  it is not read, a check written with a team decision is shown as proposed and never run, and a decision written to
  steer an AI is never handed to a program. Joining only works in your own Terminal window, so a program can't join a
  folder for you.

**Your own several Macs** work the same way: make a private git repository or a synced folder, and join it from your
vault on each Mac with the same `--as` name. Each Mac writes into its own folder there, so two Macs never clash.

What runs where: the team commands, the app and the shared Ledger are macOS only, like the rest of Burrow. The team
folder itself is plain files, so it can live in any git host or sync service; nobody on Linux or Windows can run
Burrow against it yet.

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
