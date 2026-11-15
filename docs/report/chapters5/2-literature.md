# Chapter 2:  Literature Review

## 2.1 Introduction

This chapter reviews the work on which the study builds, in order to ground the problem of Section 1.2: decisions made during AI-assisted work, with their reasons, are lost between sessions and tools. Section 2.2 reviews the current state of the field and addresses the first specific objective, from the older software engineering record of decisions to the memory of today's AI tools, and closes with the key challenges. Section 2.3 reviews six related systems and addresses the second objective. Section 2.4 identifies the gaps they leave, which is the third objective, and Section 2.5 presents the conceptual framework that guided the design. The sources are mainly peer-reviewed conference and journal papers, with preprints where a topic is too recent for peer review and official documentation for software products. Most were published between 2023 and 2026; older sources were kept where they introduced an idea this study relies on.

## 2.2 Current State of Decision Memory for AI Tools

This section reviews how decisions are kept in software work, how AI tools remember, why retrieval and long contexts do not solve the problem on their own, and how stored knowledge is kept current.

### 2.2.1 Decisions and Their Rationale in Software Work

Software engineering has treated the loss of design decisions as a problem for two decades. Bosch (2004) argued that the main weakness of software architecture was that design decisions had no first-class representation, and Jansen and Bosch (2005) called the result knowledge vaporisation: the reasons behind a design disappear into the design, so later changes violate earlier decisions without anyone knowing. Tang et al. (2006) surveyed 81 practitioners and found that they valued design rationale but met barriers in recording it. Losing people loses decisions too: in a study of Chrome and a project at Avaya, departing developers took with them the knowledge of the decisions they had made, and the loss was more than three times larger than expected (Rigby et al., 2016).

The best-known response is the architecture decision record (ADR), a short file per decision giving its context, the decision, its status and its consequences (Nygard, 2011). An accepted ADR is not edited; a later ADR supersedes it (Kunce & Goby, 2022). Writing ADRs was reported to improve how teams follow through on decisions (Keeling, 2022), and an action research study found that where the records are stored strongly affects whether they are used (Ahmeti et al., 2024). Adoption remains low: in a study of GitHub, about half of the repositories that used ADRs held only one to five of them (Buchgeher et al., 2023). Rationale is often written somewhere less formal instead; in the Linux kernel's out-of-memory killer, 98.9% of commit messages contained rationale (Dhaouadi et al., 2024). Decisions are therefore recorded, when they are recorded at all, by people, after the fact, in places a later reader must know to look.

### 2.2.2 AI Tools and Their Memory

AI tools now make and carry out decisions in the course of their work. A coding assistant such as Claude Code reads a codebase, edits it and runs its tests (Anthropic, 2026a), and benchmarks such as SWE-bench measure such agents on real GitHub issues (Jimenez et al., 2024). The Model Context Protocol (MCP) lets any such program discover and call the tools of an outside server, so one service can serve many AI programs (Model Context Protocol, 2026; Hou et al., 2026). Each program still starts a session from what its maker chooses to supply. Context engineering, the curation of what enters a model's limited context, has become a discipline of its own, with compaction and structured note-taking among its techniques for long tasks (Rajasekaran et al., 2025).

The common way to give a coding agent memory is a context file that the agent reads at the start of every session: CLAUDE.md for Claude Code (Anthropic, 2026b), and AGENTS.md or Cursor rules for other tools. Studies of thousands of such files found them dominated by build commands, implementation notes and architecture (Chatlatanagulchai et al., 2025; Chatlatanagulchai et al., 2026; Sun et al., 2026). Whether they help is in doubt. Gloaguen et al. (2026) found that context files did not generally raise task success and added more than 20% to inference cost, and Voria et al. (2026) found that coding agents followed the instructions in them 59.8% of the time on average, with 37.3% of instructions never followed. When a file disagreed with the code because it had gone stale, agents followed the file in 90.1% of their choices (X. Xu & Wu, 2026). A context file is written by a person, applies to one repository, and knows nothing of what was decided in yesterday's session unless someone copied it in.

Small models that run on the person's own computer add a further reason to keep memory outside the model. They keep data on the device and cost nothing per request (J. Xu et al., 2024), but they know least of what is not in their training data (Mallen et al., 2023; Kandpal et al., 2023), so they depend most on what they are given.

### 2.2.3 Retrieval and Long Contexts

Retrieval-augmented generation (RAG) gives a model passages fetched for each request from an index of documents (Lewis et al., 2020), and it is the usual way to give a model memory beyond its context. It fails in known ways: the relevant document may be missing, ranked too low, cut from the context, or present but not used (Barnett et al., 2024). Decisions are a hard case for similarity search because they are often phrased as negations, such as never matching by phone number, and most retrieval models rank negated pairs no better than random (Weller et al., 2024).

Putting more into the context is not a substitute. Models use information at the start and end of a long context better than in the middle (N. F. Liu et al., 2024), performance falls as input grows (Hong et al., 2025), and models lose 39% of their performance on average when the instructions for a task arrive over several turns rather than at once (Laban et al., 2026). Commercial chat assistants lost about 30% accuracy on facts that had to be remembered across sustained interaction (Wu et al., 2025). Memory for an AI tool must therefore choose a few things to give, and give them where they will be read.

### 2.2.4 Keeping Memory Current

A memory that only grows can hand over a decision that has since been overturned. Language models resolve such conflicts poorly: across 1,200 questions, six leading models adopted incorrect retrieved content over their correct prior knowledge more than 60% of the time (Wu, Wu, & Zou, 2024), and conflicts between context and memory are a recognised class of failure (R. Xu et al., 2024). On reversed facts, append-only and last-write-wins memories both scored 0.21, below no memory at all at 0.31, while explicit revocation scored 0.95 (Zhou et al., 2026). Evidence also ages: in two projects audited by Gilda and Gilda (2026), 20 to 25% of architectural decisions had stale evidence within two months. Keeping memory current therefore means recording which decision replaced which, and noticing when the thing a decision rests on has changed.

### 2.2.5 Key Challenges

The literature points to five challenges for a memory of decisions used by AI tools. The first is capture: decisions are recorded by people, after the fact, and seldom (Tang et al., 2006; Buchgeher et al., 2023), while AI tools now make them in the moment. The second is delivery: a decision must reach the next tool, in another program, at the point of use, and neither similarity search nor a longer context guarantees that (Weller et al., 2024; Laban et al., 2026). The third is currency: memories that only append hand over stale and reversed decisions (Zhou et al., 2026; Gilda & Gilda, 2026). The fourth is obedience: a model given an instruction does not always follow it (Voria et al., 2026), and the best model in an agentic benchmark met only 59.8% of the constraints set for it (Qi et al., 2025). The fifth is safety: text in a memory can carry instructions that take over the model (Greshake et al., 2023), a few planted records can steer an agent (Chen et al., 2024), and prompt injection and excessive agency lead the known risks of applications built on language models (OWASP Foundation, 2024).

## 2.3 Related Works

This section reviews six systems that give AI tools a memory, chosen to cover the main approaches: managed context, memory layers, temporal knowledge graphs, context files, decision records and vector retrieval. Table 2.1 compares them.

### 2.3.1 MemGPT and Letta

Packer et al. (2023) treated the context window as main memory and an outside store as disk, and let the model page information in and out through function calls, as an operating system does. Figure 2.1 shows this architecture. Its successor, Letta, keeps memory blocks that are always in the context and that several agents can share (Letta, 2025). The approach keeps memory within one agent framework: blocks are shared between Letta agents, not with a coding tool or a workflow running elsewhere, and a block holds text without a reason, the files it governs, or a record of what replaced it.

!fig figures/related/fig2-1-memgpt.png | Figure 2.1: The MemGPT virtual context architecture. Adapted from Packer et al. (2023) | 6.0

### 2.3.2 Mem0

Mem0 is a memory layer that extracts salient facts from conversations with a language model, consolidates them and retrieves them for later requests; on the LoCoMo benchmark its authors reported a 26% relative improvement over OpenAI's memory (Chhikara et al., 2025). Figure 2.2 shows the layer within an agent stack. Its plugins connect it to several coding tools, which makes it the nearest to sharing memory across programs. Memories are extracted automatically and retrieved by similarity, so a decision is kept only if the extractor judges it salient and returned only if it resembles the request, and the hosted service keeps the person's memory off their device.

!fig figures/related/fig2-5-mem0.png | Figure 2.2: The Mem0 memory layer within an agent stack. Source: Mem0 documentation, https://docs.mem0.ai | 6.0

### 2.3.3 Zep and Graphiti

Zep stores memory as a temporal knowledge graph through its engine, Graphiti (Rasmussen et al., 2025). Each fact is an edge with the time it held true, and when a new fact contradicts an old one, a language model detects it and marks the old edge invalid rather than deleting it. Figure 2.3 shows the idea: a fact is invalidated at a point in time and a newer one takes its place. Zep reported 94.8% on the deep memory retrieval benchmark against 93.4% for MemGPT. It is the related system that best handles currency, but its facts are extracted from conversation, not tied to files, and nothing checks new work against them.

!fig figures/related/fig2-zep-graphiti.png | Figure 2.3: A fact invalidated and replaced over time in Graphiti, the engine of Zep. Source: Graphiti repository, https://github.com/getzep/graphiti | 5.6

### 2.3.4 Context Files for Coding Agents

Context files such as CLAUDE.md and AGENTS.md are Markdown files in a repository that a coding agent reads at the start of each session. Chatlatanagulchai et al. (2025) studied 2,303 of them and found that they covered testing, implementation details and architecture far more often than security or performance; Figure 2.4 shows an example. They are simple, versioned with the code and read by many tools. Their limits were measured in Section 2.2.2: they are written by people, they hold only what someone copied in, agents often do not follow them, and a stale file is followed over the code (Voria et al., 2026; X. Xu & Wu, 2026).

!fig figures/related/fig2-agent-readme.png | Figure 2.4: An example of a context file for a coding agent. Source: Chatlatanagulchai et al. (2025) | 5.4

### 2.3.5 Architecture Decision Records

An ADR records one decision with its context, status and consequences, and a later record supersedes it rather than editing it (Nygard, 2011). Figure 2.5 shows how an ADR is used to review a change: if the change violates the ADR, the reviewer links the record and the author updates the change. ADRs have the structure this study needs, a decision with its reason and a way to retire it, and they have been checked against code by language models with good accuracy for decisions that can be read from the code (Su et al., 2026). They are written by people, kept in one repository, and checked at human review rather than before an AI tool reports its work as done.

!fig figures/related/fig2-adr-aws.png | Figure 2.5: Using an architecture decision record to review a change. Source: Kunce and Goby (2022) | 4.6

### 2.3.6 Retrieval with a Vector Database

The most common memory for AI applications is a vector database such as Chroma, which stores passages as embedding vectors and returns those nearest to a request (Chroma, 2026). Figure 2.6 shows its distributed architecture. A vector database scales to large collections and works with any model, and it served as a baseline in this study. It returns what resembles the request, which may not be the decision that governs it, keeps no reason or author with a passage, and has no notion of a passage being replaced.

!fig figures/related/fig2-6-chroma.png | Figure 2.6: The architecture of distributed Chroma. Source: Chroma (2026), https://docs.trychroma.com/reference/architecture/distributed | 6.0

Table 2.1 compares the six systems on what this study needs of a decision memory.

!tab Table 2.1: Comparison of related systems as a memory of decisions for AI tools
!widths 1.15,1.0,1.0,0.9,1.1,1.0,0.95
| System | Shared across tools | Who records | Reason kept | How it is delivered | Knows it is out of date | Checks new work |
| MemGPT and Letta | Within Letta agents | The agent | No | Always in context | No | No |
| Mem0 | Yes, by plugin | Automatic extraction | Not required | By similarity | Ranks the newest | No |
| Zep and Graphiti | Through a server | Automatic extraction | Not required | By search | Yes, for facts | No |
| Context files | Coding tools of one repository | The person | If written | Read at session start | No | No |
| Architecture decision records | One repository | The person | Yes | When looked up | Superseded by hand | At human review |
| Vector database | Any application | An ingest pipeline | No | By similarity | No | No |

## 2.4 Gaps in Related Works

Table 2.1 shows that no related system meets all of what a decision memory for AI tools needs. First, none is written by the AI tool at the moment a decision is made with a reason that must be given: Mem0 and Zep extract facts automatically and may miss a decision or its reason (Chhikara et al., 2025; Rasmussen et al., 2025), while context files and ADRs depend on a person writing them afterwards (Nygard, 2011; Buchgeher et al., 2023). Second, delivery is either to every request regardless of relevance, as with memory blocks and context files, or by similarity, which can miss a decision worded unlike the request (Weller et al., 2024). Third, only Zep knows when a fact has been replaced, and none knows when the code a decision governs has changed. Fourth, none checks an AI tool's change against the decisions it touches before the work is called done; ADRs are checked at human review, after the fact (Kunce & Goby, 2022). Fifth, the systems that share across tools rely on a hosted service or a server, while a person working on private material may need the memory to stay on their own computer (J. Xu et al., 2024). The unmet need this study targets is a private memory on the person's computer in which AI tools record decisions with their reasons as they make them, which hands those decisions to every later tool, knows when they are out of date, and checks new work against them.

## 2.5 Conceptual Framework

A conceptual framework shows the key variables of a study and how they relate, and guides the design and its evaluation. This section sets out the variables, their theoretical foundation, the framework itself and how it was used.

### 2.5.1 Variables

The independent variables are the inputs: the person's work with AI tools, in which decisions are made, and the person's material, the notes, documents and code those decisions concern. The processing is what Burrow does with them: keep, hand over, watch, check and share. The dependent variables are the outputs that the evaluation measures: whether the next tool keeps the decision, whether a tool can carry the work on, and the verdict on a change, together with whether the right material was found and how long each step took.

### 2.5.2 Theoretical Foundation

The framework rests on two ideas. From software architecture it takes the view that a design is a set of decisions, each with its rationale, and that the rationale vaporises unless it is kept as a first-class record (Jansen & Bosch, 2005; Tang et al., 2006). From research on language model memory it takes the view that what a model reads should be chosen, few and timely, because more context is not better context (N. F. Liu et al., 2024; Laban et al., 2026), and that stored knowledge must be revoked explicitly when it is replaced (Zhou et al., 2026). Design Science Research frames the whole: an artefact is built to address the problem and evaluated against it (Hevner et al., 2004).

### 2.5.3 Visual Representation

Figure 2.7 shows the conceptual framework as a flow of the system: the inputs at the top, the five processing steps of the engine in the middle, and the outputs at the bottom, with a feedback loop by which each new decision joins the Ledger.

!fig figures/v5/framework.png | Figure 2.7: Conceptual framework of the study, drawn by the author | 6.27

### 2.5.4 Relationships between the Variables

A decision is kept only if the tool records it with a reason, so the quality of what is kept depends on the tool and on Burrow refusing a decision without one. What the next tool receives depends on what was kept and on how it is handed over, and whether the tool then keeps to it depends on the model as well as on the memory. The check closes that last gap by holding a change that touches a decision, whatever the model chooses. The feedback loop means the Ledger grows with use, which is why handing over few and relevant decisions matters more as time passes.

### 2.5.5 One Decision through the Framework

On Monday a person settles with Claude Code that payments are matched by account reference only, because a conductor often pays for a whole group from one phone. Claude Code keeps it in Burrow with that reason and the rejected options, citing the matching code. On Wednesday a different program, running a local model, connects and is handed the decision before it starts. It is asked to add a fallback for unmatched payments, and writes one that matches by phone and amount. When it tries to finish, Burrow judges that the change breaks the decision and holds it; the program tells the person which decision it went against, and puts the code back.

### 2.5.6 Alignment with the Design and the Evaluation

Each step of the processing became a group of requirements in Chapter 4: keeping is FR-03, handing over is FR-04 to FR-06, watching is FR-07 and FR-08, checking is FR-09, and sharing is FR-11. Each output became a measure in Chapter 5: whether the decision was kept, whether the work was carried on, and whether the verdict on a change was right. The framework was refined during the work as real runs showed where a step fell short, such as decisions that lost their reasons or never reached a program that hid its instructions from the model.
