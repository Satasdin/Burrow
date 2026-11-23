# CAMR's gate for Hermes Agent

`camr-gate/` is a Hermes plugin: `plugin.yaml` and `__init__.py` (standard library only).

- **After an edit or a shell command (`transform_tool_result`).** After `write_file`, `patch` or `terminal`, it runs
  `camr check <vault> --json`. If the change in the vault's linked code rests on a decision kept in the Ledger that
  has not been shown yet, the decisions, their reasons and one instruction are added to that tool's result: say which
  decision the change touches and whether it goes against it, and if it does, put the code back and ask.
- **End of the turn (`pre_verify`).** When the model has edited files with `write_file` or `patch` and is about to give
  its final answer, Hermes calls this hook. A change still not shown, or shown in a tool result during this turn, goes
  back as `{"decision": "block", "reason": …}` and Hermes runs another step, so the model has to answer it.

Why both: `pre_verify` only runs once the model gives a final answer, and in the first real run gemma4:12b edited,
rewrote the file twice and never answered within ten minutes; a shell edit never reaches it at all.

If the model is about to finish again with the held change still in the files, it gets one more message saying so,
naming the files. Each change is held once; at most three messages a session.

Install it with:

```
camr connect hermes ~/Notes            # shows what it would write
camr connect hermes ~/Notes --write    # writes it, after you type yes
```

That copies the plugin to `~/.hermes/plugins/camr-gate/` with a `config.json` (the `camr` binary, the vault, and
`CAMR_STATE_DIR` if you use one), and adds these lines to `~/.hermes/config.yaml`, leaving every other line as it is:

```yaml
mcp_servers:
  camr:
    command: "/full/path/to/camr"
    args: ["mcp", "/Users/you/Notes"]
tools:
  tool_search:
    enabled: "off"
plugins:
  enabled:
    - camr-gate
```

Hermes only loads a plugin listed in `plugins.enabled`. `tool_search: off` turns Hermes' tool search off for every tool:
Hermes has no setting to keep one server's tools in view, and with it on gemma4:12b answered through CAMR 2 times in 6.
If `config.yaml` already sets one of these to something else, `camr connect` changes nothing and says what to set.
