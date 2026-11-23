# The engine: answering from your material

When a question is about your own notes, documents or code, CAMR's engine prepares what a model reads. It does not
change the model: any model, local or cloud, gets the same preparation.

## The steps

1. **Decide.** Does the question need the vault at all? A reasoning problem or a general question goes to the model
   without it, because irrelevant text makes reasoning worse. If the vault is needed, the engine chooses how to read
   it: search, or following links when the closest files are code, and a skill whose `when:` line fits the task.
2. **Find.** Pieces of the vault are ranked by their words and by their meaning, and the two rankings are merged. The
   decisions in the Ledger that fit the question are added with their reasons, labelled so the answer can name them.
3. **Fit.** The excerpts are cut to what this model can read in the time it has, measured once per model with
   `camr fit` (for Gemma 4 12B on the evaluation laptop, 17,417 characters). Each excerpt keeps its file and line.
4. **Answer.** The model answers from the excerpts and cites each place it used.
5. **Check.** Every cited place is checked against what the model was shown. With `camr ask --mode engine`, an answer
   that cites a place it was not shown is asked again once with a correction, and the better-grounded answer is kept;
   the app and the chat warn instead.
6. **Learn.** What a conversation decided can be kept, never without you: `/keep` in `camr chat`, **What Should
   CAMR Remember?** in the app, or `camr learn <vault> <transcript.json>` propose notes and ask before writing each.

## Commands

```bash
camr find  ~/Notes "question" [--mode search|walk] [--json]      # what would be read, no model
camr ask   ~/Notes "question" [--mode engine|none|search|walk]     # an answer from a local model
camr brief ~/Notes "question" [--json]                            # the question packed for any other model
camr fit   ~/Notes --model gemma4:12b                              # measure a model once
camr skills ~/Notes [--install]                                   # list the skills, or add the starter set
camr chat  ~/Notes [--model NAME]                                  # a terminal chat with a local model
camr tui   ~/Notes                                                 # the full-screen terminal view
```

`--mode none` asks the model alone, `search` pastes the best excerpts, `walk` follows links, and `engine` runs every
step above. `--no-skills`, `--no-check`, `--no-ledger` and `--characters N` turn parts off, for comparing.

Over MCP, `vault_prepare` gives a program the same preparation for its own model, and `vault_ask` has the local model
answer.

## Skills

A skill is a Markdown file in the vault's `Skills` folder with a `when:` line saying which tasks it fits, and a method
for them. `camr skills ~/Notes --install` adds a starter set; edit them or add your own. These are methods for
CAMR's own engine, separate from the [skill pack for agents](../skills/README.md).

## What it achieved

On 120 questions about material no model had seen (Kenyan data protection law, 2026 software documentation and a
private project's notes), Gemma 4 12B answered 9 alone, 75 with a Chroma vector database, 94 with plain retrieval and
102 with the engine; a cloud model given the same vault answered 109. On 50 reasoning problems the engine left the
vault out of every one. The engine was shown more of the vault than the two baselines, and on the smaller Qwen3.5 4B
plain retrieval did better (97 against 91). The full results are in the project report.
