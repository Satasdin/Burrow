import json, urllib.request, time
big = "\n".join(f"Note {i}: the ferry to island {i} leaves at {i%24}:{i%60:02d} from pier {i%7}." for i in range(180))
def ask(q, ctx=8192, sys_="You answer from the notes."):
    body = {"model":"qwen3:4b-instruct-2507-q4_K_M","stream":False,"keep_alive":"30m",
            "messages":[{"role":"system","content":sys_},{"role":"user","content":big+"\n\nQuestion: "+q}],
            "options":{"temperature":0,"num_ctx":ctx,"num_predict":20}}
    t=time.time(); r=json.load(urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:11434/api/chat",json.dumps(body).encode(),{"Content-Type":"application/json"})))
    print(q[:30], "cached",r.get("prompt_eval_cached_count"), "ctx",ctx,"prompt_eval_count",r.get("prompt_eval_count"),"prompt_s %.2f"%(r.get("prompt_eval_duration",0)/1e9),"load_s %.2f"%(r.get("load_duration",0)/1e9),"wall %.2f"%(time.time()-t))
ask("When does the ferry to island 5 leave?")
ask("When does the ferry to island 5 leave?")
ask("Which pier for island 9?")
ask("Which pier for island 9?", ctx=16384)
ask("Which pier for island 12?", ctx=16384)
