"""Reads each arm's raw transcript, turn log and Burrow meter, and writes the numbers (D-116 evidence).

  python3 analyse.py BASE OUT
Copies the raw files into OUT/raw/<arm><run>/ and writes OUT/results.json and OUT/results.md.
"""
import glob, gzip, json, os, shutil, sys

base, out = sys.argv[1], sys.argv[2]
os.makedirs(f"{out}/raw", exist_ok=True)
rows = []
for work in sorted(glob.glob(f"{base}/[ABC][0-9]*")):
    name = os.path.basename(work)
    quiz_file = f"{work}/quiz.json"
    if not os.path.exists(quiz_file):
        continue
    quiz = json.load(open(quiz_file))
    turns = [json.loads(l) for l in open(f"{work}/turns.jsonl")]
    session = quiz["session"]
    proj_key = "-" + (work + "/proj").replace("/", "-").replace("_", "-").lstrip("-")
    found = glob.glob(os.path.expanduser(f"~/.claude/projects/*{name}-proj/{session}.jsonl"))
    transcript = found[0] if found else None
    contexts, compactions, tool_chars, burrow_short = [], [], 0, 0
    if transcript:
        last = None
        for line in open(transcript):
            d = json.loads(line)
            if d.get("type") == "system" and d.get("subtype") == "compact_boundary":
                meta = d.get("compactMetadata", {})
                compactions.append({"trigger": meta.get("trigger"), "pre": meta.get("preTokens"), "post": meta.get("postTokens"), "after_request": len(contexts)})
            m = d.get("message") or {}
            if d.get("type") == "assistant" and isinstance(m.get("usage"), dict):
                u = m["usage"]
                c = u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
                key = (c, u.get("output_tokens"))
                if c and key != last:
                    contexts.append(c)
                last = key
            if isinstance(m.get("content"), list):
                for p in m["content"]:
                    if p.get("type") == "tool_result":
                        text = p.get("content") if isinstance(p.get("content"), str) else json.dumps(p.get("content"))
                        tool_chars += len(text)
                        if "[Burrow kept this whole output" in text:
                            burrow_short += 1
        with open(transcript, "rb") as src, gzip.open(f"{out}/raw/{name}.transcript.jsonl.gz", "wb") as dst:
            shutil.copyfileobj(src, dst)
    shutil.copy(f"{work}/turns.jsonl", f"{out}/raw/{name}.turns.jsonl")
    shutil.copy(quiz_file, f"{out}/raw/{name}.quiz.json")
    meter = []
    for f in glob.glob(f"{work}/state/meter/*.jsonl"):
        meter += [json.loads(l) for l in open(f)]
        shutil.copy(f, f"{out}/raw/{name}.meter.{os.path.basename(f)}")
    usage = {"input": 0, "cache_read": 0, "cache_write": 0, "output": 0}
    cost = 0.0
    for t in turns:
        u = t.get("usage") or {}
        usage["input"] += u.get("input_tokens", 0)
        usage["cache_read"] += u.get("cache_read_input_tokens", 0)
        usage["cache_write"] += u.get("cache_creation_input_tokens", 0)
        usage["output"] += u.get("output_tokens", 0)
        cost += t.get("cost") or 0
    kept = [e for e in meter if e["kind"] in ("kept", "shortened")]
    rows.append({
        "arm": name[0], "run": name[1:], "session": session,
        "requests": len(contexts), "compactions": len(compactions), "compaction_detail": compactions,
        "context_peak": max(contexts) if contexts else 0, "context_final": contexts[-1] if contexts else 0,
        "context_series": contexts, "tool_result_characters_in_transcript": tool_chars,
        "billed_tokens": usage, "billed_total": sum(usage.values()), "cost_usd": round(cost, 4),
        "seconds": round(sum(t.get("seconds", 0) for t in turns), 1), "errors": sum(1 for t in turns if t.get("is_error")),
        "quiz_score": quiz["score"], "quiz_total": len(quiz["quiz"]), "quiz": [{"ask": q["ask"], "right": q["right"], "answer": (q["answer"] or "")[:400]} for q in quiz["quiz"]],
        "burrow_kept_or_shortened": len(kept), "burrow_characters_kept_out": sum(max(0, e["original"] - e["shown"]) for e in kept),
        "burrow_recalls": sum(1 for e in meter if e["kind"] == "recalled"), "burrow_recalled_characters": sum(e["shown"] for e in meter if e["kind"] == "recalled"),
        "burrow_expanded": sum(1 for e in meter if e["kind"] == "expanded"), "burrow_steered": sum(1 for e in meter if e["kind"] == "steered"),
    })
json.dump(rows, open(f"{out}/results.json", "w"), indent=1)
lines = ["| Arm | Run | Requests | Compactions | Peak context | Final context | Tool output seen (chars) | Billed tokens | Cost $ | Quiz | Kept by Burrow (chars) | Recalls |",
         "|---|---|---|---|---|---|---|---|---|---|---|---|"]
for r in rows:
    lines.append(f"| {r['arm']} | {r['run']} | {r['requests']} | {r['compactions']} | {r['context_peak']:,} | {r['context_final']:,} | {r['tool_result_characters_in_transcript']:,} | {r['billed_total']:,} | {r['cost_usd']} | {r['quiz_score']}/{r['quiz_total']} | {r['burrow_characters_kept_out']:,} | {r['burrow_recalls']} |")
open(f"{out}/results.md", "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
