# Chapter 1:  Introduction

## 1.1 Background Information

Artificial intelligence (AI) tools built on large language models have moved quickly from answering questions to doing work. Chat assistants were followed by coding assistants that read a project, change its files and run its tests, and by agents that answer email or route requests inside automated workflows (Anthropic, 2026a; Jimenez et al., 2024). In 2024 the Model Context Protocol (MCP) gave these programs a common way to reach outside services, so that one service can now be used by many AI tools (Model Context Protocol, 2026; Hou et al., 2026). Their use is now widespread. According to the Stack Overflow Developer Survey of 2025, 84% of developers used or planned to use AI tools in their work and about half of professional developers used them daily, although 66% named output that was almost right but not quite as their main frustration (Stack Overflow, 2025). A person also rarely works with one tool. A project may be planned in a cloud assistant, edited by a coding agent and later handed to a smaller model that runs on the person's own computer, since open models such as Gemma and Qwen now run on an ordinary laptop and offer lower latency, data that stays on the device and personalisation (J. Xu et al., 2024).

Each of these tools begins its work with little knowledge of what came before. A language model keeps nothing between requests, so what it knows about a project is only what its program supplies at the start of a session. Products have added memory, but each keeps its own: Claude Code, for example, reads a project's instructions from files that the person writes (Anthropic, 2026b). Within a single long session, models still lose track. Laban et al. (2026) measured an average drop of 39% in performance when the instructions for a task were spread over several turns instead of being given at once, and Wu et al. (2025) found that commercial assistants lost about 30% of their accuracy on information that had to be remembered across a sustained interaction.

What is lost most often is not a fact but a decision: what was settled, why, and which options were turned down. Software engineering has recognised this problem for two decades. Bosch (2004) argued that design decisions lacked a first-class representation, and Jansen and Bosch (2005) named the result knowledge vaporisation, in which the reasons behind a design disappear into the design itself. Tang et al. (2006) found that practitioners valued design rationale but faced barriers in recording it, and architecture decision records, proposed as a light way to keep each decision with its context (Nygard, 2011), remain rare on GitHub (Buchgeher et al., 2023). AI tools make the problem sharper, because decisions are now reached inside conversations with a model, across several programs and faster than any person documents them, and the next tool has no way of knowing what the last one agreed.

Addressing this gap matters in practice. When a decision is lost, the next tool may bring back an option that was rejected for a good reason, and the person must notice it and explain the reason again; in software work the returned option can become a change that undoes what a team had deliberately ruled out. The rationale of this study is that the AI tools themselves are best placed to record a decision, with its reason, at the moment it is made. Its hypothesis is that a private memory in which AI tools record their decisions with reasons, which hands those decisions to every tool that connects and checks new work against them, will help later tools keep earlier decisions and carry earlier work on. This study tested that hypothesis by building such a memory, called Burrow, and evaluating it with real AI tools.

## 1.2 Problem Statement

Ideally, a decision that a person reaches with one AI tool, together with its reason and the options it rejected, should guide every tool that later works on the same material, whether that tool runs in the cloud or on the person's own computer. However, the current reality falls short of this. Each AI tool starts from what its own program supplies, memory features are tied to one product (Anthropic, 2026b), and instruction files hold only what the person remembered to copy into them. Even written instructions are not reliably followed: coding agents followed the instructions in their context files only 59.8% of the time on average, and 37.3% of instructions were never followed (Voria et al., 2026). Retrieval does not close the gap, because it returns text that resembles a request, and most retrieval models rank a negated statement such as "never match payments by phone number" no better than random (Weller et al., 2024). As a result, the next tool brings back options that were already rejected, often with a convincing reason, and nothing warns the person; the risk is greatest for small local models, which bring the least knowledge of their own. This study developed Burrow, a private memory engine in which AI tools keep each decision with its reason and the files it rests on, and which hands those decisions to every tool that connects and checks new work against them.

## 1.3 Research Objectives

### 1.3.1 General Objective

To design and develop a private on-device memory engine that preserves decisions and their reasons across local and cloud AI tools.

### 1.3.2 Specific Objectives

i) To analyse the current state of memory for AI tools, together with the challenges of keeping decisions across sessions and tools.
ii) To study and analyse how existing memory systems for AI tools keep and deliver decisions.
iii) To review the gaps in existing memory systems for keeping decisions across local and cloud AI tools.
iv) To design and develop a private on-device memory engine that keeps decisions with their reasons, hands them to AI tools and checks new work against them.
v) To test and validate the memory engine with local and cloud AI tools.

## 1.4 Research Questions

i) What is the current state of memory for AI tools, and what challenges exist in keeping decisions across sessions and tools?
ii) How do existing memory systems for AI tools keep and deliver decisions?
iii) What gaps exist in current memory systems for keeping decisions across local and cloud AI tools?
iv) How can a private on-device memory engine be designed and developed to keep decisions with their reasons, hand them to AI tools and check new work against them?
v) How well does the memory engine help local and cloud AI tools find material, keep earlier decisions and carry earlier work on?

## 1.5 Justification

Research has established that language models lose information across sessions and within long conversations (Laban et al., 2026; Wu et al., 2025), and that decisions which are not recorded are lost to later work (Jansen & Bosch, 2005). AI tools have responded with memory features and instruction files: Claude Code reads a project's instruction files at the start of each session (Anthropic, 2026b), and thousands of open-source projects now keep such files for their coding agents (Chatlatanagulchai et al., 2025). Memory layers such as Mem0 extract facts from conversations and return them in later sessions (Chhikara et al., 2025).

These approaches leave important gaps. Each product's memory serves only that product, so a decision reached in one tool does not reach the next. Instruction files are written by people after the fact, and when they fall out of date, agents were found to follow them over the code in 90.1% of their choices (X. Xu & Wu, 2026). Memory layers keep what an extractor judges salient and return it by similarity, with no requirement that a decision's reason be kept and no check of later work against it (Chhikara et al., 2025).

As a result, people repeat their reasons to each new tool and still meet rejected options again, and in software work a returned option can break something that a team had deliberately ruled out. The risk is greatest for people who use small local models to keep their material private, which matters in Kenya, where personal data is protected by law (Data Protection Act, 2019).

This study addresses these gaps by building a memory in which the AI tools themselves record each decision with its reason as it is made, which hands those decisions to every tool that connects, local or cloud, and which checks new work against them before it is reported as done, all on the person's own computer. This work will help individuals and small teams who work with several AI tools, especially on private material, by keeping their decisions consistent across tools, while advancing research on memory for AI agents and on the recording of design decisions.

## 1.6 Scope

This study focused on keeping the decisions made during AI-assisted work on one person's computer, and later within a small team, within defined boundaries to ensure feasible completion.

The technical scope was the development of Burrow, a memory engine written in Swift for a Mac with Apple silicon, with its index in an embedded SQLite database, local models run through Ollama, a server for the Model Context Protocol, hooks and plugins for coding tools, and a desktop application.

The data scope was the person's own Markdown notes, documents and linked code folders. The evaluation used a vault of public documents on Kenyan data protection law, software released in 2026 and a private project, with 120 knowledge questions written from them and 50 reasoning problems from a public benchmark, together with Matatu, a fixture project written for the study with tasks and hidden tests.

The functional scope covered indexing and searching the person's material, keeping decisions with their reasons, handing them to connected AI tools, checking changes against them, and sharing them within a small team with the person's approval. The AI tools connected in the study were Claude Code, OpenCode, OpenClaw, Hermes Agent, an n8n workflow and the llama.cpp server.

The time scope ran from June to November 2026: the literature review and proposal in June, a first prototype of the memory with its search and first evaluation from July to October, and the Ledger of decisions, the connection to AI tools, the check of new work and the final evaluation in November.

The study did not address mobile phones, operating systems other than macOS, languages other than English, or use by real end users other than the developer.

## 1.7 Limitations and Delimitations

### 1.7.1 Limitations

Several factors beyond the study's control may affect its findings. The behaviour of the AI tools and their models is set by their makers and can change from one version to the next, so a run may not repeat exactly. Whether a model follows a decision it has been given depends on the model and not on the memory. Each run of a real AI tool takes several minutes and some cost money, which limited the number of runs that could be made for each condition. Finally, no group of real users was available within the project's timeline, so the system could not be tested by people other than the developer.

### 1.7.2 Delimitations

The study set deliberate boundaries to keep it focused and feasible. It fixed the exact version of every tool and model used and kept the full transcript of every run. It measured separately whether a decision reached a model and whether the model kept it, and it treated making a model obey as outside its aim, adding instead a check that holds a change touching a decision. It limited each comparison to a small number of runs, with the scoring fixed beforehand and every result reported as a count with its sample size. It used scripted tasks on a fixture project with hidden tests in place of real users, referred to the simulated tools as agents rather than participants, and made no claim about real users. It also confined the system to one operating system, macOS, and to English material.
