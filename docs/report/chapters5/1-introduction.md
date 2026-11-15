# Chapter 1:  Introduction

## 1.1 Background Information

Language models have become the foundation of modern conversational software, powering assistants that answer questions, summarise documents, write code and help with everyday tasks. The most capable of these models run as cloud services on specialised hardware, and their capability comes at a cost: every request travels over a network, personal data leaves the user's device, the service fails without connectivity, and each request carries a price. Empirical work on scaling has shown that a model's performance improves predictably with its size, training data and compute (Kaplan et al., 2020), which is why the strongest models are also the largest and the least practical to run locally.

A parallel movement has formed around small language models that run directly on consumer hardware such as laptops. Open-weight families such as Qwen2.5 (Yang et al., 2024), Llama 3 (Grattafiori et al., 2024) and Phi-3 (Abdin et al., 2024), the 2026 releases Gemma 4 (Gemma Team, 2026) and Qwen3.5 (Qwen Team, 2026), and the foundation model that Apple ships on its own devices (Gunter et al., 2024) show that useful language ability now fits in the memory of an ordinary computer. Running a model locally gives answers with low latency, keeps private data on the machine, works offline and costs nothing per request (J. Xu et al., 2024), although a survey of 70 small models confirmed that they remain weaker than their larger counterparts (Lu et al., 2024).

The most consistent of those weaknesses is factual knowledge. Mallen et al. (2023) showed that language models struggle with less popular facts, that retrieving external text helps most in exactly those cases, and that making models bigger barely improves this long tail, and Kandpal et al. (2023) traced the cause to how often a fact appears in the training data. A person's own notes, documents and code are the extreme case, because no public model has seen them. If much of the gap between small and large models is missing knowledge rather than missing reasoning, then supplying the right knowledge from outside the model, at the right time, might recover much of that gap without changing the model at all.

A second weakness is shared by small and large models alike: they keep nothing between sessions. A person now often works with several AI tools on the same project, for example a cloud coding assistant alongside a local model kept for private material, and each tool starts from what its own program supplies (Anthropic, 2026b). What was settled with one tool, and why, is therefore lost to the next, which may bring back an option that was already rejected. Software engineering has long known this problem as knowledge vaporisation, the loss of the reasons behind design decisions (Jansen & Bosch, 2005), and the Model Context Protocol (MCP) now gives AI tools a common way to reach an outside service (Model Context Protocol, 2026). This study therefore built a single memory on the person's own computer that both local and cloud models can reach, holding the person's knowledge and the decisions made with the tools.

## 1.2 Problem Statement

Users who want a private, offline and low-cost assistant must accept a small on-device model, and with it a marked drop in capability, most visibly on questions that need knowledge the model has not memorised. The standard remedies do not fit this setting. A larger model no longer fits on the device, and fine-tuning a small model needs computing resources that ordinary users lack and must be repeated whenever the knowledge changes (Soudani et al., 2024). Retrieval offers a third path, since a frozen model given relevant text has matched models 25 to 50 times larger (Borgeaud et al., 2022; Izacard et al., 2023), but irrelevant retrieved text can also lower accuracy (Shi et al., 2023).

The problem grows when a person uses several models. Each AI tool, local or cloud, starts from what its own program supplies, so decisions reached with one tool and their reasons are lost to the next. Even written instructions are not reliably followed: coding agents followed the instructions in their context files only 59.8% of the time on average (Voria et al., 2026). Without a shared memory, a local model lacks the knowledge a cloud model has, and every model lacks the work and decisions of the others, so a person must choose between privacy and capability and must repeat their reasons to each new tool.

This study developed Burrow, a local vault that gives local and cloud language models one shared memory. Burrow keeps the person's notes, documents and code on their own computer, together with a ledger of the decisions made with AI tools, each with its reason and the files it rests on. Any model reaches it through MCP, and Burrow decides what to supply, hands over earlier decisions, and checks new work against them, while the models themselves are never changed.

## 1.3 Objectives

This section states the general objective of the study and breaks it down into the specific objectives that guided the work.

### 1.3.1 General Objective

The general objective of this study was to design, develop and validate a local memory vault that gives local and cloud language models one shared memory of a person's knowledge and decisions, and to measure how far it narrows the gap between them.

### 1.3.2 Specific Objectives

i) To investigate the capability gap between local and cloud language models, together with existing memory, retrieval and decision-keeping techniques, so as to establish their applicability and limitations for a memory shared by local and cloud models.
ii) To design a local memory vault comprising an index of the person's material, a ledger of decisions kept with their reasons, and a protocol through which local and cloud models read from and write to it.
iii) To develop the designed vault on a consumer laptop, using an embedded database for the index and plain files for the ledger.
iv) To evaluate how much of the knowledge gap between a local model and a cloud model the vault closes, and at what cost in time.
v) To evaluate whether models connected to the vault keep earlier decisions and carry on earlier work started by other models.

## 1.4 Research Questions

i) What is the capability gap between local and cloud language models, and how applicable and limited are existing memory, retrieval and decision-keeping techniques for a memory shared by both?
ii) How can a local memory vault be designed with an index of the person's material, a ledger of decisions with their reasons, and a protocol for local and cloud models?
iii) How can the designed vault be developed on a consumer laptop using an embedded database and plain files?
iv) How much of the knowledge gap between a local model and a cloud model does the vault close, and at what cost in time?
v) Do models connected to the vault keep earlier decisions and carry on earlier work started by other models?

## 1.5 Justification

The study matters for three audiences. For users, especially where data privacy is a serious concern, a more capable local model means useful AI that keeps personal data on their own computer and costs nothing per request; in Kenya, personal data is protected by law (Data Protection Act, 2019). For people and teams who use several AI tools on the same work, a shared memory means that what was settled with one tool, and why, reaches the next, instead of being repeated to every tool or broken by it. For the research community, the study contributes a measured account of how far a local memory narrows the gap between local and cloud models, and evidence on whether models keep decisions that other models made. This work helps people who want private and capable AI tools by giving every model they use one memory of their knowledge and decisions, while advancing research on memory for language models.

## 1.6 Scope

The target device was a consumer laptop of the kind a person already owns, an Apple MacBook Pro with Apple silicon, on which Burrow, the local models and all timings ran. The local models were open-weight models run through Ollama, with Gemma 4 12B as the main model, and the cloud models were Claude models reached through Anthropic's services. The material in the vault was the person's own Markdown notes, documents and linked code. The evaluation used 120 English knowledge questions on Kenyan data protection law, software released in 2026 and a private project, 50 reasoning problems from a public benchmark, and coding tasks with hidden tests on a fixture project written for the study. The AI tools connected through MCP were Claude Code, OpenCode, OpenClaw, Hermes Agent, an n8n workflow and the llama.cpp server. The system delivered was the Burrow vault with its command-line program, MCP server and desktop application. The work ran from June to November 2026, and it did not cover mobile phones, operating systems other than macOS, languages other than English, or use by people other than the developer.

## 1.7 Limitations and Delimitations

### 1.7.1 Limitations

The study operated under constraints that shape how the findings should be interpreted. First, timings measured on one laptop may differ on other machines, so the device results are indicative rather than universal. Second, the cloud models are hosted services whose behaviour may change over time, which affects both the ceiling used to measure the gap and the behaviour of the cloud tools. Third, whether a model follows a decision it has been given depends on the model and not on the memory. Fourth, the study was limited by the cost and time of running real AI tools, which restricted the number of runs per condition, and no group of real users was available.

### 1.7.2 Delimitations

The delimitations respond directly to those constraints. To address the hardware limitation, the study fixed one laptop as the target device and reported its specification with every timing. To address changing cloud models, it recorded the exact model and tool version of every run and kept the full transcript. To address obedience, it measured separately whether a decision reached a model and whether the model kept it, and added a check that holds a change touching a decision whatever the model chooses. To address the cost of runs, it fixed its scoring before the main comparisons, reported every result as a count with its sample size, and used scripted tasks with hidden tests in place of real users, referring to the simulated tools as agents rather than participants. To keep the project focused, the study did not train or fine-tune any language model, did not port Burrow to mobile phones, and did not evaluate languages other than English.
