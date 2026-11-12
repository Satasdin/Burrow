#!/bin/bash
# Clip 08: sets up the Matatu project and records the two sessions as two tapes, joined afterwards.
# Each session is its own recording, so a long run that fails costs one session. Gemma runs live: 10 to 20 minutes.
# Usage: tapes/08-coding-session.sh <vault> <code-folder> <output.mp4>
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
"$HERE/08-coding-setup.sh" "$1" "$2"
VAULT=$(cd "$1" && pwd); CODE=$(cd "$2" && pwd); OUT=$3
for part in a b; do
  sed -e "s|{CODE}|$CODE|g" -e "s|{VAULT}|$VAULT|g" -e "s|{OUT}|${OUT%.mp4}-$part.mp4|" "$HERE/08$part-coding-session.tape" > "$CODE/08$part.tape"
  vhs "$CODE/08$part.tape"
done
printf "file '%s'\nfile '%s'\n" "${OUT%.mp4}-a.mp4" "${OUT%.mp4}-b.mp4" > "$CODE/parts.txt"
ffmpeg -loglevel error -y -f concat -safe 0 -i "$CODE/parts.txt" -c copy "$OUT"
