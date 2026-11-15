# Chapter 2:  Literature Review

## 2.1 Introduction

This chapter reviews the literature on which the study rests. The problem it addresses is that decisions reached with one AI tool, and the reasons behind them, are lost to the tools that work on the same material afterwards. The review grounds that problem in existing scholarship and shows how the study builds on and departs from earlier work. It is organised by the first three specific objectives: Section 2.2 analyses the current state of memory for AI tools and its key challenges, Section 2.3 examines five related systems, and Section 2.4 draws out the gaps they leave. Section 2.5 then presents the conceptual framework that the study derived from these sections. The sources reviewed are mainly peer-reviewed conference and journal papers, supported by preprints where a topic is too recent for peer review and by official documentation for software products. They were chosen for their relevance to memory for AI tools and to the recording of decisions, and most were published between 2023 and 2026, with a few older works kept where they introduced an idea the study relies on.

## 2.2 Current State of Memory for AI Tools

### 2.2.1 Overview of Memory for AI Tools

Memory for an AI tool is whatever it is given, beyond the immediate request, about the work and the person it serves. Because a language model keeps nothing between requests, this memory is supplied by the program around the model, and several approaches are in current use.

The simplest is the instruction file. A coding agent such as Claude Code reads Markdown files kept in the project, such as CLAUDE.md, at the start of every session (Anthropic, 2026b), and thousands of open-source projects now keep such files for their agents (Chatlatanagulchai et al., 2025). A second approach is memory built into an agent framework. MemGPT treated the model's limited context as main memory and an outside store as disk, and moved information between them as an operating system does (Packer et al., 2023), while memory layers such as Mem0 extract facts from conversations and return them in later sessions (Chhikara et al., 2025). A third approach is retrieval-augmented generation, in which passages are fetched from an index for each request (Lewis et al., 2020), usually from a vector database that returns the passages closest in meaning to the request. The Model Context Protocol (MCP) now lets a program reach such memory as an outside service, so that one memory can serve many tools (Model Context Protocol, 2026; Hou et al., 2026). Outside AI, software engineering keeps decisions in architecture decision records, short documents that record a decision with its context and consequences (Nygard, 2011).

These approaches have had real successes. Memory layers have improved answers in long conversations, with Mem0 reporting a 26% relative improvement over OpenAI's memory on a benchmark of long conversations (Chhikara et al., 2025), and decision records have helped teams follow through on what they decided (Keeling, 2022). Their limitations are equally clear. Retrieval misses relevant passages, ranks them too low or returns them unused (Barnett et al., 2024), and most retrieval models rank negated statements, which decisions often are, no better than random (Weller et al., 2024). Supplying more context does not help reliably either, since models use the middle of a long context poorly (N. F. Liu et al., 2024) and lose 39% of their performance on average when instructions arrive over several turns (Laban et al., 2026). Stored knowledge also goes out of date: when retrieved content conflicted with what six leading models knew, they adopted the incorrect content more than 60% of the time (Wu, Wu, & Zou, 2024), and memories that only append scored 0.21 on reversed facts against 0.95 for memories that revoke the old fact (Zhou et al., 2026).

### 2.2.2 Key Challenges

Existing memory for AI tools faces five main challenges in keeping decisions.

1. Capture: decisions are seldom recorded at the moment they are made. Practitioners value design rationale but find it hard to record (Tang et al., 2006), and the decision records kept by people are few (Buchgeher et al., 2023), while AI tools now reach decisions within a conversation and keep no record of them.
2. Delivery: a decision must reach the next tool, in another program, at the point where it matters. Similarity search may not return a decision worded unlike the task (Weller et al., 2024), and a longer context does not guarantee that the model attends to it (Laban et al., 2026).
3. Currency: memories that only grow hand over decisions that have since been reversed (Zhou et al., 2026), and in two audited projects 20 to 25% of architectural decisions had stale evidence within two months (Gilda & Gilda, 2026).
4. Obedience: a model given a decision does not always keep it. Coding agents followed the instructions in their context files 59.8% of the time on average (Voria et al., 2026), and the best model on an agentic benchmark met only 59.8% of the constraints set for it (Qi et al., 2025).
5. Safety: a memory that AI tools read is also a route for attack, since instructions hidden in stored text can take over a model (Greshake et al., 2023) and a few planted records can steer an agent (Chen et al., 2024).

## 2.3 Related Works

This section examines five systems that give AI tools a memory, chosen to cover the main approaches reviewed in Section 2.2: instruction files, memory layers, temporal knowledge graphs, agent memory blocks and decision records. Each is described in terms of what it does, the technology behind it and its reported performance, and the gaps it leaves.

### 2.3.1 Claude Code Project Memory and Context Files

Claude Code keeps a project's memory in CLAUDE.md files that it reads at the start of every session, and other coding agents use similar files such as AGENTS.md and Cursor rules (Anthropic, 2026b). These context files are the most widely used memory for coding agents. Chatlatanagulchai et al. (2025) studied 2,303 of them from 1,925 repositories, a study of Claude Code examined 253 CLAUDE.md files (Chatlatanagulchai et al., 2026), and Sun et al. (2026) found about 12,110 Cursor rules files in 11,427 GitHub repositories. Figure 2.1 shows an example.

!fig figures/related/fig2-agent-readme.png | Figure 2.1: An example of a context file for a coding agent. Source: Chatlatanagulchai et al. (2025) | 5.4

The files are plain Markdown, written mostly by developers and loaded whole into the model's context. Chatlatanagulchai et al. (2025) found that they described testing in 75.9% of cases, implementation details in 70.8% and architecture in 68.1%, but security in only 14.8%, and that 67% of Claude Code files were edited in more than one commit. Their effect on results is uncertain: Gloaguen et al. (2026) found that context files did not generally raise the success rate of coding agents and increased the cost of running them by more than 20%.

The gaps are significant for keeping decisions. A context file holds only what a person remembered to write, records no reason unless someone writes one, and is read only by tools working in that repository. Agents followed its instructions 59.8% of the time on average, with 37.3% of instructions never followed (Voria et al., 2026), and when a file went stale they followed it over the code in 90.1% of their choices (X. Xu & Wu, 2026). Nothing marks a rule when the code it describes changes.

### 2.3.2 Mem0

Mem0 is a memory layer for AI agents that keeps what it learns from conversations and gives it back in later sessions (Chhikara et al., 2025). As a conversation goes on, it extracts the facts it judges salient, compares each with what it already holds, and adds, updates or deletes memories accordingly. When a later request arrives, it retrieves the memories most relevant to it and passes them to the model. Figure 2.2 shows Mem0 as a layer between an application and its model.

!fig figures/related/fig2-5-mem0.png | Figure 2.2: The Mem0 memory layer within an agent stack. Source: Mem0 documentation, https://docs.mem0.ai | 6.0

The system uses a language model in two phases: an extraction phase that draws candidate facts from recent messages, and an update phase that decides whether each fact should be added, should update or delete an existing memory, or should be ignored. A graph variant also stores the relationships between entities. On the LoCoMo benchmark of long conversations, Mem0 achieved a 26% relative improvement over OpenAI's memory on a score judged by a language model, with a 91% lower latency and more than 90% fewer tokens than passing the full conversation to the model (Chhikara et al., 2025).

As a memory of decisions, Mem0 has three gaps. A decision is kept only if the extractor judges it salient, and nothing requires its reason or the rejected options to be kept with it. Memories are returned by similarity, so a decision worded unlike the task may not be returned, and an update or deletion loses the record of what was replaced. Mem0 also keeps facts drawn from conversation rather than decisions tied to the files they govern, and it does not check new work against what was decided.

### 2.3.3 Zep and Graphiti

Zep is a memory service for AI agents built on Graphiti, an engine that stores memory as a temporal knowledge graph (Rasmussen et al., 2025). Conversations and business data are taken in as episodes, from which a language model extracts entities and the relationships between them. Each relationship is stored as an edge that records when it became true and when it stopped being true, so an agent can be told what was known at a given time.

The distinctive technology in Zep is its handling of contradiction. When a new fact arrives, a language model compares it with related facts already in the graph, and if they conflict, the old edge is marked invalid from the time the new one became valid rather than being deleted. Figure 2.3 shows a fact invalidated and replaced in this way. Zep scored 94.8% on the deep memory retrieval benchmark against 93.4% for MemGPT, and on LongMemEval it improved accuracy by up to 18.5% with about 90% lower latency than a full-context approach (Rasmussen et al., 2025).

!fig figures/related/fig2-zep-graphiti.png | Figure 2.3: A fact invalidated and replaced over time in Graphiti, the engine of Zep. Source: Graphiti repository, https://github.com/getzep/graphiti | 5.6

Zep keeps memory current better than any other system reviewed, but it was designed for facts about users and businesses rather than decisions about work. Its facts are extracted automatically, so a decision's reason is kept only if the extractor captures it, and no fact is tied to the code files it concerns. It needs a graph database and a language model to run, and it does not check a tool's work against what is stored.

### 2.3.4 Letta

Letta is an agent framework that grew out of MemGPT (Packer et al., 2023) and gives agents a memory they manage themselves (Letta, 2025). Its central idea is the memory block: a labelled section of the agent's context, such as a block about the person or about the task, that stays in view at every step. Agents read and edit their blocks through memory tools, and the same block can be attached to several agents so that they share it. Figure 2.4 shows the virtual context architecture from which this design developed.

!fig figures/related/fig2-1-memgpt.png | Figure 2.4: The MemGPT virtual context architecture on which Letta builds. Adapted from Packer et al. (2023) | 6.0

The technology treats the context window as a resource that the agent manages, paging information between always-visible blocks and an outside store as the conversation demands. Packer et al. (2023) showed that this let a model with a fixed context sustain conversations and analyse documents well beyond the length of its window, and Letta describes memory blocks as a way of breaking the context into purposeful units that agents keep up to date (Letta, 2025).

Letta's memory works within its own framework: blocks are shared between Letta agents, not with a coding tool or workflow running elsewhere. A block holds free text, so a decision's reason, the files it governs and what replaced it are kept only if the agent writes them, and nothing marks a block when the work it describes changes or checks new work against it.

### 2.3.5 Architecture Decision Records

An architecture decision record (ADR) is a short document that records one design decision with its context, the decision itself, its status and its consequences (Nygard, 2011). An accepted record is not edited; when a decision changes, a new record supersedes it, so the history of decisions is kept (Kunce & Goby, 2022). Teams use ADRs to explain a system to newcomers and to review changes against what was decided. Figure 2.5 shows such a review: if a change violates a record, the reviewer links the record and the author updates the change.

!fig figures/related/fig2-adr-aws.png | Figure 2.5: Using an architecture decision record to review a change. Source: Kunce and Goby (2022) | 4.6

ADRs are kept as plain files beside the code and follow a template, most often Nygard's (Buchgeher et al., 2023). In practice they helped teams follow through on decisions (Keeling, 2022) and improved documentation culture and knowledge transfer, though where the records were stored strongly affected whether they were used (Ahmeti et al., 2024). Language models have recently checked code against ADRs with good accuracy for decisions that can be read from the code (Su et al., 2026). Their adoption remains low: on GitHub, about half of the repositories that used ADRs held only one to five of them (Buchgeher et al., 2023).

ADRs provide much of what a decision memory needs, a decision with its reason and a way to retire it without losing it, but they are written by people after the decision and kept in one repository. They are checked at human review rather than before an AI tool reports its work as done, and an AI tool that does not open them never learns of the decisions they hold.

Table 2.1 summarises the strengths and critical gaps of the five systems.

!tab Table 2.1: Comparative analysis of the reviewed systems
!widths 1.6,2.3,2.4
| System | Strengths | Critical gaps |
| Claude Code project memory and context files | Simple Markdown, read at every session start, versioned with the code | Written by people; one repository; often not followed; no reasons or staleness |
| Mem0 | Learns from conversations; large gains on long conversations | Reason not required; returned by similarity; updates lose history; no check of work |
| Zep and Graphiti | Marks replaced facts invalid and keeps their history | Facts extracted automatically; not tied to files; needs a server; no check of work |
| Letta | Memory always in view; blocks shared between agents | Only within Letta; free text without reasons; no staleness or check |
| Architecture decision records | Decision with reason; superseded, never lost | Written by people after the fact; one repository; checked only at human review |

## 2.4 Gaps in Related Works

A critical synthesis of the five reviewed systems reveals persistent gaps in keeping decisions for AI tools, which this study aims to address.

1. Decisions are not captured when they are made. Context files and ADRs depend on people writing them after the fact (Section 2.3.1; Section 2.3.5), while Mem0 and Zep extract facts automatically and may miss a decision or its reason (Chhikara et al., 2025; Rasmussen et al., 2025). None requires a decision to be kept with its reason and the options it rejected.

2. Decisions do not reach every tool. Context files and ADRs are read only by tools working in one repository, Letta shares blocks only between its own agents, and Mem0 returns memories only when they resemble the request (Table 2.1). A decision reached in a cloud coding tool therefore seldom reaches a local model or a workflow agent working on the same material.

3. Decisions are not tied to what they govern. Only Zep marks a replaced fact as invalid, and none of the systems knows when the code that a decision concerns has changed, although decision evidence goes stale within months (Gilda & Gilda, 2026).

4. Work is not checked against decisions. No reviewed system checks an AI tool's change against the decisions it touches before the work is reported as done; ADRs are checked at human review, after the fact (Kunce & Goby, 2022), even though agents often fail to follow the instructions they are given (Voria et al., 2026).

5. Shared memory leaves the person's computer. The systems that share memory across tools rely on a hosted service or a server, while a person working on private material may need the memory to stay on their own device (J. Xu et al., 2024).

Key unmet need: a private memory on the person's own computer in which AI tools record decisions with their reasons as they make them, which hands those decisions to every local and cloud tool, knows when they are out of date, and checks new work against them, remains absent; this study directly targets that gap.

## 2.5 Conceptual Framework

### 2.5.1 Definition and Purpose

The conceptual framework of this study shows, visually and in words, how Burrow keeps the decisions made with one AI tool and makes the tools that follow keep them. It brings together the variables, processes and relationships drawn from the literature review in Sections 2.2 to 2.4, and it links them to the objectives of the study, so that it served as the bridge between the review and the design in Chapter 4.

### 2.5.2 Key Variables

The input variables are the person's work with AI tools, in which decisions are reached, and the person's material, the notes, documents and linked code that those decisions concern. The processing variables are the five steps of the engine: keeping a decision with its reason and files, handing decisions over to each tool that connects, watching for changed files and contradicting decisions, checking a change before the work is finished, and sharing decisions within a team. The output variables are whether the next tool keeps the decision, whether a tool can carry the work on from where it stopped, and the verdict on each change, measured together with whether the right material was found and how long each step took.

### 2.5.3 Theoretical Foundation

The framework builds on two bodies of work. From software architecture it takes the view that a design is a set of decisions, each with its rationale, and that the rationale vaporises unless it is kept as a first-class record (Jansen & Bosch, 2005; Tang et al., 2006). From research on memory for language models it takes the view that what a model reads should be chosen, few and timely, because more context is not better context (N. F. Liu et al., 2024; Laban et al., 2026), and that stored knowledge must be revoked explicitly when it is replaced (Zhou et al., 2026). Design Science Research frames the whole, since an artefact is built to address the problem and then evaluated against it (Hevner et al., 2004).

### 2.5.4 Visual Representation

Figure 2.6 shows the conceptual framework as a flow of the system: the inputs at the top, the five processing steps of the engine in the middle, and the outputs at the bottom, with a feedback loop by which each new decision joins the Ledger.

!fig figures/v5/framework.png | Figure 2.6: Conceptual framework of the study, drawn by the author | 6.27

### 2.5.5 Relationships between Variables

A decision is kept only if the tool records it with a reason, so what is kept depends on the tool and on Burrow refusing a decision without one. What the next tool receives depends on what was kept and on how it is handed over, and whether the tool then keeps to it depends on the model as well as on the memory. The check closes that last gap by holding a change that touches a decision whatever the model chooses. Through the feedback loop the Ledger grows with use, which makes handing over few and relevant decisions more important over time.

### 2.5.6 Flexibility and Refinement

The framework was expected to change as the system was tested with real AI tools, and it did. Early runs showed that decisions handed over without their reasons were kept in letter but defeated in purpose, and that some programs never showed Burrow's instructions to their model, which led to keeping reasons with every decision and to sending decisions with a tool's first result. Chapter 5 reports these refinements.

### 2.5.7 Narrative Flow

On Monday a person settles with Claude Code that payments are matched to tickets by account reference only, because a conductor often pays for a whole group from one phone. Claude Code keeps the decision in Burrow with that reason and the rejected options, citing the matching code. On Wednesday a different program, running a local model, connects and is handed the decision before it starts. Asked to handle unmatched payments, it writes a fallback that matches by phone and amount, and when it tries to finish, Burrow judges that the change breaks the decision and holds it. The program tells the person which decision it went against and puts the code back, and any new decision the person settles joins the Ledger for the next tool.

### 2.5.8 Alignment with the Objectives

The framework is aligned with the design and testing objectives of the study. The processing steps address the fourth objective, since each became a group of requirements in Chapter 4, and the outputs address the fifth objective, since each became a measure in the evaluation of Chapter 5: whether a decision was kept, whether work was carried on, and whether the verdict on a change was right.
