# Burrow's gate for OpenCode

`burrow-gate/index.js` is an OpenCode 2.x plugin (a plain object with an `id` and `setup`, no dependencies).

When the model has finished and the session is about to go idle, it runs `burrow check <vault> --json`. If the change in
the vault's linked code rests on a decision kept in the Ledger that has not been shown yet, it puts the decisions, their
reasons and one instruction into the session as a message. OpenCode then runs another step, so the model has to answer
it: say which decision the change touches and whether it goes against it, and if it does, put the code back and ask.
Each change is held once; after three holds in one session it stays quiet.

Install it with:

```
burrow connect opencode ~/Notes            # shows what it would write
burrow connect opencode ~/Notes --write    # writes it, after you type yes
```

That writes `~/.config/opencode/plugins/burrow-gate/index.js` (this file), `burrow-gate.json` beside it (the `burrow`
binary, the vault, and `BURROW_STATE_DIR` if you use one), and adds Burrow to `~/.config/opencode/opencode.json` with
`"codemode": false`. Without that line OpenCode 2 hides every MCP tool behind its `execute` tool and the model has to
write code to reach Burrow.

By hand: put `index.js` and a `burrow-gate.json` like this in any OpenCode config folder's `plugins/burrow-gate/`:

```json
{ "burrow": "/full/path/to/burrow", "vault": "/Users/you/Notes" }
```

The plugin is global: it checks the vault's linked folders whatever folder OpenCode was opened in, as Claude Code's Stop
hook does. Run OpenCode with `--print-logs` to see it load; `BURROW_GATE_LOG=/tmp/gate.jsonl` logs every check.
