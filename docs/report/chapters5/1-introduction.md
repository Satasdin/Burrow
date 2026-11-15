# Chapter 1:  Introduction

## 1.1 Background Information

Language models have become the foundation of modern conversational software, powering assistants that answer questions, summarise documents and write code. The most capable of these models run as cloud services on specialised hardware, and their capability comes at a cost: every request travels over a network, personal data leaves the user's device, and each request carries a price. Scaling studies have shown that a model's performance improves predictably with its size and training data (Kaplan et al., 2020), which is why the strongest models are also the largest and the least practical to run on a personal computer.

A parallel movement has formed around small language models that run directly on consumer laptops. Open-weight families such as Qwen, Llama, Phi and Gemma now offer models that fit in the memory of an ordinary computer (Abdin et al., 2024; Gemma Team, 2026; Grattafiori et al., 2024; Yang et al., 2024). Running a model locally keeps private data on the machine, works offline and costs nothing per request (J. Xu et al., 2024). These small models remain weaker than cloud models, however, and their most consistent weakness is knowledge: they have memorised far fewer facts, and making a model larger barely helps with rare facts, which are exactly the ones retrieved text helps most (Mallen et al., 2023). A person's own notes, documents and code are the extreme case, because no model has seen them in training.

Every model, local or cloud, also shares a second weakness: it starts each session knowing nothing about the person or their work. A person increasingly uses several models on the same project, such as a cloud coding assistant alongside a local model kept for private material, and each model begins only with what its own program supplies (Anthropic, 2026b). What was settled with one model, and why, therefore never reaches the next, and software engineering has long recognised that decisions whose reasons are not kept are lost to later work (Jansen & Bosch, 2005). Since late 2024, the Model Context Protocol (MCP) has given AI programs a common way to reach outside services (Model Context Protocol, 2026), which makes it possible for many models to share one memory. If that memory lived on the person's own computer and held both their knowledge and the decisions made with their models, a local model could know what the person knows, and no model would forget what another had already decided.

## 1.2 Problem Statement

Ideally, a person should be able to use a private local model as confidently as a cloud model, and every model they use, local or cloud, should know the person's material and build on what was settled with the models before it. In reality, a local model answers poorly on knowledge it has not memorised, and a person's own material is knowledge no model has seen (Mallen et al., 2023). Every model also starts each session without the person's earlier work: memory features are tied to one product (Anthropic, 2026b), and instruction files that people write for their tools are followed only 59.8% of the time on average (Voria et al., 2026). As a result, a person must choose between a private model and a capable one, and must repeat their reasons to each new model, which may still bring back an option already rejected. No existing work provides one memory on the person's own computer that both local and cloud models share, and measures how far it narrows the gap between them and whether models keep each other's decisions.

This study developed Burrow, a local vault that gives local and cloud language models one shared memory. Burrow keeps the person's notes, documents and code on their own computer, together with a record of the decisions made with the models and their reasons, and any model reaches it through MCP without being changed.

## 1.3 Objectives

This section states the general objective of the study and breaks it down into the specific objectives that guided the work.

### 1.3.1 General Objective

To design, develop and validate a local vault that gives local and cloud language models one shared memory of a person's knowledge and decisions.

### 1.3.2 Specific Objectives

i) To investigate the capability gap between local and cloud language models, and existing techniques for giving models memory of knowledge and of earlier decisions.
ii) To design a local vault that holds a person's material and a record of decisions with their reasons, and that local and cloud models can share.
iii) To develop the designed vault on a consumer laptop.
iv) To evaluate how much of the knowledge gap between a local model and a cloud model the vault closes.
v) To evaluate whether models that share the vault keep earlier decisions and carry on earlier work.

## 1.4 Research Questions

i) What is the capability gap between local and cloud language models, and what techniques exist for giving models memory of knowledge and of earlier decisions?
ii) How can a local vault be designed to hold a person's material and a record of decisions with their reasons, shared by local and cloud models?
iii) How can the designed vault be developed on a consumer laptop?
iv) How much of the knowledge gap between a local model and a cloud model does the vault close?
v) Do models that share the vault keep earlier decisions and carry on earlier work?

## 1.5 Justification

The study matters for three audiences. For users, especially where data privacy is a serious concern, a more capable local model means useful AI that keeps personal data on their own computer and costs nothing per request; in Kenya, personal data is protected by law (Data Protection Act, 2019). For people who use several AI models on the same work, a shared memory means that what was settled with one model reaches the next, instead of being repeated or undone. For the research community, the study contributes a measure of how far a local memory narrows the gap between local and cloud models, and evidence on whether models keep decisions that other models made.

## 1.6 Scope

The target device was a consumer laptop of the kind a person already owns, on which Burrow, the local models and all timings ran. The local models were open-weight models run on the laptop, and the cloud models were reached through their providers' services. The material in the vault was the person's own notes, documents and code, and the evaluation used English knowledge questions and coding tasks with hidden tests. The system delivered was the Burrow vault, the means by which models connect to it, and a desktop application through which the person reads it. The work ran from June to November 2026.

## 1.7 Limitations and Delimitations

### 1.7.1 Limitations

The study operated under constraints that shape how the findings should be interpreted. First, timings measured on one laptop may differ on other machines. Second, cloud models are hosted services whose behaviour may change over time. Third, whether a model follows a decision it has been given depends on the model and not on the memory. Fourth, the time and cost of running real models limited the number of runs, and no group of real users was available within the project's timeline.

### 1.7.2 Delimitations

The delimitations respond directly to those constraints. To address the hardware limitation, the study fixed one laptop as the target device and reported its specification with every timing. To address changing cloud models, it recorded the exact model and version of every run. To address obedience, it measured separately whether a decision reached a model and whether the model kept it. To address the cost of runs, it used scripted tasks with hidden tests in place of real users and reported every result with its sample size. To keep the project focused, the study did not train or fine-tune any model, did not build for mobile phones, and did not evaluate languages other than English.
