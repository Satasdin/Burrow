# Chapter 2:  Literature Review

## 2.1 Introduction

Decisions made while working with AI tools, and the reasons behind them, are easily lost between one session and the next and between one tool and another. This chapter reviews the literature on that problem, guided by the first three specific objectives. The review looked at works published mostly between 2022 and 2026 on memory for AI agents, AI coding tools, retrieval and long contexts, and the recording of design decisions in software engineering, together with a few older works that introduced ideas this study relies on. Section 2.2 reviews the current state of decision memory for AI tools and its key challenges. Section 2.3 examines four related systems, Section 2.4 discusses the gaps they leave, and Section 2.5 presents the conceptual framework of the study.

## 2.2 Current State of Decision Memory for AI Tools

### 2.2.1 Decisions and Their Reasons in Software Work

Software engineering has treated the loss of design decisions as a problem for many years. Bosch (2004) argued that the main weakness of software architecture was that design decisions had no first-class representation, so that the architecture recorded what had been built but not why. Jansen and Bosch (2005) named the consequence knowledge vaporisation: once the reasons behind a design are forgotten, later changes violate earlier decisions without anyone noticing. Tang et al. (2006) surveyed 81 practitioners and found that they considered design rationale valuable and used it often, yet faced real barriers when trying to record it. The loss also follows people. In a study of Chrome and a project at Avaya, Rigby et al. (2016) found that developers who left a project took with them the knowledge of the decisions they had made, and that the resulting losses were more than three times larger than expected.

Where rationale is recorded, it is often recorded informally. Dhaouadi et al. (2024) found that 98.9% of the commit messages in one part of the Linux kernel contained some rationale, which shows that developers do explain their choices but scatter the explanations across places that a later reader must know to search. The more structured response has been the architecture decision record, discussed as a related work in Section 2.3.4. Decisions in software work are therefore kept, when they are kept at all, by people, after the fact, and in places that the next person or tool may never read.

### 2.2.2 Memory in Today's AI Tools

AI tools now take part in making and carrying out decisions. A coding assistant such as Claude Code reads a codebase, edits it and runs its tests (Anthropic, 2026a), and benchmarks such as SWE-bench measure such agents on thousands of real GitHub issues (Jimenez et al., 2024). The Model Context Protocol (MCP) has become a common way for these programs to reach outside services: a program discovers the tools a server offers and calls them, so one service can serve many AI programs (Model Context Protocol, 2026; Hou et al., 2026). Each program still starts a session only with what its maker chooses to supply, which has made context engineering, the careful choice of what enters a model's limited context, a discipline of its own (Rajasekaran et al., 2025).

Several approaches give these tools a memory. MemGPT treated the model's context as main memory and an outside store as disk, and paged information between them as an operating system does (Packer et al., 2023). Retrieval-augmented generation fetches passages from an index for each request (Lewis et al., 2020), usually from a vector database that returns the passages closest in meaning to the request. Retrieval fails in well-known ways, however. The relevant passage may be missing, ranked too low, cut from the context or present but unused (Barnett et al., 2024), and decisions are a hard case because they are often written as negations, which most retrieval models rank no better than random (Weller et al., 2024). Giving a model more context is not a reliable substitute either. Models use information at the start and end of a long context better than in the middle (N. F. Liu et al., 2024), their performance falls as the input grows (Hong et al., 2025), and they lose 39% of their performance on average when instructions arrive over several turns (Laban et al., 2026).

A memory must also stay current. When retrieved content conflicted with what six leading models already knew, the models adopted the incorrect content more than 60% of the time (Wu, Wu, & Zou, 2024), and such conflicts between context and memory are now a recognised class of failure (R. Xu et al., 2024). Zhou et al. (2026) showed that memories which only append, or which simply keep the latest write, scored 0.21 on reversed facts, below the 0.31 of having no memory at all, while revoking the old fact explicitly scored 0.95. Evidence also ages quickly; in two projects audited by Gilda and Gilda (2026), 20 to 25% of architectural decisions had stale evidence within two months.

### 2.2.3 Key Challenges in Existing Works

While AI tools can now be given a memory, several challenges remain for keeping decisions. First, decisions are seldom captured at the moment they are made: practitioners struggle to record rationale (Tang et al., 2006), and records kept by people are few (Buchgeher et al., 2023). Second, a decision must reach the next tool, in another program, at the point where it matters, and neither similarity search nor a longer context guarantees this (Weller et al., 2024; Laban et al., 2026). Third, memories that only grow hand over decisions that have since been reversed, and nothing marks a decision whose evidence has changed (Zhou et al., 2026; Gilda & Gilda, 2026). Fourth, a model that is given a decision does not always follow it: coding agents followed the instructions in their context files 59.8% of the time on average (Voria et al., 2026), and the best model on an agentic benchmark met only 59.8% of the constraints set for it (Qi et al., 2025). Finally, a memory that AI tools read is also a route for attack, since instructions hidden in stored text can take over a model (Greshake et al., 2023) and a few planted records can steer an agent (Chen et al., 2024). In conclusion, missing capture, unreliable delivery, stale content, weak obedience and exposure to planted instructions together limit how well current memory keeps decisions for AI tools.

## 2.3 Related Works

### 2.3.1 Mem0

Mem0 is a memory layer for AI agents that keeps what it learns from conversations and gives it back in later sessions (Chhikara et al., 2025). As a conversation goes on, Mem0 extracts the facts it judges salient, compares each with what it already holds, and adds, updates or deletes memories accordingly. When a later request arrives, it retrieves the memories most relevant to it and passes them to the model, so that an assistant can remember a user's preferences or earlier answers without being given the whole history. Figure 2.1 shows Mem0 as a layer between an application and its model.

!fig figures/related/fig2-5-mem0.png | Figure 2.1: The Mem0 memory layer within an agent stack. Source: Mem0 documentation, https://docs.mem0.ai | 6.0

The system uses a language model in two phases: an extraction phase that draws candidate facts from recent messages, and an update phase that decides for each fact whether to add it, update an existing memory, delete a contradicted one or do nothing. A graph variant also stores the relationships between entities. On the LoCoMo benchmark of long conversations, the authors reported a 26% relative improvement over OpenAI's memory on a score judged by a language model, together with a 91% lower latency and more than 90% fewer tokens than passing the full conversation to the model (Chhikara et al., 2025).

Despite these strengths, Mem0 has limits as a memory of decisions. A decision is kept only if the extractor judges it salient, and nothing requires its reason or the options that were rejected to be kept with it. Memories are returned by similarity to the request, so a decision worded unlike the task may not be returned, and when a fact is updated or deleted the record of what it replaced is lost. Mem0 also keeps facts drawn from conversation rather than decisions tied to the files they govern, and it has no means of checking new work against what was decided.

### 2.3.2 Zep and Graphiti

Zep is a memory service for AI agents built on Graphiti, an engine that stores memory as a temporal knowledge graph (Rasmussen et al., 2025). Conversations and business data are taken in as episodes, from which a language model extracts entities and the relationships between them. Each relationship is stored as an edge that records when it became true and when it stopped being true, so that the agent can be told not only what is known but what was known at a given time.

Zep's distinctive feature is how it handles contradiction. When a new fact arrives, a language model compares it with related facts already in the graph, and if they conflict, the old edge is marked invalid from the time the new one became valid instead of being deleted. Figure 2.2 shows a fact invalidated and replaced in this way. Rasmussen et al. (2025) reported 94.8% on the deep memory retrieval benchmark against 93.4% for MemGPT, and on LongMemEval an improvement of up to 18.5% in accuracy with about 90% lower latency than a full-context approach.

!fig figures/related/fig2-zep-graphiti.png | Figure 2.2: A fact invalidated and replaced over time in Graphiti, the engine of Zep. Source: Graphiti repository, https://github.com/getzep/graphiti | 5.6

Zep is the related system that best keeps memory current, but it was designed for facts about users and businesses rather than decisions about work. Its facts are extracted automatically, so a decision's reason is kept only if the extractor captures it, and nothing ties a fact to the code files it concerns. It needs a graph database and a language model to run, and, like Mem0, it does not check a tool's work against what is stored.

### 2.3.3 Context Files for Coding Agents

Context files are Markdown files kept in a code repository that a coding agent reads at the start of every session, such as CLAUDE.md for Claude Code, AGENTS.md for several other agents, and rules files for Cursor (Anthropic, 2026b). They are the most widely used memory for coding agents. Chatlatanagulchai et al. (2025) studied 2,303 such files from 1,925 repositories, a study of Claude Code examined 253 CLAUDE.md files (Chatlatanagulchai et al., 2026), and Sun et al. (2026) found about 12,110 Cursor rules files in 11,427 GitHub repositories. Figure 2.3 shows an example.

!fig figures/related/fig2-agent-readme.png | Figure 2.3: An example of a context file for a coding agent. Source: Chatlatanagulchai et al. (2025) | 5.4

The files are written mostly by developers and describe how to build and test the project, implementation details and architecture: Chatlatanagulchai et al. (2025) found testing in 75.9% of files, implementation details in 70.8% and architecture in 68.1%, but security in only 14.8%. They change often, with 67% of Claude Code files edited in more than one commit. Their effect on results is uncertain, however. Gloaguen et al. (2026) found that context files did not generally raise the success rate of coding agents and increased the cost of running them by more than 20%.

Context files have clear limits as a memory of decisions. They hold only what a person remembered to write and are kept in one repository, so tools outside that repository never read them. Agents followed their instructions 59.8% of the time on average, with 37.3% of instructions never followed (Voria et al., 2026), and when a file went stale they followed it over the code in 90.1% of their choices (X. Xu & Wu, 2026). Nothing in a context file records why a rule was made or marks it when the code it describes changes.

### 2.3.4 Architecture Decision Records

An architecture decision record (ADR) is a short document that records one design decision with its context, the decision itself, its status and its consequences (Nygard, 2011). An accepted record is not edited; when a decision changes, a new record supersedes it, so the history of decisions is kept (Kunce & Goby, 2022). ADRs are used to explain a system to newcomers and to review changes against what was decided. Figure 2.4 shows how a team uses an ADR to review a change: if the change violates the record, the reviewer links the record and the author updates the change.

!fig figures/related/fig2-adr-aws.png | Figure 2.4: Using an architecture decision record to review a change. Source: Kunce and Goby (2022) | 4.6

In practice, ADRs help teams follow through on decisions (Keeling, 2022), and an action research study found that they improved documentation culture and knowledge transfer, while showing that where records are stored strongly affects whether they are used (Ahmeti et al., 2024). Their adoption remains low: on GitHub, about half of the repositories that used ADRs held only one to five of them (Buchgeher et al., 2023). Language models have recently been used to check code against ADRs, with good accuracy for decisions that can be read from the code (Su et al., 2026).

ADRs provide much of what a decision memory needs: a decision with its reason and a way to retire it without losing it. They are, however, written by people after the decision, kept in one repository, and checked at human review rather than before an AI tool reports its work as done. An AI tool that does not open the records never learns of the decisions they hold.

Table 2.1 compares the four related systems, together with managed context as in MemGPT and a vector database, on what this study needs of a memory of decisions.

!tab Table 2.1: Comparison of related systems as a memory of decisions for AI tools
!widths 1.15,1.0,1.0,0.9,1.1,1.0,0.95
| System | Shared across tools | Who records | Reason kept | How it is delivered | Knows it is out of date | Checks new work |
| MemGPT | Within one agent | The agent | No | Paged into context | No | No |
| Mem0 | Yes, by plugin | Automatic extraction | Not required | By similarity | Overwrites or deletes | No |
| Zep and Graphiti | Through a server | Automatic extraction | Not required | By search | Yes, for facts | No |
| Context files | Coding tools of one repository | The person | If written | Read at session start | No | No |
| Architecture decision records | One repository | The person | Yes | When looked up | Superseded by hand | At human review |
| Vector database | Any application | An ingest pipeline | No | By similarity | No | No |

## 2.4 Gaps in Related Works

The reviewed works show that no existing system keeps decisions for AI tools in the way the problem requires. The memory layers, Mem0 and Zep, keep facts that a language model extracts from conversation, so whether a decision and its reason are kept depends on the extractor, and what is kept is returned by similarity or search rather than when it governs the task (Chhikara et al., 2025; Rasmussen et al., 2025). Zep marks a replaced fact as invalid, which Mem0 does not, but neither ties a decision to the files it concerns or knows when those files change.

The approaches used in software teams have the opposite problem. Context files and ADRs are written and kept by people, so they hold only what someone chose to record, and they live in one repository where tools outside it never read them (Nygard, 2011; Chatlatanagulchai et al., 2025). Even when an agent reads a context file, it may not follow it, and it may follow a stale one over the code (Voria et al., 2026; X. Xu & Wu, 2026).

None of the reviewed systems checks an AI tool's work against the decisions it touches before the work is reported as done; ADRs are checked at human review, after the fact (Kunce & Goby, 2022). The systems that share memory across tools also rely on a hosted service or a server, while a person working on private material may need the memory to stay on their own computer (J. Xu et al., 2024). These gaps point to the need for a private memory on the person's computer in which AI tools record decisions with their reasons as they make them, which hands those decisions to every later tool, knows when they are out of date, and checks new work against them.

## 2.5 Conceptual Framework

Burrow is designed so that a decision reached with one AI tool is kept and honoured by every tool that comes after it. When a person settles something with a tool, for example that payments are matched by account reference only because a conductor often pays for a whole group from one phone, the tool keeps that decision in Burrow with its reason, the options that were rejected and the files it rests on. The person's notes, documents and code sit beside it in the same vault on their own computer.

When another tool connects, local or cloud, Burrow hands it the decisions in force before it starts, tells it where the last session stopped, and attaches the relevant decisions to whatever it looks up. While the work goes on, Burrow watches the files each decision rests on and marks a decision to be checked again if they change, and it catches a new decision that contradicts an old one.

When the tool tries to finish, Burrow checks the change against each decision it touches and holds a change that breaks one, so that the tool must undo it or the person must overturn the decision. The outputs are a decision kept by the next tool, work carried on from where it stopped, and a verdict on each change, and every new decision joins the Ledger for the tools that follow. Figure 2.5 shows this flow from inputs, through the five steps of the engine, to its outputs.

!fig figures/v5/framework.png | Figure 2.5: Conceptual framework of the study, drawn by the author | 6.27
