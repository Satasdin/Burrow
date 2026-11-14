"""Burrow's gate for Hermes Agent (D-108).

When the model has edited files with write_file or patch and is about to give its final answer, Hermes calls the
``pre_verify`` hook. This runs ``burrow check <vault> --json``; if the change in the linked code rests on a decision
kept in Burrow's Ledger that has not been shown yet (exit 2), or Burrow says the change breaks one (exit 3), the
decisions and their reasons go back to the model as a message it must answer, and Hermes runs the loop again.

``pre_verify`` only runs once the model gives a final answer, and a small model can wander for many steps after an edit
(in the first D-108 run it never answered within ten minutes), and edits made through the shell never reach it. So
after each edit (``write_file``, ``patch``) and each shell command the same check runs too, and a held change is added
to that tool's result at once; the end-of-turn hook then asks once more for the answer.

One follow-up, once per change: if the model is about to finish with the held change still in the files (in the D-108
runs gemma4:12b twice wrote "I have reverted the change" and had not), it is told so, plainly, once.

Each change is held once: Burrow records a change as shown when it checks it, and this plugin remembers what it said per
session. Settings (burrow, vault, stateDir) come from config.json beside this file, which
``burrow connect hermes <vault> --write`` writes. A gate that cannot run never blocks. Standard library only.
"""
import datetime
import json
import os
import subprocess

NOTE = ("Burrow held your reply: this change rests on a decision kept in the Ledger, and it had not been checked against it. "
        "Before you finish, tell the person which decision this change touches and whether it goes against it, in plain words. "
        "If it goes against a decision, put the code back as it was and ask the person whether they want to overturn that decision first.")
BROKEN = "Burrow's check says this change breaks a decision kept in the Ledger."
CHANGING_TOOLS = {"write_file", "patch", "terminal", "shell", "bash"}
MOST_PER_SESSION = 3

_said = {}      # session id -> fingerprints already put to the model at the end of a turn
_pending = {}   # session id -> {fingerprint: message} shown in a tool result, still to be asked about at the end


def _settings():
    try:
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json"), encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return {}


def _log(entry):
    path = os.environ.get("BURROW_GATE_LOG") or _settings().get("log")
    if not path:
        return
    try:
        entry = dict(program="hermes", at=datetime.datetime.now(datetime.timezone.utc).isoformat(), **entry)
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry) + "\n")
    except Exception:
        pass


def _check():
    """(exit code, report) from burrow check, or None when it could not run."""
    config = _settings()
    if not config.get("vault"):
        return None
    env = dict(os.environ)
    if config.get("stateDir"):
        env["BURROW_STATE_DIR"] = config["stateDir"]
    try:
        done = subprocess.run([config.get("burrow") or "burrow", "check", config["vault"], "--json"],
                              capture_output=True, text=True, timeout=25, env=env)
        return done.returncode, json.loads(done.stdout)
    except Exception:
        return None


def _held_message(result):
    if not result:
        return None, None
    code, report = result
    exit_code = report.get("exit") if isinstance(report.get("exit"), int) else code
    if code not in (2, 3) and exit_code not in (2, 3):
        return None, report.get("fingerprint")
    broken = 3 in (code, exit_code)
    text = (BROKEN + "\n\n" if broken else "") + (report.get("text") or "") + "\n\n" + NOTE
    return text, report.get("fingerprint") or report.get("text")


def _still_there(report):
    files = ", ".join(report.get("resting") or []) or "the files it named"
    return ("Burrow checked again: the change it held is still in " + files + ", exactly as it was. "
            "If you told the person you put the code back, you have not yet: put it back now, then say so. "
            "If you are keeping the change, tell the person plainly that it is still there and which decision it goes against.")


def _pre_verify(session_id="", attempt=0, changed_paths=(), **_):
    said = _said.setdefault(session_id, [])
    if len(said) >= MOST_PER_SESSION:
        return None
    result = _check()
    message, key = _held_message(result)
    if not message and key and key in said and "still:" + str(key) not in said:
        said.append("still:" + str(key))
        _log({"event": "still", "session": session_id})
        return {"decision": "block", "reason": _still_there(result[1])}
    pending = _pending.setdefault(session_id, {})
    if not message and key in pending:
        # Shown in an edit's or a shell command's result during this turn, not yet answered as the turn ends.
        message = pending[key]
    _log({"event": "pre_verify", "session": session_id, "attempt": attempt, "changed": list(changed_paths), "held": bool(message)})
    if not message or key in said:
        return None
    said.append(key)
    pending.pop(key, None)
    _log({"event": "held", "session": session_id, "fingerprint": key if len(str(key)) < 80 else None})
    return {"decision": "block", "reason": message}


def _transform_tool_result(tool_name="", result=None, session_id="", **_):
    if tool_name not in CHANGING_TOOLS or not isinstance(result, str):
        return None
    message, key = _held_message(_check())
    _log({"event": "after_tool", "session": session_id, "tool": tool_name, "held": bool(message)})
    if not message:
        return None
    _pending.setdefault(session_id, {})[key] = message
    return result + "\n\n" + message


def register(ctx):
    ctx.register_hook("pre_verify", _pre_verify)
    ctx.register_hook("transform_tool_result", _transform_tool_result)
