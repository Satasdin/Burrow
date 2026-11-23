# CAMR's gate for OpenCode

`camr-gate/index.js` is an OpenCode 2.x plugin (a plain object with an `id` and `setup`, no dependencies).

When the model has finished and the session is about to go idle, it runs `camr check <vault> --json`. If the change in
the vault's linked code rests on a decision kept in the Ledger that has not been shown yet, it puts the decisions, their
reasons and one instruction into the session as a message. OpenCode then runs another step, so the model has to answer
it: say which decision the change touches and whether it goes against it, and if it does, put the code back and ask.
If the model then stops again with the held change still in the files, it gets one more message saying so, naming the
files (in the first real runs gemma4:12b twice wrote "I have reverted the change" and had not). Each change is held
once; after three messages in one session it stays quiet.

Install it with:

```
camr connect opencode ~/Notes            # shows what it would write
camr connect opencode ~/Notes --write    # writes it, after you type yes
```

That writes `~/.config/opencode/plugins/camr-gate/index.js` (this file), `camr-gate.json` beside it (the `camr`
binary, the vault, and `CAMR_STATE_DIR` if you use one), and adds CAMR to `~/.config/opencode/opencode.json` with
`"codemode": false`. Without that line OpenCode 2 hides every MCP tool behind its `execute` tool and the model has to
write code to reach CAMR.

By hand: put `index.js` and a `camr-gate.json` like this in any OpenCode config folder's `plugins/camr-gate/`:

```json
{ "camr": "/full/path/to/camr", "vault": "/Users/you/Notes" }
```

The plugin is global: it checks the vault's linked folders whatever folder OpenCode was opened in, as Claude Code's Stop
hook does. Run OpenCode with `--print-logs` to see it load; `CAMR_GATE_LOG=/tmp/gate.jsonl` logs every check.
