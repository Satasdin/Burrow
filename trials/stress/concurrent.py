"""Workflow 4a: many programs on one vault at once, no model.

N `burrow mcp` processes, as N coding tools would start them, each keeps K commits and runs K searches, all at the
same time, while `burrow index` re-indexes the vault twice. Afterwards every commit must be in the Ledger exactly once,
readable, with its own id, and no call may have failed.

Usage: python3 concurrent.py <vault> [N] [K]
"""
import json, os, re, subprocess, sys, threading, time

vault = sys.argv[1]
N = int(sys.argv[2]) if len(sys.argv) > 2 else 8
K = int(sys.argv[3]) if len(sys.argv) > 3 else 25
burrow = os.path.expanduser("~/.local/bin/burrow")
errors, latencies, lock = [], {"commit": [], "find": []}, threading.Lock()
queries = ["statement line suspense", "reconcile unknown reference", "breach notification 72 hours", "ticket fare route 46"]


def client(n):
    p = subprocess.Popen([burrow, "mcp", vault], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    def call(i, method, params):
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": i, "method": method, "params": params}) + "\n"); p.stdin.flush()
        return json.loads(p.stdout.readline())
    call(0, "initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": f"stress-{n}", "version": "1"}})
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
    for k in range(K):
        for kind, args in (("commit", {"kind": "fact", "message": f"stress process {n} commit {k}", "files": "matatu/matatu/payments/reconcile.py"}),
                           ("find", {"query": queries[(n + k) % len(queries)]})):
            started = time.time()
            reply = call(1 + 2 * k + (kind == "find"), "tools/call", {"name": f"burrow_{kind}", "arguments": args})
            with lock:
                latencies[kind].append(time.time() - started)
                result = reply.get("result", {})
                if "error" in reply or result.get("isError"):
                    errors.append((n, k, kind, json.dumps(reply)[:300]))
    p.stdin.close(); p.wait(30)


before = set(os.listdir(os.path.join(vault, ".burrow/ledger/main")))
started = time.time()
threads = [threading.Thread(target=client, args=(n,)) for n in range(N)]
for t in threads: t.start()
indexer = subprocess.run([burrow, "index", vault, "--vault"], capture_output=True, text=True)
indexer2 = subprocess.run([burrow, "index", vault, "--vault"], capture_output=True, text=True)
for t in threads: t.join()
took = time.time() - started

made = sorted(set(os.listdir(os.path.join(vault, ".burrow/ledger/main"))) - before)
texts = [open(os.path.join(vault, ".burrow/ledger/main", f)).read() for f in made]
facts = [t for t in texts if 'kind: "fact"' in t]
handoffs = [t for t in texts if 'kind: "handoff"' in t]
messages = [m for t in facts for m in re.findall(r"stress process \d+ commit \d+", t)]
want = {f"stress process {n} commit {k}" for n in range(N) for k in range(K)}
ids = [re.search(r'^id: "(.*)"', t, re.M).group(1) for t in texts]
log = subprocess.run([burrow, "log", vault, "--limit", "1000"], capture_output=True, text=True).stdout
pct = lambda xs, q: sorted(xs)[int(q * (len(xs) - 1))] if xs else 0

report = {
    "processes": N, "commits_each": K, "seconds": round(took, 1),
    "commits_wanted": len(want), "commit_files_written": len(facts), "missing": sorted(want - set(messages))[:10],
    "missing_count": len(want - set(messages)), "duplicates": len(messages) - len(set(messages)),
    "ids_unique": len(ids) == len(set(ids)), "handoffs": len(handoffs),
    "unreadable_in_log": sum(1 for m in want if m not in log),
    "errors": len(errors), "first_errors": errors[:5],
    "index_runs_ok": [indexer.returncode == 0, indexer2.returncode == 0], "index_stderr": (indexer.stderr + indexer2.stderr)[-400:],
    "commit_seconds_p50_p95": [round(pct(latencies["commit"], .5), 3), round(pct(latencies["commit"], .95), 3)],
    "find_seconds_p50_p95": [round(pct(latencies["find"], .5), 3), round(pct(latencies["find"], .95), 3)],
}
print(json.dumps(report, indent=1))
