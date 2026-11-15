# Chapter 3:  Methodology

## 3.1 Introduction

This chapter presents the methodological approach of the study and introduces the experimental design used to evaluate Burrow. Unlike conventional software projects, the study had to show by controlled experiments with real models that the vault changes what those models do, so the chapter begins with the research paradigm and its four stages: data acquisition, data processing, the setting of the models, and validation and testing. It then presents the system development methodology and its justification, the methodology diagram with each of its stages, the analysis and design diagrams that Chapter 4 presents, the deliverables, and the tools and techniques used. The system was analysed and designed with Object-Oriented Analysis and Design (OOAD).

## 3.2 Research Paradigm

The study adopted an experimental research paradigm within design science research. Design science research was appropriate because the study created and evaluated a new artefact, the Burrow vault, and the discipline requires such an artefact to be evaluated rigorously against explicit measures of its usefulness (Hevner et al., 2004). The study followed the stages set out by Peffers et al. (2007): identifying the problem, defining the objectives of a solution, designing and developing the artefact, demonstrating it, evaluating it and communicating the results. The evaluation took the form of controlled experiments, in which the same model was given the same questions or tasks with the vault and with a baseline in its place, against two measurable objectives: the fraction of the knowledge gap between a local and a cloud model that the vault closed, and whether a later model kept an earlier decision and carried the earlier work on. For example, one experiment asked whether supplying the relevant section of Kenya's Data Protection Act from the vault let a local model answer a question about reporting a data breach that it could not answer alone. The experiments were organised in four stages, described in the subsections that follow.

### 3.2.1 Data Acquisition

Two kinds of data were acquired, one for each half of the vault. For knowledge, a vault of 87 real documents was assembled on three subjects that a local model cannot know well: Kenyan data protection law, taken from the Data Protection Act and its three sets of regulations of 2021 (Data Protection Act, 2019); software documentation dated 2026, namely the release notes of SQLite, Python 3.15, Ollama and the Model Context Protocol; and the notes of a private software project. Fifty reasoning problems from GSM8K, a public benchmark of grade-school mathematics (Cobbe et al., 2021), served as a control that needs no memory. Each knowledge record is a question, its answer key and the passage that supports the key, as the two examples in Table 3.1 show.

!tab Table 3.1: Two records of the knowledge data
!widths 0.9,2.5,2.9
| Kind | Question | Answer key |
| Knowledge, one fact | Under Kenya's Data Protection Act, 2019, within how many hours of becoming aware of a personal data breach that poses a real risk of harm must a data controller notify the Data Commissioner? | seventy-two or 72 |
| Knowledge, several facts | Across SQLite 3.53.0 and 3.54.0 (both released in 2026), which three new options were added to the sqlite3_limit() interface? | SQLITE_LIMIT_PARSER_DEPTH; SQLITE_LIMIT_SCHEMA; SQLITE_LIMIT_TRIGGER_STEPS |

For decisions, a fixture project called Matatu was written for the study: a Python service of about 1,500 lines that records matatu fares paid by M-Pesa and matches each payment on a statement to its ticket. It came with four written tasks, hidden tests that the models could not read, and one business decision with its reason and two rejected options: payments are matched by account reference only, because conductors often pay for a whole group from one phone. A later task asks for unmatched payments to be handled, which tempts a model to bring back matching by phone and amount, the option the decision had rejected.

All the material was either public, such as the law and the software documentation, or written by the author, such as the project notes and the Matatu fixture, whose payments and passengers are invented. No personal data about any real person was collected or processed, in keeping with the Data Protection Act (2019).

### 3.2.2 Data Processing

The documents of the three subjects were converted to Markdown and placed in one vault, so that two subjects stood as distractors whenever a question concerned the third. For each subject, 25 single-fact and 15 multi-fact questions were written from the documents by Claude Code agents, where a multi-fact question needs passages from two different files. A script checked every answer key against the text of the vault and rejected any question whose key appeared in the question itself. The reasoning problems were drawn once from the GSM8K test split with a fixed random seed.

Burrow then indexed the vault before any evaluation began. Each file was split at its headings or code boundaries, and the pieces were indexed by their words and by embedding vectors of their meaning, with the links between files kept, so that a search could return an excerpt with its file and line. For the decision experiments, a script built a fixed starting point: the vault with the Matatu code linked into it, and a first session by a cloud coding model that had kept the payment decision in Burrow. The brief of that first session was then removed, so that later sessions could learn of the decision only through Burrow. In both kinds of experiment, the questions, answer keys and hidden tests were kept outside the vault, so that no answer could be read from the memory under test.

### 3.2.3 Model Training

No model was trained or fine-tuned. Burrow works beside whichever model a person chooses, so its value had to be shown with models used as published; training a model on the person's material would also need computing power that ordinary users lack and would have to be repeated whenever the material changed. In place of training, the experimental conditions were fixed. In the knowledge experiment, six set-ups were run on every question: the local model alone, which is the floor; the local model with plain retrieval; the local model with a vector database built on Chroma, which is the baseline; the local model with Burrow, which is the treatment; the cloud model alone; and the cloud model with Burrow, which is the ceiling. Local models ran in Ollama at a temperature of zero, each set-up used one fixed prompt, and plain retrieval and the vector database used the same vault, the same embedding model and the same limit of 12,000 characters. In the decision experiments, a later session by a local or cloud model worked on the Matatu fixture after the earlier session had kept the payment decision, and the outcome was compared with a baseline under the same task and starting point: no memory at all, the earlier session's transcript pasted in, plain vector search over the decisions, or the build of Burrow from before each improvement. Burrow's own thresholds were set on cases written for that purpose and never on the scored questions or tasks, so that no part of the vault was tuned to the test.

### 3.2.4 Model Validation and Testing

Every run logged the model and program used, their versions, the tokens read and written, the seconds taken and the full transcript, so that each result can be traced to its logs. A knowledge answer was right when it contained every required fact of its key, and a reasoning answer was right when its last number equalled the key. For each task type, the fraction of the gap closed was computed as shown in Equation 3.1, where S denotes the accuracy of a set-up on that task type.

!eq gap | Equation 3.1: Fraction of the capability gap closed

A value of zero means that the vault adds nothing, and a value of one means that the local model with the vault matches the cloud model with the vault. The ceiling was the cloud model given the same vault, because the material is new to every model, and the measure was not reported where the ceiling was less than ten percentage points above the floor, since one answer would then move it widely. A decision was kept when both hidden decision tests of the fixture passed, and work was carried on when the next session continued the right step with its constraint.

Validity was protected in four ways. The questions, keys and hidden tests formed a held-out set that never appeared in the vault or in the tuning of Burrow, and every transcript was read to confirm that no model found an answer elsewhere. Each result was reported as a count with its sample size, and paired results were compared with an exact two-sided sign test, because each outcome is simply right or wrong. Time was measured in seconds on the target laptop. The exact version of every model and program was recorded, so that a change in a hosted model could be traced.

## 3.3 System Development Methodology

Burrow was developed with an iterative and incremental methodology from the Agile family. The system was built in five increments, each of which passed through analysis, design, building and evaluation and ended in a working build that was tested before the next increment began. The methodology was guided by the OOAD paradigm, which models a system as objects that hold their own data and behaviour and suits incremental methods, because each increment can add or refine objects without redesigning the rest.

### 3.3.1 Justification of the Methodology

Iterative and incremental development grows a system in small steps in which the result of each step informs the next, and it has a long record of use on projects whose requirements cannot be fixed in advance (Larman & Basili, 2003). Design science asks for the same cycle, alternating between building an artefact and evaluating it (Hevner et al., 2004), and allows a project to return to earlier stages when evaluation reveals a problem (Peffers et al., 2007). This methodology suited the study for three reasons. First, the requirements changed as the work went on: the Sprint II review asked for something a person can see and use, and testing with real AI programs exposed needs that no specification had foreseen. Second, Burrow is made of separable parts, so each could be built, tested and measured in turn, and a phased method such as the Waterfall model, which fixes all requirements before design, would have pushed every such discovery to the end. Third, evaluating each increment with real models reduced the largest risk of the project, which was finding late that the vault did not change what the models do.

OOAD was chosen as the paradigm because the memory is naturally a set of objects, such as a vault, a decision and a session, each with its own data and behaviour, which increments could extend independently. Chapter 4 therefore presents the analysis and design in diagrams of the Unified Modeling Language (UML).

## 3.4 Methodology Diagram

Figure 3.1 shows the methodology as applied to Burrow: five increments between June and November 2026, each passing through analysis, design, building and evaluation, and each adding capability to the last. The first increment built the memory as plain Markdown files with a rebuildable index, search by words and by meaning, and the links between files. The second built the steps that give a local model knowledge from the vault and evaluated them on the knowledge questions. The third added the record of decisions, the MCP server through which models reach the vault, hooks for coding tools and the desktop application. The fourth tested the vault with real AI programs on the Matatu tasks and added what those runs required. The fifth strengthened the check of new work and the vault's security and added sharing within a team.

!fig figures/v5/incremental.png | Figure 3.1: Incremental development methodology applied to Burrow, drawn by the author | 5.6

### 3.4.1 Analysis

In this stage, the needs to be met by the increment were identified and prioritised. Requirements were worked backwards from the specific objectives and from the measurements that the evaluation needed, and were informed by secondary sources: the literature reviewed in Chapter 2, the documentation of the AI programs to be connected, and the MCP specification. In later increments they also came from the Sprint II review and from faults seen in real runs, so that each capability maps either to an experiment or to the person using the system. The analysis diagrams are introduced in Section 3.5.

### 3.4.2 Design

In this stage, the increment was designed following OOAD: the objects it added, their responsibilities and the interactions between them, together with the experiment that would evaluate it. Designing the experiment alongside the system ensured that every part of Burrow could be measured. The design diagrams are introduced in Section 3.6, and Chapter 4 presents the full analysis and design.

### 3.4.3 Build

In this stage, the increment was implemented and integrated with the existing system. Burrow was written in Swift with SQLite as its index, local models were served through Ollama, and AI programs were connected through MCP; Section 3.8 lists and justifies each tool. Every increment ended in a working build whose state was marked in version control, so that every later result could be traced to the code that produced it.

### 3.4.4 Evaluate

In this stage, the increment was tested and measured before the next began. Unit testing checked individual components, such as the rebuilding of the index and the rule that a recorded decision is never overwritten, which was white-box testing of the internal logic. Integration testing checked that the components worked together and that real AI programs could connect through MCP and receive the decisions in force. System testing exercised Burrow end to end from the point of view of the person and their AI programs, as black-box testing with normal, wrong, boundary and hostile input. Performance was measured with the experiments of Section 3.2.4: the number of knowledge questions answered, the fraction of the gap closed, whether decisions were kept and work carried on, and the seconds taken on the laptop. Each test case was traced to a requirement, and the test cases are presented in Chapter 5.

### 3.4.5 Iteration and Final Evaluation

The results of each evaluation fed the analysis of the next increment, so that a weakness found in one round became a requirement in the following one. After the fifth increment, the build used for each experiment was fixed, and the full experiments were run on it. The final evaluation judged whether Burrow met the fourth and fifth specific objectives by the measures of Section 3.2.4, documented every result with its logs and transcripts, and recorded the remaining limits as the basis for further development.

## 3.5 System Analysis Diagrams

Following OOAD, the requirements were analysed with four UML diagrams chosen from those suited to object-oriented analysis. Section 4.3 presents them.

### 3.5.1 Use Case Diagram

The use case diagram identifies the actors, the person and the local and cloud AI programs that connect to the vault, and the goals each pursues, such as finding material, keeping a decision and resuming earlier work. It defines the boundary of the system.

### 3.5.2 Sequence Diagram

The sequence diagram shows the order of messages between an AI program and Burrow during a session, from connecting and resuming earlier work to looking up material, changing code and having the change checked.

### 3.5.3 Activity Diagram

The activity diagram shows the flow of the check of new work, from a proposed change to the verdict for each decision it touches and the action that follows.

### 3.5.4 Class Diagram

The class diagram shows the objects of Burrow's engine, their attributes and responsibilities, and the relationships between them.

## 3.6 System Design Diagrams

The design was captured in four diagrams that refine the analysis into a buildable system. Section 4.4 presents them.

### 3.6.1 System Architecture

The system architecture diagram shows the layers of Burrow, from the AI programs that connect to it and the interfaces they connect through, to the engine and the stores on disk.

### 3.6.2 Logical Database Schema

The logical database schema shows the entities that Burrow stores, with their keys and relationships, covering the record of decisions, sessions and the index of the vault.

### 3.6.3 Wireframes

The wireframes show the main pages of the desktop application in which the person reads the vault, reviews the decisions that models have kept and connects AI programs.

### 3.6.4 Deployment Diagram

The deployment diagram shows where each part of Burrow runs: on the person's laptop beside the local model service, with cloud models reached over the internet by the programs that use them.

## 3.7 Deliverables

### 3.7.1 The Burrow Vault

A Swift package that implements the vault, its index, the record of decisions and the check of new work, with a command-line program named burrow, running entirely on the person's laptop.

### 3.7.2 The MCP Server and the Desktop Application

An MCP server through which local and cloud models reach the vault, commands and hooks that connect coding tools and other AI programs, and a desktop application in which the person reads the vault, reviews the decisions that models have kept and connects their AI programs.

### 3.7.3 The Evaluation Material and Results

The knowledge questions with their answer keys, the Matatu fixture with its tasks and hidden tests, the scripts that ran every experiment, and the saved logs, transcripts and results.

### 3.7.4 System Documentation

This report, and the project repository with its user guide and record of design decisions, sufficient for another person to install Burrow and reproduce the results.

## 3.8 Tools and Techniques

### 3.8.1 Swift

Burrow's engine, its command-line program, its MCP server and its desktop application were written in Swift, the native language of the target platform. This let Burrow run as one compiled program with no interpreter or server process, and gave the desktop application the platform's own interface.

### 3.8.2 SQLite with FTS5

The index of the vault is SQLite, a database held in one file with no server process, which suits a memory that lives on the person's own disk. Its FTS5 extension provides full-text search with BM25 ranking (SQLite, 2026), and the embedding vectors and links are stored in the same file. Because the index is rebuilt from the plain files, the person's material stays readable without Burrow.

### 3.8.3 Ollama and Local Models

Local models were served through Ollama, which runs quantised open-weight models on consumer hardware and offers a local interface to them (Ollama, 2026). The main local model was Gemma 4 12B (Gemma Team, 2026), with Qwen models used in some experiments (Qwen Team, 2026), chosen because they are recent open-weight models sized for the laptop.

### 3.8.4 Cloud Models and Claude Code

The cloud models were Claude models from Anthropic, reached through Claude Code, a coding tool that reads a codebase and acts on it (Anthropic, 2026a), and through Anthropic's service. Claude Code was chosen because it is widely used, supports MCP and hooks, and keeps its own project memory in files, which made it a demanding test of whether decisions reach a cloud model through Burrow.

### 3.8.5 Embedding Model

Embedding vectors for search by meaning were produced on the laptop by Qwen3 Embedding 0.6B (Zhang et al., 2025), a small open model that runs quickly through Ollama. Burrow and the vector database baseline used the same model, so that a difference between them could not come from the embeddings.

### 3.8.6 Model Context Protocol and AI Programs

MCP, an open standard between AI applications and outside services (Model Context Protocol, 2026), was used so that every model reaches the same memory without being changed. The programs connected through it in the evaluation were Claude Code, OpenCode, OpenClaw, Hermes Agent, n8n and the llama.cpp server, chosen to cover cloud and local models, coding tools and a workflow platform.

### 3.8.7 Chroma

Chroma, an open-source vector database (Chroma, 2026), was run locally to build the vector database baseline, because it represents the standard way of giving a model retrieval over documents.

### 3.8.8 Auxiliary Tools

The evaluation scripts and charts were written in Python. Version control used Git and GitHub, and the state of the code at each evaluation was marked so that every result can be traced to the code that produced it.
