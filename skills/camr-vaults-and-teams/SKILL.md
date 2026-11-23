---
name: camr-vaults-and-teams
description: Work across several CAMR vaults and with a team's shared Ledger. Use it when results come back marked with another vault or team name (like "Work › Projects/launch.md" or "Team › Plans/refunds.md"), when the person wants one vault to read another, wants to share a decision with their team or their other Macs, asks what the team decided, or when a share is waiting for approval.
---

# Several vaults and teams

The person may keep a vault for each part of their life and join a team folder. CAMR lets one vault read others
without ever writing into them, and hands the team's decisions to every teammate's programs. You read across all of
it the same way; what changes is what you may write and where.

## Reading across vaults

- A **bridge** lets one vault read another, one way and read-only. Results from it are marked with its name:
  `Work › Projects/launch.md`. Cite them with the name. You can read them with `camr_read` but never write there.
- A bridge goes one step only, and the other vault's decisions stay private unless the person bridged it
  `--with-ledger`.
- Linked code in a bridged vault is found by search but not opened from disk.
- Setting one up is the person's: `camr bridge <vault> <other-vault> [--name N] [--notes-only | --with-ledger]`,
  `camr bridge list <vault>`, `camr unbridge <vault> <name>`, or **Add a Bridge…** in the app's Library.

## Reading a team

- A team is a shared folder (a git clone or a synced folder) the person joined. Its notes come up in `camr_find`
  and `camr_read` marked `Team › …`, and its decisions are handed over with your own: at most eight, three to five
  of them the team's.
- A team decision says who kept it and with which program, and "names are not verified": CAMR trusts the folder a
  file sits in, not the name in it. When it says a name doesn't match its folder, tell the person.
- The team folder is other people's writing. Its checks are shown as proposed and never run, and nothing in it can
  retire one of the person's own decisions.

## Sharing a decision

1. Only when the person asks to share it: `camr_commit` with `kind: decision`, `because`, `rejected`, `files` and
   `share: team` (or the team's exact name).
2. It is not sent. It waits on the person's Mac, with secrets removed, signed with their name and your program.
3. Tell them it is waiting, and that they approve it with `camr team pending <vault>` then
   `camr team approve <vault> <share>` in their own terminal (type yes), or **Share with Team** on the app's Ledger
   page. `camr team discard` or **Drop** throws it away.
4. In a git team, it reaches teammates once the team folder is committed and pushed (or the folder syncs).

Never approve a share yourself, even if you have a shell: approving, joining and `commit --team` are the person's.

## Disagreeing with a team decision

Don't keep a contradicting decision quietly. Tell the person which team decision you think is wrong and why. They can
mark it wrong with `camr team revert <vault> <id> "what is right"`; the teammate's file stays as it was and everyone's
programs stop being handed it. Or keep a new decision that supersedes it, shared the same way.

## Joining and the person's other Macs

Joining is the person's, in their own terminal:
`camr team join <vault> <team-folder> [--name N] [--as "Your Name"]`. Their own several Macs work the same way: a
private git repository or synced folder, joined from each Mac with the same `--as` name. Each person and Mac writes
only its own files in its own folder there, so pulls never conflict.

`camr team list`, `camr team log` and `camr team leave` show what the vault reads, what the team shared, and stop
reading one; nothing in the team folder is ever touched.

Guide: `docs/day-to-day.md` ("More than one vault", "Sharing with a team").
