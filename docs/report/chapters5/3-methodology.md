# Chapter 3:  Methodology

## 3.1 Introduction

This chapter describes how the study was carried out. It states the research paradigm that guided the work, the development approach that was followed, the analysis of what the system had to do, the design of both the system and the experiments that evaluated it, the tools and techniques that were used, and the deliverables the study produced. The system was analysed and designed with Object-Oriented Analysis and Design (OOAD). Throughout the chapter, the guiding principle is that every claim about Burrow was tested as a controlled experiment with real models. The design itself is presented in Chapter 4 and the results in Chapter 5.

## 3.2 Research Paradigm

The study adopted a pragmatist research philosophy, combining design science research with controlled experimentation. Design science research was appropriate because the study created and evaluated a new artefact, the Burrow vault, and the discipline's guidelines require that such an artefact be evaluated rigorously against explicit measures of utility (Hevner et al., 2004). The study followed the design science research methodology of Peffers et al. (2007), proceeding through problem identification, definition of solution objectives, design and development, demonstration, evaluation and communication. The evaluation took the form of controlled experiments organised as a research pipeline of four stages, described in the subsections that follow.

### 3.2.1 Data Acquisition

Two kinds of data were acquired, one for each half of the vault. For knowledge, a curated vault was assembled on three subjects that a local model cannot know well: Kenyan data protection law, taken from the Data Protection Act and its three sets of 2021 regulations (Data Protection Act, 2019); software documentation dated 2026, namely the release notes of SQLite, Python 3.15, Ollama and the Model Context Protocol; and the notes of a private software project. Fifty reasoning problems from GSM8K, a public benchmark of grade-school mathematics (Cobbe et al., 2021), served as a control that needs no memory. Each knowledge record is a question, its answer key and the passage that supports the key, as Table 3.1 shows.

!tab Table 3.1: Two records of the knowledge data
!widths 1.0,2.9,2.4
| Kind | Question | Answer key |
| Knowledge, one fact | Under Kenya's Data Protection Act, 2019, within how many hours of becoming aware of a personal data breach that poses a real risk of harm must a data controller notify the Data Commissioner? | seventy-two or 72 |
| Knowledge, several facts | Across SQLite 3.53.0 and 3.54.0 (both released in 2026), which three new options were added to the sqlite3_limit() interface? | SQLITE_LIMIT_PARSER_DEPTH; SQLITE_LIMIT_SCHEMA; SQLITE_LIMIT_TRIGGER_STEPS |

For decisions, a fixture project called Matatu was written for the study: a Python service of about 1,500 lines that records matatu fares paid by M-Pesa and matches each payment on a statement to its ticket. It came with four written tasks, hidden tests that the models could not read, and one business decision with a reason and two rejected options: payments are matched by account reference only, because conductors pay for a whole group from one phone. None of the data contains personal information about any real person.

### 3.2.2 Data Preparation

The documents of the three subjects were converted to Markdown and placed in one vault, so that two subjects stood as distractors for the third, and Burrow indexed the vault before any evaluation began. For each subject, 25 single-fact and 15 multi-fact questions were written from the documents by Claude Code agents, and a script checked every key against the text of the vault and rejected any key that appeared in its own question. The reasoning problems were drawn once from the GSM8K test split with a fixed random seed. For the decision experiments, a script built a fixed starting point: the vault with the Matatu code linked into it, and a first session by a cloud coding model that had kept the payment decision in Burrow. The brief of that first session was then removed, so that later sessions could learn of the decision only through Burrow. In both kinds of experiment, the questions, keys and hidden tests were kept outside the vault, so that no answer could be read from the memory under test.

### 3.2.3 Experimental Conditions

No model was trained or fine-tuned; every model was used as published, because Burrow works beside a model and does not change it. In the knowledge experiment, six set-ups were run on every question: the local model alone, which is the floor; the local model with plain retrieval; the local model with a vector database baseline; the local model with Burrow, which is the treatment; the cloud model alone; and the cloud model with Burrow. In the decision experiments, the same model was given the same task with Burrow and with a baseline in its place, such as no memory, a pasted transcript, plain vector search or an earlier build of Burrow. Section 3.5.2 gives the full design.

### 3.2.4 Measurement and Validation

Every run logged the model and tool used, their versions, the tokens read and written, the seconds taken, and the full transcript, so that every result could be examined from its logs. Knowledge answers were scored against their keys and decisions against the hidden tests of the fixture. Validity was protected by paired designs, scoring rules written before the main runs, a frozen build for the knowledge experiment, the reading of every transcript, and the measures described in Section 3.5.6.

## 3.3 Development Approach

The system was developed by incremental prototyping, in small working stages, each of which was checked before the next was begun. Iterative and incremental development grows a system in small steps in which the result of each step informs the next (Larman & Basili, 2003), and design science asks for the same cycle of building and evaluating (Hevner et al., 2004). This approach suited the study for two reasons. First, the requirements changed as the work went on: the Sprint II review asked for something a person can see and use, and testing with real models raised needs that were taken into later increments. Second, Burrow is made of separable parts, so each could be built, tested and measured in turn. The system was analysed and designed with OOAD, because the memory is naturally a set of objects, such as a vault, a ledger and a commit, that hold their own data and behaviour, and Chapter 4 therefore presents diagrams drawn in the Unified Modeling Language.

Development proceeded in the five increments shown in Figure 3.1. The first increment built the memory as plain Markdown files with a rebuildable SQLite index, search by words and by meaning, and the links between files, after an earlier prototype in Python under the working name CAMR. The second increment built the steps that give a local model knowledge from the vault, deciding whether the vault is needed and how much to show, and evaluated them on the knowledge questions. The third increment added the Ledger of decisions, the MCP server through which local and cloud models reach the vault, hooks for coding tools and the desktop application. The fourth increment tested the vault with real AI tools on the Matatu tasks and added what those runs required, including the check of new work and the handover between models. The fifth increment made the check hold a change that breaks a decision, added sharing within a team, and strengthened the vault's security.

!fig figures/v5/incremental.png | Figure 3.1: Incremental development approach applied to Burrow, drawn by the author | 6.2

## 3.4 System Analysis

The requirements were worked backwards from the specific objectives, the measurements the evaluation needed, the Sprint II review and the faults found in real runs, so that each capability maps to an experiment or to the person using the system. Following OOAD, they were analysed with use case, sequence, activity and class diagrams, and stated as functional, non-functional, data and interface requirements with identifiers; Sections 4.2 and 4.3 present them.

## 3.5 System Design

This section states how Burrow and the experiments that evaluated it were designed.

### 3.5.1 Architectural Overview

Burrow was designed in layers: the models and AI programs that connect to it, the interfaces through which they connect, an engine that holds the vault, the Ledger and the check, and stores on disk that are plain files beside one index that can be rebuilt from them. The design was captured in a system architecture diagram, a logical database schema, wireframes and a deployment diagram, which Section 4.4 presents.

### 3.5.2 Experimental Design

The knowledge experiment was designed around one central quantity, the fraction of the capability gap closed. The six set-ups of Section 3.2.3 were run on every question, with the local models at a temperature of zero. Plain retrieval and the vector database used the same vault, the same embedding model and the same limit of 12,000 characters. For each task type, the gap closed was computed as shown in Equation 3.1, where S denotes the accuracy of a set-up on that task type. The ceiling was the cloud model given the same vault, which compares like with like on material the cloud model could not have seen in training.

!eq gap | Equation 3.1: Fraction of the capability gap closed

A value of zero means the vault adds nothing, and a value of one means the local model with the vault matches the cloud model. The measure is not reported where the ceiling is less than ten percentage points above the floor, because one answer then moves it widely.

The decision experiments asked whether a model kept an earlier decision and carried earlier work on. In each, a later session by a local or cloud model worked on the Matatu fixture after an earlier session had kept the payment decision, and the outcome was compared with a baseline under the same task and starting point. The baselines were chosen to test each part of Burrow: no memory at all, the session's whole transcript pasted in, plain vector search over the decisions, and the build of Burrow before each improvement was made.

### 3.5.3 Datasets and Task Types

The 120 knowledge questions, 40 on each subject, were the knowledge-bound task type, split into 25 single-fact and 15 multi-fact questions per subject, where a multi-fact question needs two passages from two different files. The 50 GSM8K problems were the reasoning-bound control, where memory was predicted to help little and the question was whether Burrow would leave the vault out (Cobbe et al., 2021). The Matatu tasks were the decision-bound task type: a later task asks for unmatched payments to be handled, which tempts a model to bring back matching by phone and amount, the option the earlier decision had rejected.

### 3.5.4 Evaluation Metrics

A knowledge answer was right when it contained every required fact of its key, and a reasoning answer was right when its last number equalled the key. Accuracy was the share of right answers in a set-up, and the gap closed was computed from it using Equation 3.1. A decision was kept when both hidden decision tests of the fixture passed, and work was carried on when the next session continued the right step with its constraint. Every result was reported as a count with its sample size, and paired differences were tested with an exact two-sided sign test, because each outcome is simply right or wrong. Time was measured in seconds on the target laptop.

### 3.5.5 Ablation Procedure

Parts of Burrow were evaluated by changing one thing and measuring the result on the same tasks, holding everything else fixed. In the knowledge experiment, the amount of the vault shown to the model was varied from 2,000 to 32,000 characters, and parts of the engine were switched off in turn. In the decision experiments, each improvement, such as keeping reasons with decisions, ranking decisions by relevance or keeping the exact words of a session, was compared with the build before it, run from the same starting point.

### 3.5.6 Threats to Validity

Six threats were addressed. Answer leakage was prevented by keeping questions, keys and hidden tests outside the vault and reading every transcript for stray reads. Prompt sensitivity was limited by one fixed prompt for each set-up. Sampling error was addressed by paired designs, counts reported with their sample sizes and an exact sign test. Timing noise was addressed by reporting medians on one machine. Changes in the models were addressed by recording the exact version of every model and tool. Tuning bias was addressed by setting Burrow's thresholds on cases written for that purpose and not on the scored tasks.

## 3.6 Tools and Techniques

This section describes the tools that were used to build Burrow and its evaluation, and the role each played. Their exact versions are given in Section 5.2.2.

### 3.6.1 Swift

Burrow's engine, its command-line program, its MCP server and its desktop application were written in Swift, the native language of the target platform, so that Burrow runs as one compiled program with no interpreter.

### 3.6.2 SQLite with FTS5

The index is SQLite, one database file with no server process. The word index uses the FTS5 full-text extension (SQLite, 2026), and the embedding vectors are stored in the same database with a memory-mapped copy beside it for speed.

### 3.6.3 Ollama and Local Models

Local models were served through Ollama, which runs quantised open-weight models on consumer hardware (Ollama, 2026). The main local model was Gemma 4 12B, with Qwen models used in some experiments (Gemma Team, 2026; Qwen Team, 2026).

### 3.6.4 Cloud Models

The cloud models were Claude models from Anthropic, reached through Claude Code (Anthropic, 2026a) and through Anthropic's API, with the version of each run recorded so that the ceiling and the behaviour of the cloud tools could be traced.

### 3.6.5 Embedding Model

Embedding vectors were produced on the laptop by Qwen3 Embedding 0.6B (Zhang et al., 2025). Burrow and the vector database baseline used the same model.

### 3.6.6 Model Context Protocol and AI Programs

The Model Context Protocol, an open standard between AI applications and outside services (Model Context Protocol, 2026), was used so that every model reaches the same memory. The programs connected through it in the evaluation were Claude Code, OpenCode, OpenClaw, Hermes Agent, n8n and the llama.cpp server.

### 3.6.7 Chroma

Chroma, an open-source vector database (Chroma, 2026), was run locally to build the vector database baseline of Section 3.5.2.

### 3.6.8 Auxiliary Tools

The evaluation scripts and the charts were written in Python. Claude Code wrote the knowledge questions under the checks of Section 3.2.2. Version control used Git and GitHub, and the state of the code at each evaluation was marked, so that a result can be traced to the code that produced it.

## 3.7 Deliverables

The study produced the following deliverables, each described in its own subsection.

### 3.7.1 The Burrow Vault

A Swift package that implements the vault, its index, the Ledger of decisions and the check of new work designed in Chapter 4, with a command-line program named burrow, running entirely on the target laptop.

### 3.7.2 The MCP Server and the Desktop Application

An MCP server through which local and cloud models reach the vault, setup commands and hooks for coding tools, and a native desktop application in which the person reads the vault, reviews the decisions models have kept and connects their AI tools.

### 3.7.3 The Evaluation Material

The question sets, the Matatu fixture with its tasks and hidden tests, the scripts that ran every experiment, and the saved transcripts and results.

### 3.7.4 Experimental Results

The measured gap closed per task type, the results of the decision experiments, and the time taken by each step, together with the logs that support them.

### 3.7.5 System Documentation

This report, with the design, the experiments and the findings, and the repository with its user guide and record of design decisions, needed to reproduce the results.
