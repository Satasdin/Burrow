"""Runs one arm of the session-context proof with real Claude Code, headless, one `claude -p --resume` per message.

  python3 run_arm.py ARM RUN BASE BURROW_NEW BURROW_OLD SCRIPT_DIR
ARM: A = Claude Code alone, B = Burrow 1.2.3 as shipped (folds, Ledger hooks), C = Burrow with D-116/D-117.
Everything lives under BASE/<ARM><RUN>: the project, Burrow's state, the settings. The person's own Claude Code settings,
hooks and MCP servers are switched off (--setting-sources project,local --strict-mcp-config).
"""
import json, os, shutil, subprocess, sys, time

arm, run, base, new_burrow, old_burrow, here = sys.argv[1:7]
quiz_only = len(sys.argv) > 7 and sys.argv[7] == "quiz"
script_name = sys.argv[8] if len(sys.argv) > 8 else "script.json"
work = os.path.join(base, f"{arm}{run}")
proj, state = os.path.join(work, "proj"), os.path.join(work, "state")
if not quiz_only:
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(state)
if not quiz_only:
    subprocess.run([sys.executable, os.path.join(here, "make_project.py"), proj], check=True, capture_output=True)
script = json.load(open(os.path.join(here, script_name)))
burrow = {"A": None, "B": old_burrow, "C": new_burrow}[arm]
env = dict(os.environ)
for key in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID"]:
    env.pop(key, None)
env["BURROW_STATE_DIR"] = state
# Claude Code's documented floor for its window, so compaction happens within a 30-message session.
env["CLAUDE_CODE_AUTO_COMPACT_WINDOW"] = "100000"

settings = {"permissions": {"allow": ["Bash", "Read", "Grep", "Glob", "Edit", "Write", "mcp__burrow"]}, "env": {"BURROW_STATE_DIR": state}}
mcp = {"mcpServers": {}}
if burrow and not quiz_only:
    subprocess.run([burrow, "index", proj, "--no-embed", "--vault"], env=env, capture_output=True)
    out = subprocess.run([burrow, "hook", "install", "claude", proj], env=env, capture_output=True, text=True).stdout
    settings["hooks"] = json.loads(out[out.index("{"):])["hooks"]
    mcp["mcpServers"]["burrow"] = {"type": "stdio", "command": burrow, "args": ["mcp", proj], "env": {"BURROW_STATE_DIR": state}}
if not quiz_only:
    json.dump(settings, open(os.path.join(work, "settings.json"), "w"), indent=1)
    json.dump(mcp, open(os.path.join(work, "mcp.json"), "w"), indent=1)

base_args = ["claude", "-p", "--model", "sonnet", "--setting-sources", "project,local", "--settings", os.path.join(work, "settings.json"),
             "--strict-mcp-config", "--mcp-config", os.path.join(work, "mcp.json"), "--output-format", "json", "--max-turns", "25"]
session = None
if quiz_only:
    # Ask the quiz again on the session the turns made: drop the old quiz lines, keep the work.
    kept = [json.loads(l) for l in open(os.path.join(work, "turns.jsonl")) if not json.loads(l).get("quiz")]
    session = next((t["session"] for t in reversed(kept) if t.get("session")), None)
    log = open(os.path.join(work, "turns.jsonl"), "w")
    for t in kept:
        log.write(json.dumps(t) + "\n")
else:
    log = open(os.path.join(work, "turns.jsonl"), "w")

def turn(message, quiz=False):
    global session
    args = list(base_args)
    if session:
        args += ["--resume", session]
    if quiz:
        # One token: --disallowedTools takes several values, and a separate prompt after it was read as a tool name
        # (the first run's quiz sent no prompt at all).
        args += ["--disallowedTools=Bash,Read,Grep,Glob,Edit,Write"]
    started = time.time()
    done = subprocess.run(args + [message], cwd=proj, env=env, capture_output=True, text=True, timeout=1800)
    try:
        result = json.loads(done.stdout)
    except Exception:
        result = {"is_error": True, "raw": done.stdout[-2000:], "stderr": done.stderr[-2000:]}
    session = result.get("session_id", session)
    record = {"message": message, "quiz": quiz, "seconds": round(time.time() - started, 1), "result": result.get("result"),
              "is_error": result.get("is_error"), "usage": result.get("usage"), "cost": result.get("total_cost_usd"),
              "num_turns": result.get("num_turns"), "session": session}
    log.write(json.dumps(record) + "\n"); log.flush()
    print(f"[{arm}{run}] {'quiz' if quiz else 'turn'} {message[:60]!r} -> {record['seconds']}s cost {record['cost']}", flush=True)
    return record

for message in ([] if quiz_only else script["turns"]):
    turn(message)
answers = []
for item in script["quiz"]:
    record = turn(item["ask"], quiz=True)
    text = (record.get("result") or "").lower()
    right = any(all(s.lower() in text for s in group) for group in item["any"])
    answers.append({"ask": item["ask"], "answer": record.get("result"), "right": right})
json.dump({"arm": arm, "run": run, "session": session, "quiz": answers, "score": sum(a["right"] for a in answers)},
          open(os.path.join(work, "quiz.json"), "w"), indent=1)
print(f"[{arm}{run}] done: quiz {sum(a['right'] for a in answers)}/{len(answers)}", flush=True)
