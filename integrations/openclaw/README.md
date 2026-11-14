# Burrow's gate for OpenClaw

`burrow-gate/` is an OpenClaw plugin: `package.json`, the manifest `openclaw.plugin.json`, and `index.mjs` (no
dependencies). It registers a tool-result middleware: after a tool that can change files runs (`edit`, `write`,
`apply_patch`, `exec`), it runs `burrow check <vault> --json`, and if the change in the vault's linked code rests on a
decision kept in the Ledger that has not been shown yet, the decisions, their reasons and one instruction are added to
that tool's result. The model reads them before its next step: say which decision the change touches and whether it
goes against it, and if it does, put the code back and ask. Each change is held once, at most three times a run.

Why after the edit and not at the end of the turn: OpenClaw has an end-of-turn hook (`before_agent_finalize`) that can
ask for a revision, but OpenClaw drops that request once any tool with side effects has run in the turn, which every
edit is.

Install it with:

```
burrow connect openclaw ~/Notes            # shows what it would write
burrow connect openclaw ~/Notes --write    # writes it, after you type yes
```

That copies the plugin to `~/.openclaw/burrow-gate/` and changes `~/.openclaw/openclaw.json`:

```json
{
  "mcp": { "servers": { "burrow": { "command": "/full/path/to/burrow", "args": ["mcp", "/Users/you/Notes"] } } },
  "tools": { "toolSearch": false },
  "plugins": {
    "load": { "paths": ["/Users/you/.openclaw/burrow-gate"] },
    "entries": { "burrow-gate": { "enabled": true, "config": { "burrow": "/full/path/to/burrow", "vault": "/Users/you/Notes" } } }
  }
}
```

`tools.toolSearch: false` turns OpenClaw's tool search off for every tool: OpenClaw has no setting to keep one server's
tools in view, and with it on gemma4:12b found Burrow 0 times in 3. `"enabled": true` is needed: OpenClaw only lets an
explicitly enabled plugin register a tool-result middleware.
