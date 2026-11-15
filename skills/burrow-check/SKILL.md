---
name: burrow-check
description: Check a code change against the decisions kept in the person's Burrow Ledger before calling it done, and respond correctly when Burrow holds a change. Use it before saying any change to linked code is finished, when a Burrow hook or plugin blocks your turn or a git commit, and when burrow_check or burrow check returns a verdict of breaks, affected or unprovable.
---

# Checking a change against the decisions

Burrow reads what changed in the linked code since its last git commit and puts every decision resting on those files,
or one import away, beside the diff. A memory alone does not stop a model breaking a decision it has read; this check
does.

## Before you say a change is done

Call `burrow_check`. For each decision it shows, Burrow gives a verdict:

| Verdict | Meaning | What to do |
| --- | --- | --- |
| unaffected | your change left the code the decision rests on as it was | nothing |
| affected | you changed code the decision rests on | read the decision and its reason; confirm your change keeps to it, or undo that part |
| unprovable | Burrow cannot tell (no code named, a file it cannot outline) | treat as affected |
| breaks | the decision's own check failed on your change | undo the part that breaks it, or ask the person |

Then, for every decision that is not unaffected, do one of three things and say which:

1. it still holds with your change, and why;
2. you undid the part that went against it;
3. your change goes against it: tell the person which decision, its reason, and what your change does instead, and
   ask before going on. Never go against a decision silently.

## When Burrow holds you

Claude Code's Stop hook, git's pre-commit hook and the plugins in OpenCode, OpenClaw and Hermes Agent run the same
check without you. If one blocks your turn or a commit with Burrow's decisions, that is the check: answer it as
above. A change is held once until it has been shown; a change that breaks a decision's check is held every time.

- Do not say you reverted something until the file shows it. Read the file back, or call `burrow_check` again.
- Do not try to get the change through some other way (`--no-verify`, editing hook files, a different commit).
- Only the person can override a broken decision, with a code shown in a macOS notification. Never ask them for the
  code, and never type one you see.

## What is not counted

Files only a build makes (`__pycache__`, `.pyc`, `node_modules`, `.DS_Store`, build folders) are named on one line and
not counted as your change.

With no linked code, or no decision on the files you changed, `burrow_check` says so and you are done.
