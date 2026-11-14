# Burrow day to day

What a normal day with Burrow looks like, once a vault is set up. The examples use `~/Notes` as the vault and a code
folder linked into it as `matatu`.

## Once

```
burrow link ~/Notes ~/code/matatu      # the code stays where it is, read-only
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
