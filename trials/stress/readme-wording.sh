#!/bin/bash
# D-80 reworded: the "read README through Burrow" arm of readme-proof.sh again, 6 runs, with the new notice.
set -e
. "$(dirname "$0")/lib.sh"
rm -f "$HOME/.local/bin/burrow"; cp "$HOME/Developer/burrow/.build/release/burrow" "$HOME/.local/bin/burrow"
READ="Do the task in task-04.md. Before you start, read the repository's README through Burrow: burrow_read matatu/README.md."
TAG=-read-v2 PROMPT="$READ" "$HERE/w23.sh" claude 6 readme
echo "wording rerun done"
