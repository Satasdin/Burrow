#!/bin/zsh
# Local resume proof (D-117, D-118): Qwen3 4B through llama.cpp, loading the model file Ollama already has, resumes the
# archived Sonnet session from arm C run 1. Twice, each time with a freshly started server (nothing in memory).
M=$(python3 -c "import json,os;d=json.load(open(os.path.expanduser('~/.ollama/models/manifests/registry.ollama.ai/library/qwen3/4b-instruct-2507-q4_K_M')));print([os.path.expanduser('~/.ollama/models/blobs/'+l['digest'].replace(':','-')) for l in d['layers'] if l['mediaType'].endswith('model')][0])")
KV=/private/tmp/claude-501/-Users-p3wrky-Developer-burrow--claude-worktrees-session-memory-324f48/1f1bd66f-4ea0-4d18-a04f-8e841082c516/scratchpad/proof/C1/proj/.burrow/kv; mkdir -p $KV
for attempt in 1 2; do
  llama-server -m $M -c 16384 --port 8092 -np 1 --slot-save-path $KV -fa on -ctk q8_0 -ctv q8_0 --jinja > /private/tmp/claude-501/-Users-p3wrky-Developer-burrow--claude-worktrees-session-memory-324f48/1f1bd66f-4ea0-4d18-a04f-8e841082c516/scratchpad/proof/local/server-$attempt.log 2>&1 &
  SERVER=$!
  until curl -s localhost:8092/health | grep -q ok; do sleep 1; done
  START=$(python3 -c "import time;print(time.time())")
  printf 'What is the deploy port, and who is the customer?\nWhich shard failed and what were the checksums?\nWhich database did we choose and why?\n' |     BURROW_STATE_DIR=/private/tmp/claude-501/-Users-p3wrky-Developer-burrow--claude-worktrees-session-memory-324f48/1f1bd66f-4ea0-4d18-a04f-8e841082c516/scratchpad/proof/C1/state /private/tmp/claude-501/-Users-p3wrky-Developer-burrow--claude-worktrees-session-memory-324f48/1f1bd66f-4ea0-4d18-a04f-8e841082c516/scratchpad/proof/bin/burrow-new chat /private/tmp/claude-501/-Users-p3wrky-Developer-burrow--claude-worktrees-session-memory-324f48/1f1bd66f-4ea0-4d18-a04f-8e841082c516/scratchpad/proof/C1/proj --resume 3a9523af --llama http://127.0.0.1:8092 --tools-only > /private/tmp/claude-501/-Users-p3wrky-Developer-burrow--claude-worktrees-session-memory-324f48/1f1bd66f-4ea0-4d18-a04f-8e841082c516/scratchpad/proof/local/chat-$attempt.txt 2> /private/tmp/claude-501/-Users-p3wrky-Developer-burrow--claude-worktrees-session-memory-324f48/1f1bd66f-4ea0-4d18-a04f-8e841082c516/scratchpad/proof/local/chat-$attempt.err
  python3 -c "import time;print('attempt $attempt wall', round(time.time()-$START,2),'s')" >> /private/tmp/claude-501/-Users-p3wrky-Developer-burrow--claude-worktrees-session-memory-324f48/1f1bd66f-4ea0-4d18-a04f-8e841082c516/scratchpad/proof/local/timing.txt
  kill $SERVER; wait $SERVER 2>/dev/null
done
ls -la $KV >> /private/tmp/claude-501/-Users-p3wrky-Developer-burrow--claude-worktrees-session-memory-324f48/1f1bd66f-4ea0-4d18-a04f-8e841082c516/scratchpad/proof/local/timing.txt
