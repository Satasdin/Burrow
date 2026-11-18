import json, urllib.request, time
U="http://127.0.0.1:8091"
def call(path, body):
    return json.load(urllib.request.urlopen(urllib.request.Request(U+path, json.dumps(body).encode(), {"Content-Type":"application/json"})))
notes = "\n".join(f"Note {i}: the ferry to island {i} leaves at {i%24}:{i%60:02d} from pier {i%7}." for i in range(330))
msgs=[{"role":"system","content":"Answer from the notes.\n"+notes}]
def turn(q):
    msgs.append({"role":"user","content":q})
    t=time.time(); r=call("/v1/chat/completions",{"messages":msgs,"max_tokens":24,"temperature":0,"id_slot":0,"cache_prompt":True})
    a=r["choices"][0]["message"]["content"]; msgs.append({"role":"assistant","content":a})
    tm=r.get("timings",{}); print(f"{q[:28]:28} prompt_n={tm.get('prompt_n')} cached={tm.get('cache_n')} prompt_ms={tm.get('prompt_ms',0):.0f} wall={time.time()-t:.2f}s")
turn("When does the ferry to island 5 leave?")
turn("And from which pier?")
t=time.time(); r=call("/slots/0?action=save",{"filename":"chat-session.bin"}); print("save", r.get("n_saved"), "tokens", f"{time.time()-t:.2f}s")
call("/slots/0?action=erase",{})
print("-- model now holds nothing (as after a restart) --")
cold=list(msgs)
turn("When does the ferry to island 40 leave?")   # cold: whole history read again
msgs[:]=cold
call("/slots/0?action=erase",{})
t=time.time(); r=call("/slots/0?action=restore",{"filename":"chat-session.bin"}); print("restore", r.get("n_restored"), "tokens", f"{time.time()-t:.2f}s")
turn("When does the ferry to island 40 leave?")   # warm: only the new message read
