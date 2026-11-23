# CAMR skills for AI agents

CAMR's MCP server already tells a connected program what each tool does. These skills teach an agent to use them
well: when to resume, how to keep a decision the next model will keep to, and what to do when CAMR holds a change.

| Skill | Use it when |
| --- | --- |
| [camr](camr/SKILL.md) | any question the person's own material could answer, and the basics of the five tools |
| [camr-carry-on](camr-carry-on/SKILL.md) | carrying on earlier work, after compaction, and before stopping with work unfinished |
| [camr-decisions](camr-decisions/SKILL.md) | the person settles something, a decision overlaps or replaces another, or one is shared with a team |
| [camr-check](camr-check/SKILL.md) | before calling a code change done, and when a CAMR hook or plugin holds a change |
| [camr-setup](camr-setup/SKILL.md) | installing CAMR, opening a vault and connecting programs |
| [camr-local-models](camr-local-models/SKILL.md) | a small local model answering from the vault, preparing a question for another model, reading a whole folder |
| [camr-vaults-and-teams](camr-vaults-and-teams/SKILL.md) | results from another vault or a team, sharing a decision, a share waiting for approval |

[AGENTS.md](AGENTS.md) is all seven on one page, for programs that read an instructions file instead of skills.

One more skill is not in this folder: `camr-resume`, for picking up an archived session, is written by
`camr connect claude-code` into `~/.claude/skills/camr-resume/` (`/camr-resume <name>`) and by
`camr connect codex` into `~/.agents/skills/camr-resume/` (`$camr-resume <name>`). See
[docs/sessions.md](../docs/sessions.md).
[CAMR.md](../CAMR.md) maps every tool, command and page of CAMR in one file, for an agent that needs the whole picture.

## Installing

**Claude Code**, as a plugin from this repository:

```
/plugin install camr --marketplace Satasdin/CAMR
```

On Claude Code before 2.1.275: `/plugin marketplace add Satasdin/CAMR`, then `/plugin install camr@camr`.

Or copy the folders you want into `~/.claude/skills/`.

**Any program that reads skills folders** (each skill is a folder with a `SKILL.md`): copy the folders into that
program's skills folder.

**OpenCode, OpenClaw, Hermes Agent, Cursor, Codex and others**: paste [AGENTS.md](AGENTS.md) into the program's
instructions file.

The skills need CAMR itself to be connected: `camr connect <program> <vault>` (see
[docs/connect.md](../docs/connect.md)).
