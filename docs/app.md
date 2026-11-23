# The desktop app

CAMR.app is where you read your vault and govern what your AI programs keep. It runs the same engine as the
`camr` command and the MCP server, on the same vault. It needs macOS 26 or later; install it with the installer's
`--app` option, or build it with `app/build.sh`.

## Opening it

A short film plays once each time the app starts: sparks of light on black that land as the stars of the vault's map.
A click skips it; with Reduce Motion on, it is the still wordmark for a second.

The app then opens the last vault straight away. Otherwise the start window shows the wordmark, a line on what CAMR
is, **Open** with the latest vault's name, **New Vault…**, **Open Folder…** and the vaults CAMR knows, with that
vault's map drawn beside them.

## Home: the vault's live map

A vault opens on its map, with no tab open. The notes a connected program looked up in the last ten minutes glow gold,
with a trail to that program's line in the corner ("Claude Code is reading · 11 notes · 7 seconds ago"). Notes a
decision in force rests on wear a green ring, amber when that file changed since, and red for text written to steer an
AI, the same three states as the Watch panel.

The **Home** tab, with the C, sits first in the tab row and is never closed. It, or **View ▸ Home** (⇧⌘H), brings you
back to the live map with every other tab left open.

## The window

A ribbon on the left switches pages; tabs across the top hold notes, Ask and the map side by side (**Open in New
Tab**, **Open to the Right**); the inspector on the right shows the open note's properties, links and the decisions on
it. **⌘K** opens any note or file, or runs a command by name. The status light at the bottom is green when nothing needs a look, amber
when changed code rests on a decision, and red when the vault holds text written to steer an AI.

## Pages

**All** lists every note and linked file, with **New Note**, **New Folder**, rename and **Move to Trash** for your own
notes. Linked code is read-only.

**Ask** answers a question from the vault with a model on this Mac. The answer cites each place it used; under it the
decision line says whether the vault was read and why, **Used** lists the files read in order, and a warning appears
only when the answer cites a place it was not shown. Decisions from the Ledger that it used are named by their label.
**Keep as Note** saves the answer; **What Should CAMR Remember?** proposes notes from the conversation and asks before
writing each. The map beside the answer lights up the files read.

**Conversations** shows every connection a program made: what it asked, searched for, read and kept, and the handoff
it left. **Open Conversation** shows it whole.

**Ledger** lists what programs kept, newest first, on branches. It opens with three counts: the rules handed to every
program, files changed under a decision, and lines written to steer an AI. Each decision shows its reason and what was
rejected in full, who kept it and with which program. **Still Right** confirms a decision whose file changed, **Mark
Wrong…** retires it with what is right, **Keep newer** or **Keep both** (in the Watch panel) settles two decisions that overlap,
**Confirm Check** turns on a decision's check, and **Share with Team** or **Drop** answers a program's request to share.
**Resume** shows what the next program will be handed.

**Library** shows the vault's folders, linked folders (**Link a Folder…**, **Unlink**), bridged vaults (**Add a
Bridge…**) and teams, with a storage bar for this vault and one for all vaults, amber when nearly full.

**Programs** reads each AI program's own settings on this Mac and says whether it will find this vault: connected,
not set up, set up for another vault. Each program shows its own app's icon when it is installed (Claude, Codex,
Ollama, LM Studio); CAMR asks macOS for it and bundles no one's logo. **Connect** shows exactly what it will change and writes it when you agree;
**Copy** gives you the setup line instead.

**Map** (⇧⌘G) draws the vault as a graph of notes and the links between them, coloured by folder, with the same
rings for decisions as Home.

**Sessions** (⌘6) shows each live or recent Claude Code and Codex session that ran with CAMR's session hooks: its
context per request with each compaction marked, the tokens CAMR kept out, recalls and outputs expanded, every step
CAMR took, and the lines to resume it in Claude Code, Codex or `camr chat`, ready to copy. It reads again every few
seconds while open. A strip shows which parts are on, where the archive is and how big, and says when the archive's
drive is not connected. The switches are changed with `camr session settings` for now. See
[sessions.md](sessions.md).

## The Watch panel

The Watch stays beside whatever page is open and shows what a connected program is shown: the rules in force, what
`camr_check` would show for the code changed right now, and lines written to steer an AI, with their file and line.

## When the app asks you

- **Linked folders**: a vault that names folders you have not approved asks once, listing each real path. **Allow**
  reads them from then on; **Not now** leaves them out.
- **Confirming a decision's check** asks in the app's own window, the strongest place to do it, because no program
  can answer for you there. Overriding a broken decision is done in your own terminal with
  `camr decision override`.

## Themes

Ember, tuned to the logo's orange, is the default; Nebula, Aurora and Tide are there too. Type "Theme" in the ⌘K
palette.
