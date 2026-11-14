# Burrow's gate inside other programs

A small local model can read a decision kept in Burrow and still break it, and it rarely calls `burrow_check` on its
own. The gate is a hook inside the program the person uses, so the model can't skip it: when the model edits code (or
finishes its turn), the hook runs `burrow check <vault> --json`. If the change rests on a decision that has not been
shown yet, the decisions and their reasons go back to the model with one instruction: tell the person which decision
the change touches and whether it goes against it, and if it does, put the code back and ask before overturning it.

Then one follow-up, where the program has an end-of-turn hook (OpenCode, Hermes): if the model stops again with the
held change still in the files, it is told so plainly, once. In the first real runs gemma4:12b twice wrote "I have
reverted the change" and had not.

Each change is held once. `burrow check` records a change as shown when it checks it (a fingerprint of the decisions and
the exact file contents), and each plugin also remembers what it already said, so the gate can't loop. A further edit
to those files is a new change and is held again. A gate that can't run (Burrow missing, a timeout) never blocks.

You don't copy these by hand: `burrow connect <program> <vault> --write` installs the right one with the vault filled in
(see [docs/connect.md](../docs/connect.md)). They are here so you can read exactly what runs.

| Program | Folder | Where it hooks in |
| --- | --- | --- |
| OpenCode 2.x | [opencode/burrow-gate](opencode/burrow-gate) | when the session is about to go idle (`experimental.idle`): the message goes into the session and OpenCode runs another step |
| OpenClaw 2026.11 | [openclaw/burrow-gate](openclaw/burrow-gate) | after a tool that can change files (`edit`, `write`, `apply_patch`, `exec`): the decisions are added to that tool's result |
| Hermes Agent 0.23 | [hermes/burrow-gate](hermes/burrow-gate) | after `write_file`, `patch` or `terminal` (added to the result), and before the final answer of a turn that edited files (`pre_verify`): Hermes runs another step |
| Claude Code | built in: `burrow hook claude <vault> --gate` | the Stop hook (D-93) |
| n8n | none | n8n has no hook that can hold an agent's reply; `burrow connect n8n` says how to add a check step |

Exit codes the plugins read: 0 nothing to hold, 2 a decision rests on this change and it was not shown yet, 3 Burrow's
check says the change breaks a decision (treated like 2, with a sentence saying so). Anything else is ignored.

`BURROW_GATE_LOG=<file>` makes any of the three write one JSON line per check, for testing.
