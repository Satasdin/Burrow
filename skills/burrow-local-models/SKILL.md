---
name: burrow-local-models
description: Get good answers from a small local model (Ollama, llama.cpp, LM Studio) using the person's Burrow vault, and read large folders without overflowing a model's context. Use it when you are a local model connected to Burrow, when the person wants Burrow's own model to answer (burrow ask, vault_ask), when a task needs a whole codebase or document set read end to end (vault_pack), when they want a question prepared for another model (vault_prepare, burrow brief), or when they ask how much a model should be shown (burrow fit).
---

# Local models and Burrow

A small model on a Mac can't know the person's material and can't read much at once. Burrow's engine closes most of
that gap: on 120 questions about material no model had seen, Gemma 4 12B answered 9 alone and 102 with the engine,
against 109 for a cloud model with the same vault. It works by giving the model less, better chosen, not more.

## If you are the local model

1. **Prepare before answering.** With `--tools full`, call `vault_prepare` with the task in the person's words. It says
   whether the vault is needed at all, gives the excerpts worth reading, cut to fit, and a method for this kind of task
   when the vault has one. If it says the vault isn't needed (a sum, a reasoning problem, a general question), answer
   without it: irrelevant text makes a small model reason worse.
2. **Otherwise search narrowly.** `burrow_find` with the person's own words and names. Read the trust line first; if
   it says the vault doesn't hold this, say so rather than guess.
3. **Read little.** `burrow_read` with `start_line` and `line_count` around the excerpt, not the whole file.
4. **Cite every fact** as `file:line`, and only places you were shown. An answer that cites a place it was not shown
   is the commonest failure; Burrow's check catches it.

## Having Burrow's own model answer

- From another program: `vault_ask` with the `question`, an optional `folder`, and `model` (an installed Ollama
  model). It returns the answer and the files read. It runs on the Mac and can take tens of seconds.
- In a terminal: `burrow ask <vault> "question"`. `--mode engine` decides, finds, fits,
  answers and checks the citations, asking again once if the answer cites a place it was not shown. `--mode none`,
  `search` and `walk` are there for comparing.
- `burrow chat <vault>` is a terminal conversation; `/keep` proposes notes from it, asking before writing each.

## Preparing for another model

`burrow brief <vault> "question" [--json]` packs the question with the excerpts and method for any other model, local
or cloud, to answer from. `vault_prepare` is the same over MCP.

## How much a model is shown

`burrow fit <vault> --model NAME` measures a model once and sets how much it is shown (Gemma 4 12B on the evaluation
laptop: 17,417 characters). Run it after installing a new model. `--characters N` on `ask` and `brief` overrides it
for one question.

## Reading a whole folder

When a task needs a codebase or document set end to end, don't search piece by piece:

- `vault_pack` with `folder` (from `vault_folders` or `vault_list`) and `part`, starting at 1. Each part fits the
  context: a map of the folder and its main notes first, then every file with line numbers. The text says how many
  parts there are. Keep notes between parts; the same folder always gives the same text.
- In a terminal: `burrow kv <vault> pack <folder> --part N`.

## llama.cpp: keeping what the model read

With `llama-server ... -np 2 --slot-save-path <vault>/.burrow/kv` and `burrow mcp <vault> --llama http://127.0.0.1:8080`,
Burrow reads folders that keep coming up into the model's cache in the spare slot and saves it, so a conversation that
opens with that pack starts in seconds instead of re-reading it (5.3 s against 37.7 s for a 24,240-token pack in the
trial). `burrow kv <vault> warm <folder>` does it ahead of time, `burrow kv <vault> list` shows the shelf. Nothing
changes for the model: if the server is down or has one slot, lookups work as before. Guide: `docs/kv.md`.

## What a local model still gets wrong

A small model can read a decision and still break it (2 of 4 runs in the evaluation). Before calling a code change
done, call `burrow_check` and answer every verdict (see the burrow-check skill).
