# Chapter 1:  Introduction

## 1.1 Background Information

Language models have become the foundation of modern AI assistants, which answer questions, summarise documents and write code, and by 2025, 84% of software developers used or planned to use AI tools in their work (Stack Overflow, 2025). The most capable of these models run as cloud services on a provider's hardware, because a model's performance improves predictably with its size and training data (Kaplan et al., 2020), which makes the strongest models also the largest and the least practical to run on a personal computer. Their capability comes at a cost: every request travels over a network and carries a price, and the person's data leaves their device. That data is often private: personal information appeared in 16% of real code-editing conversations with commercial chat models (Mireshghallah et al., 2024), and users trade their privacy for usefulness while often misunderstanding where their data goes (Zhang et al., 2024).

A parallel movement has formed around models that run on the person's own computer. Open-weight families such as Qwen2.5, Llama 3, Phi-3 and Gemma have been released in sizes that fit in the memory of an ordinary laptop (Abdin et al., 2024; Gemma Team, 2026; Grattafiori et al., 2024; Yang et al., 2024), and Apple ships a model that runs on its own devices (Gunter et al., 2024). Running a model locally keeps private data on the machine, works offline and costs nothing per request (J. Xu et al., 2024), which matters where personal data is protected by law, as it is in Kenya (Data Protection Act, 2019). A survey of the field confirms both the rapid progress of small models and their persistent weakness relative to large ones (Lu et al., 2024).

The most consistent of those weaknesses is knowledge, and every model, local or cloud, shares a second one: memory. Small models have memorised fewer facts, and making a model larger mainly improves recall of popular facts while barely helping with rarer ones (Mallen et al., 2023); a person's own notes, documents and code are the extreme case, since no model has seen them. Supplying relevant text when a model answers is known to substitute for size on such knowledge (Borgeaud et al., 2022; Lewis et al., 2020), but the one study that measured the gap between a local and a cloud model closed it by keeping the cloud model involved (Narayan et al., 2025). Every model also starts each session knowing nothing of the person's earlier work: memory features belong to one program (Anthropic, 2026b), instruction files written for coding tools are followed only 59.8% of the time (Voria et al., 2026), and the reasons behind decisions vanish unless they are recorded (Jansen & Bosch, 2005), so a decision settled with one model does not reach the next. Since late 2024, the Model Context Protocol (MCP) has given AI programs one common way to reach outside services (Model Context Protocol, 2026), which makes a single shared memory possible. This suggests a practical opportunity: if the local model's weakness is mainly missing knowledge, and the loss between models is mainly a missing record, then one memory on the person's computer, holding their material and the decisions made with their models and reached by every model through MCP, might give a local model much of the knowledge it lacks and let every model build on the decisions made before it, without changing any model.

## 1.2 Problem Statement

Ideally, a person should be able to use a private local model on their own material as confidently as a cloud model, and every model they use, local or cloud, should build on what was settled with the models before it without being told again. In reality, small local models answer poorly on knowledge they have not memorised, and closing that gap by model size alone would need many orders of magnitude more parameters (Kandpal et al., 2023); a person's own material is knowledge that no model has memorised. Models also fail to carry work between them. Memory features belong to single products (Anthropic, 2026b), coding agents followed the instructions in their context files only 59.8% of the time and never followed 37.3% of them (Voria et al., 2026), and models lost 39% of their performance on average when instructions arrived over several turns instead of at once (Laban et al., 2026).

As a result, a person must choose between a private model that knows less and a capable model that sends their data away, and must repeat their reasons to each new model, which may still bring back an option already rejected. Existing memory systems each serve one agent or are evaluated only with cloud models, so there is no evidence of how far one memory, kept on the person's computer and shared by local and cloud models, narrows the gap between them, or of whether models that share it keep each other's decisions.

This study developed Burrow, a local vault that gives local and cloud language models one shared memory. Burrow keeps the person's notes, documents and code on their own computer, together with a ledger of the decisions made with their models and the reasons for them, and any model reads from and writes to it through MCP without being changed. The study then measured how much of the knowledge gap between a local and a cloud model the vault closes, and whether models that share it keep earlier decisions and carry earlier work on.

## 1.3 Research Objectives

### 1.3.1 General Objective

To design, develop and evaluate a local vault that gives local and cloud language models one shared memory of a person's knowledge and decisions.

### 1.3.2 Specific Objectives

i) To analyse the current state of local and cloud language models and the memory available to them, to review existing systems that give models knowledge and memory of earlier decisions, and to identify the gaps those systems leave.
ii) To design a local vault that holds a person's notes, documents and code together with a record of decisions and their reasons, and that any local or cloud model can read from and write to.
iii) To develop the designed vault as working software on a consumer laptop.
iv) To evaluate how much of the knowledge gap between a local model and a cloud model the vault closes.
v) To evaluate whether models that share the vault keep decisions made with earlier models and carry earlier work on.

## 1.4 Research Questions

i) What is the current state of local and cloud language models and the memory available to them, how have existing systems given models knowledge and memory of earlier decisions, and what gaps do those systems leave?
ii) How can a local vault be designed to hold a person's notes, documents and code together with a record of decisions and their reasons, so that any local or cloud model can read from and write to it?
iii) How can the designed vault be developed as working software on a consumer laptop?
iv) How much of the knowledge gap between a local model and a cloud model does the vault close?
v) Do models that share the vault keep decisions made with earlier models and carry earlier work on?

## 1.5 Justification

Research has established that retrieval can stand in for model size on knowledge. Retrieval-augmented models outperformed models many times larger on less popular facts (Mallen et al., 2023), Atlas beat a 540-billion-parameter model with 50 times fewer parameters (Izacard et al., 2023), and across twelve models retrieval beat fine-tuning by a large margin on the least popular knowledge (Soudani et al., 2024). Memory systems keep information across long conversations (Chhikara et al., 2025; Packer et al., 2023), and software teams record design decisions with their reasons in decision records (Nygard, 2011).

What is missing is a memory that serves both needs and is measured on a person's own computer. Existing memory systems each serve one agent or one product, the one study that measured the gap between local and cloud models closed it by sending work to the cloud (Narayan et al., 2025), and decision records are written by people after the fact and read by people, not by the models doing the work. The instruction files that do reach models are often ignored and go out of date without anyone noticing: agents followed stale guidance and none of them repaired the file (Mehtiyev et al., 2026).

This causes real costs, in Kenya as elsewhere, where data sovereignty runs through the national AI strategy (Ogonjo, 2025). People send private material to cloud models because local models know too little, they explain the same reasons to each new model, and models bring back options that were already rejected, which adds work that developers already describe as their main frustration with AI tools (Stack Overflow, 2025). Burrow addresses this with one memory, kept on the person's laptop, that both local and cloud models read and write through MCP, and the study measures how far it narrows the gap and whether decisions carry between models.

This work helps people who use AI models on private material, and people who use several models on the same work, by giving them a local model that knows their material and models that build on each other's decisions, while advancing research in retrieval-augmented generation and agent memory with a measured account of how far a shared local memory narrows the gap between local and cloud models.

## 1.6 Scope

The study focused on one memory shared by local and cloud language models and operated within defined boundaries so that it could be completed in the time available.

The technical scope was the development of Burrow in Swift, with SQLite as its index, on one consumer laptop, an Apple MacBook Pro with 24 GB of shared memory. Local models were open-weight models run on the same laptop through Ollama, with Gemma 4 12B as the main local model, and cloud models were Claude models reached through Claude Code and Anthropic's service. Models connected to Burrow through MCP.

The data scope was a vault of real documents on three subjects that a local model cannot know well: Kenya's Data Protection Act, 2019 and its regulations, documentation of software released in 2026, and the notes of a private software project. From these, 120 knowledge questions in English were written with an answer key for each, and 50 reasoning problems were drawn from the public GSM8K benchmark (Cobbe et al., 2021). Decisions were tested on a fixture project written for the study, with written tasks and hidden tests.

The functional scope covered keeping the person's material and the decisions made with their models, supplying them to any connected model, checking new work against recorded decisions, and a desktop application in which the person reads the vault. Burrow does not generate answers itself and does not change the models that use it.

The time scope ran from June to November 2026. The proposal was completed in June, the analysis and design in July and August, development and evaluation in increments from August to early November, and the report in November.

The study did not train or fine-tune any model, build for mobile phones or for operating systems other than macOS, evaluate languages other than English, handle images or audio, or run a study with real users.

## 1.7 Limitations and Delimitations

### 1.7.1 Limitations

Several factors outside the study's control affect how its findings should be read. Timings were measured on one laptop that other jobs sometimes shared, so they are indicative and may differ on other machines. The cloud models are hosted services whose behaviour can change between versions without notice, and one of them did not accept a fixed temperature setting, so its runs could not be made fully repeatable. Whether a model follows a decision it has been given depends on the model, which the study could supply with information but could not control. The time and cost of running real models limited the number of runs in each condition, so small differences between conditions cannot be told apart from chance. The knowledge questions were written from the documents by AI coding agents from the same family as the cloud model, which may make them easier or harder than the questions a person would ask. Finally, no group of real users was available within the project's timeline, so the usability of the desktop application could not be measured with people other than the developer.

### 1.7.2 Delimitations

The study deliberately narrowed its focus to keep the work feasible and the comparisons fair. It fixed one consumer laptop as the target device and built Burrow for macOS only, so that every timing was taken on the kind of computer a person already owns and reported with its specification. It used local models as published and cloud models as offered, without training or fine-tuning any of them, because a memory that works beside any model a person chooses must not depend on changing that model. It held the vault to text material, namely Markdown notes, documents and linked code folders, in English, and chose three subjects that a local model could not have memorised, so that any gain could be credited to the memory. It tested decisions on one fixture project with one recorded business decision and hidden tests, and used scripted tasks with these tests in place of a study with real users, so that each result could be scored automatically and traced to its transcript. It recorded the exact version of every model and program used, limited sharing within a team to a shared folder rather than a server, and left a full security evaluation of the vault outside the study.
