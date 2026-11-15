# Burrow skills for AI agents

Burrow's MCP server already tells a connected program what each tool does. These skills teach an agent to use them
well: when to resume, how to keep a decision the next model will keep to, and what to do when Burrow holds a change.

| Skill | Use it when |
| --- | --- |
| [burrow](burrow/SKILL.md) | any question the person's own material could answer, and the basics of the five tools |
| [burrow-carry-on](burrow-carry-on/SKILL.md) | carrying on earlier work, after compaction, and before stopping with work unfinished |
| [burrow-decisions](burrow-decisions/SKILL.md) | the person settles something, a decision overlaps or replaces another, or one is shared with a team |
| [burrow-check](burrow-check/SKILL.md) | before calling a code change done, and when a Burrow hook or plugin holds a change |
| [burrow-setup](burrow-setup/SKILL.md) | installing Burrow, opening a vault and connecting programs |

[AGENTS.md](AGENTS.md) is all five on one page, for programs that read an instructions file instead of skills.

## Installing

**Claude Code**, as a plugin from this repository:

```
/plugin install burrow --marketplace Satasdin/Burrow
```

On Claude Code before 2.1.275: `/plugin marketplace add Satasdin/Burrow`, then `/plugin install burrow@burrow`.

Or copy the folders you want into `~/.claude/skills/`.

**Any program that reads skills folders** (each skill is a folder with a `SKILL.md`): copy the folders into that
program's skills folder.

**OpenCode, OpenClaw, Hermes Agent, Cursor, Codex and others**: paste [AGENTS.md](AGENTS.md) into the program's
instructions file.

The skills need Burrow itself to be connected: `burrow connect <program> <vault>` (see
[docs/connect.md](../docs/connect.md)).
