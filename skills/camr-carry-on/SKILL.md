---
name: camr-carry-on
description: Pick up work where an earlier session, or another model in another program, stopped, and leave a clean handover for the next one, through the person's CAMR vault. Use it when the person says carry on, continue, pick up where we left off or what was I doing, at the start of any task that may have been worked on before, after your context has been compacted, and before you end a session with work unfinished.
---

# Carrying work on through CAMR

Every model starts a session knowing nothing. CAMR keeps where the work stopped, so the next session, the same
program after compaction, or a different model in a different program, starts from there.

## Starting

1. Read the decisions in force that came with your first CAMR tool result or the server's instructions, before you
   plan. Each has its reason; a decision marked **check again** rests on a file that changed since it was kept.
2. Call `camr_resume`. It gives the plan, where the last session stopped, what it was in the middle of (its open
   request, the exact error it was working on, the constraint it was keeping), corrections, and the latest decisions.
   Pass a `branch` when the work belongs to a linked folder's branch.
3. Continue the step it names, with its constraint. Do not start the task again from the top, and do not redo work the
   resume says is done without checking it.

## After compaction

Your summary of the session loses detail. In Claude Code, CAMR's hooks keep the person's requests, the reasons and
the errors word for word at each compaction and hand them back afterwards. If something you need is missing, call
`camr_recall` (with `--tools full`) with words from it; it returns the exact words, never a paraphrase.

## Ending

Before you stop with work unfinished, keep a handover with `camr_commit`:

- `kind: plan` for the steps left, when the plan changed;
- `kind: handoff` for where you stopped: the step you were on, what is done, the exact error or open question, and any
  constraint the next model must keep.

CAMR writes a short handoff for every connection anyway, but yours says what it cannot see. Keep decisions made
along the way as decisions, with their reasons (see the camr-decisions skill), not inside the handoff.

## Conversations

Each connection is kept as its own conversation, with what it searched for, read and kept. With `--tools full`,
`vault_session_list` and `vault_session_resume` let you pick up a specific conversation another program started.
