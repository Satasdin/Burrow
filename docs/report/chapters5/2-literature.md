# Chapter 2:  Literature Review

## 2.1 Introduction

This chapter reviews the research that the study builds on, in order to ground in existing work the two problems that Burrow addresses: the capability gap between small local and large cloud language models, and the loss of a person's work and decisions between one model and the next. Section 2.2 surveys the current state of the field: the rise of small on-device models, what the capability gap consists of, retrieval as a substitute for scale, the efficient use of what a model reads, the evaluation and security of persistent memory, and memory shared across tools and sessions. Section 2.3 reviews memory, retrieval and compression techniques at each scale of model. Section 2.4 examines specific related systems, Section 2.5 identifies the gaps those systems leave, and Section 2.6 closes with the conceptual framework that guided the study. The sources are mainly peer-reviewed conference and journal papers, with technical reports for the models, preprints for the most recent topics and official documentation for software products. Most were published between 2023 and 2026, and older sources were kept where they introduced a method or theory that this study used.

## 2.2 On-Device Language Models and External Memory

This section reviews the current state of the field and addresses the first specific objective of the study.

### 2.2.1 The Rise of On-Device Models

Scaling studies established that the loss of a language model falls smoothly with its parameter count, training data, and compute (Kaplan et al., 2020), which drove the field toward ever larger models served from the cloud. A counter-movement followed. Qwen2.5 (Yang et al., 2024), Llama 3, whose smallest model has 8 billion parameters (Grattafiori et al., 2024), and Phi-3 (Abdin et al., 2024) were published as open-weight models small enough for an ordinary laptop, and Gunter et al. (2024) described the model that Apple ships on its own devices. J. Xu et al. (2024) reviewed this movement and named lower latency, data that stays local, and personalisation among its reasons.

Later generations reach similar quality at smaller sizes. Liu et al. (2024) showed that careful architecture lets models under one billion parameters come close to a seven-billion-parameter model on API-calling tasks, and the Gemma 3 report stated that its 4B model was competitive with the previous generation's 27B model (Gemma Team, 2025). The families released in 2026, Gemma 4 (Gemma Team, 2026) and Qwen3.5 (Qwen Team, 2026), include the two models hosted in this study. Lu et al. (2024) measured 70 open small models and reported their ability together with their latency and memory use on a device.

### 2.2.2 Capability Gaps in Processing

The most important evidence for this study concerns the composition of the gap. Mallen et al. (2023) tested ten models on 14,000 factual questions and found that models struggle with less popular facts and that scaling barely helps in the long tail. Sun et al. (2024) saw the same pattern in 16 public models, which were far from perfect on the rarer entities. Kandpal et al. (2023) traced the cause to training data: accuracy on a fact depends on how many training documents mention it, and closing the long tail by size alone would need many orders of magnitude more parameters. A large part of what users buy with model scale is therefore memorised knowledge, and memorised knowledge is the one ingredient that can also be supplied from outside the model. This study treated knowledge-bound and reasoning-bound tasks separately for that reason.

### 2.2.3 The Scalability-Accuracy Trade-Off

Letting a model read relevant external text at answer time can substitute for parameters. Retrieval-augmented generation paired a generator with an index of documents that it reads at answer time (Lewis et al., 2020), building on dense passage retrieval, which finds relevant text by comparing embedding vectors rather than keywords (Karpukhin et al., 2020). Borgeaud et al. (2022) made the substitution explicit: their RETRO model, retrieving from a database of two trillion tokens, reached performance comparable to GPT-3 and Jurassic-1 with 25 times fewer parameters. Izacard et al. (2023) showed with Atlas that a retrieval-augmented model could beat a 540-billion-parameter model on NaturalQuestions while using 50 times fewer parameters. In the study by Mallen et al. (2023), retrieval-augmented models largely outperformed models that were orders of magnitude larger, and Soudani et al. (2024) found across twelve models that retrieval beat fine-tuning by a large margin on the least popular facts.

The trade-off has a second side, because retrieved text can harm an answer. Yoran et al. (2024) found that retrieval sometimes lowered accuracy across five question-answering benchmarks, and Cuconasu et al. (2024) identified the harmful passages as those a retriever scores highly although they do not contain the answer. Reasoning tasks are especially exposed. Shi et al. (2023) saw performance fall dramatically when irrelevant information was added to grade-school mathematics problems, and Mirzadeh et al. (2025) reported drops of up to 65% from a single clause that only seemed relevant. More context is not simply better either. Levy et al. (2024) found a notable drop in reasoning at input lengths far shorter than a model's maximum, Hsieh et al. (2024) found that only half of 17 long-context models kept satisfactory performance at 32,000 tokens, and Jin et al. (2025) showed that output quality first improves and then declines as the number of retrieved passages rises. None of these results addresses the on-device setting, where the index and the model must fit on a consumer machine and every token read costs measurable time.

### 2.2.4 Token-Efficient Retrieval

Every token a model reads costs time on a device, so what is put in front of the model matters as much as its relevance. Research on prompt compression has shown that the text supplied to a model carries substantial redundancy. Jiang et al. (2023) demonstrated with LLMLingua that prompts can be compressed up to about twenty times with little loss in performance. A complementary line compresses context into learned representations: Chevalier et al. (2023) taught models to summarise long contexts into compact vectors, and Ge et al. (2024) trained an in-context autoencoder that reached about four times context compression on Llama. These methods change the text or the model after the passages have been chosen. The lesson this study took is that the first saving on a device comes from selecting less: reading the memory only when it is needed, and showing the model no more than it reads well. Compression has so far been applied to prompts and contexts at inference time, and not to the question of how a token budget interacts with capability gap closing on a device.

### 2.2.5 Evaluation and Risks of Persistent Memory

Benchmarks for conversational memory inform the evaluation design of this study. Maharana et al. (2024) introduced LoCoMo, a benchmark of very long multi-session conversations, and found that models lag far behind human recall of conversation history. Wu et al. (2025) introduced LongMemEval, 500 questions embedded in long chat histories, and found that commercial assistants lose about 30% accuracy when information must be remembered across sustained interaction. They also divided memory design into indexing, retrieval, and reading stages. Trust in what a model does with its context is a further concern: Joren et al. (2025) found that smaller models often hallucinate or abstain even when the context is sufficient, and Gao et al. (2023) found that even the best models lacked complete citation support half of the time on one benchmark. These studies show that memory is an unsolved problem even for large cloud systems, but none measures memory as an instrument for closing the gap between a small and a large model.

A memory store that accepts writes is also an attack surface. Greshake et al. (2023) showed that instructions hidden in retrieved data can take over an application. Chen et al. (2024) showed with AgentPoison that a small number of crafted records in an agent's memory can steer it when a trigger appears, with benign instructions left untouched, and Dong et al. (2025) showed that an attacker who can only send queries can plant malicious records. Hou et al. (2026) catalogued 16 threat scenarios for servers of the Model Context Protocol. These findings motivated Burrow's guards: text in the vault that is written to steer a model is shown to the person and never handed over as a rule, and nothing is shared with a team or read from a linked folder without the person's approval. A full security evaluation was beyond the scope of this study.

### 2.2.6 Memory Shared Across Tools and Sessions

A person now often uses several models on the same work, and each starts from what its own program supplies. Coding agents read instruction files kept in the project, such as CLAUDE.md, at the start of every session (Anthropic, 2026b), and studies of thousands of such files found them dominated by build commands, implementation notes and architecture (Chatlatanagulchai et al., 2025). They are not reliably followed: coding agents followed the instructions in them 59.8% of the time on average, and 37.3% of instructions were never followed (Voria et al., 2026), and when a file went stale, agents followed it over the code in 90.1% of their choices (X. Xu & Wu, 2026). Even within one session, models lost 39% of their performance on average when instructions arrived over several turns (Laban et al., 2026).

What is lost most often is a decision and its reason. Software engineering calls this knowledge vaporisation, in which the reasons behind a design disappear into the design (Jansen & Bosch, 2005), and practitioners value design rationale but find it hard to record (Tang et al., 2006). Decisions are also hard to retrieve, because they are often written as negations, which most retrieval models rank no better than random (Weller et al., 2024), and a memory that only appends hands over reversed decisions: on reversed facts, append-only memory scored 0.21 against 0.95 for memory that revoked the old fact (Zhou et al., 2026). The Model Context Protocol (MCP) now lets any model reach an outside service through one interface (Model Context Protocol, 2026), which makes a single memory shared by local and cloud models possible.

## 2.3 Memory, Retrieval, and Compression Techniques

The preceding section established the capability gap and the principle that external knowledge can substitute for parameters. This section surveys the techniques that make that substitution work in practice. The review is organised by the scale of the host model, because the constraints, and therefore the appropriate techniques, change as the model shrinks and moves onto the device.

### 2.3.1 Techniques for Large Language Models (LLMs)

At the scale of large cloud models, retrieval and compression are optimisation choices rather than necessities, and the literature has focused on maximising answer quality. Fan et al. (2024) surveyed the retrieval architectures that followed the original work of Lewis et al. (2020). Memory extends retrieval from documents to what an agent keeps over time. Sumers et al. (2024) described a language agent as having working, episodic, semantic, and procedural memory, and Hu, Liu, et al. (2025) separated agent memory from retrieval-augmented generation and classified it by form, function, and dynamics. Luo et al. (2026) described three stages of agent memory, storage, reflection, and experience, and Huang et al. (2026) treated portable agent skills as part of memory. Cloud assistants already apply these ideas: Claude Code reads a codebase and acts on it (Anthropic, 2026a) and keeps a project memory in plain files (Anthropic, 2026b). These techniques assume cloud-scale compute and do not account for the memory and latency budgets of a device.

### 2.3.2 Techniques for Small Language Models (SLMs)

As models shrink, retrieval shifts from optional to essential, because the model can no longer rely on what it has memorised. Wang et al. (2025) surveyed how small language models are defined, acquired, enhanced, and applied, and how they work with larger models. Patra et al. (2026) surveyed on-device small models across architecture, compression, applications, and open challenges. A central question at this scale is when to retrieve at all. Self-RAG needs a specially trained model that judges when retrieval is useful (Asai et al., 2024), and Adaptive-RAG needs a trained classifier that routes a question to no retrieval, one-step retrieval, or multi-step retrieval (Jeong et al., 2024). Moskvoretskii et al. (2025) compared 35 such methods and found that simple uncertainty estimates often matched complex pipelines in answer quality. For a frozen model on a device this finding matters, because a method that needs no training can be applied to any model that a person chooses to run.

### 2.3.3 Techniques for On-Device Deployment

On the device itself, retrieval must respect a fixed hardware budget, so inexpensive rankings are preferred. Ranking by word match uses the BM25 function (Robertson & Zaragoza, 2009), and reciprocal rank fusion merges a word ranking and a meaning ranking without training (Cormack et al., 2009). Bruch et al. (2023) showed that a tuned weighted sum of scores can outperform this fusion, but it needs a training set. The form of the memory also matters. Obsidian keeps a vault as ordinary Markdown files on the person's own disk (Obsidian, 2025a) and draws the links between notes as a graph (Obsidian, 2025b), so the person owns the memory and can read it without any model. Narayan et al. (2025) came nearest to the question of this study: an on-device model reading local documents recovered 87% of a cloud model's performance, and 97.9% when the cloud model split the task into small local jobs, but it depended on the cloud throughout. Taken together, this work shows that the techniques exist and are individually effective. It does not provide a measured account of how much of the capability gap a memory engine closes on its own, by task type, on consumer hardware.

## 2.4 Related Works

This section examines specific systems that implement memory for language models, from operating-system inspired context management to brain-inspired associative retrieval, production memory layers and vector databases, and the two ways in which software teams keep decisions for their tools: context files and decision records. Table 2.1 summarises the comparison.

### 2.4.1 MemGPT

Packer et al. (2023) framed the memory problem in operating-system terms. The model's limited context window is treated as fast main memory and an external store as disk, and the system pages information in and out as the conversation demands, allowing a fixed-context model to sustain interactions far longer than its window. The framing is influential because it makes explicit that what the model reads at each step is a policy decision, which is the decision this study's token budget controls. MemGPT manages context length, however. It does not target capability gain for a small model, and it does not account for token cost or device latency. Figure 2.1 illustrates the two-tier architecture.

!fig figures/related/fig2-1-memgpt.png | Figure 2.1: The MemGPT virtual context architecture. Adapted from Packer et al. (2023). | 6.0

### 2.4.2 Generative Agents

Park et al. (2023) gave simulated agents a memory stream of timestamped observations and retrieved from it by combining three scores: relevance to the current situation, recency, and importance. The agents produced believable long-running behaviour in a simulated town, and the three-part score shaped the retrieval policy of this study. Zhao et al. (2024) later showed that insights written in natural language and recalled at inference improve an agent without any parameter updates. Generative Agents was designed for simulation rather than question answering, and its memory records are verbose natural-language entries, so it does not answer the efficiency questions a device imposes. Figure 2.2 shows the simulated town in which the agents live, work, and remember.

!fig figures/related/fig2-2-generative-agents.png | Figure 2.2: The Smallville environment of Generative Agents. Source: Park et al. (2023). | 5.6

### 2.4.3 MemoryBank

Zhong et al. (2024) added a model of forgetting. MemoryBank strengthens or weakens stored memories over time in the spirit of the Ebbinghaus forgetting curve, so that what the system retains reflects both the time elapsed and the relative significance of a memory. The contribution is a principled answer to what should be kept, and Hu, Wang, and McAuley (2025) later named selective forgetting as one of four competencies of a memory agent. MemoryBank was evaluated through a companion chatbot, SiliconFriend, on real and simulated dialogs, and not on capability gain, token cost, or latency. Figure 2.3 shows the memory bank, the forgetting curve, and retrieval into conversation.

!fig figures/related/fig2-3-memorybank.png | Figure 2.3: The MemoryBank framework with updating and forgetting. Source: Zhong et al. (2024). | 6.0

### 2.4.4 HippoRAG

Plain similarity search retrieves passages that resemble the question, but some questions require connecting facts that do not resemble the question at all. Cognitive science offers a model for this in spreading activation, where recalling one concept activates linked concepts (Collins & Loftus, 1975), and in the hippocampal indexing theory, where a compact index links the distributed traces of an experience (Teyler & DiScenna, 1986). Gutiérrez et al. (2024) built these ideas into HippoRAG: a language model extracts entities from stored passages into a knowledge graph, and a Personalized PageRank walk spreads relevance from the question to connected passages. HippoRAG improved multi-hop question answering by up to 20%, and its single-step retrieval was 10 to 30 times cheaper than iterative retrieval such as IRCoT. A language model must build the graph, however, as in GraphRAG (Edge et al., 2024) and A-Mem (W. Xu et al., 2025), and Gutiérrez et al. (2025) noted that graph methods fall considerably below standard retrieval on basic factual memory. This study therefore searched the text first and followed links that already exist between files. Figure 2.4 shows the pipeline of its successor, HippoRAG 2.

!fig figures/related/fig2-4-hipporag.png | Figure 2.4: HippoRAG 2 offline indexing and online retrieval. Source: Gutiérrez et al. (2025). | 6.0

### 2.4.5 Mem0

Production systems have begun packaging these ideas. Chhikara et al. (2025) presented Mem0, which extracts the salient facts from a conversation, consolidates them, and retrieves them at question time. On the LoCoMo benchmark, the authors reported a 26% relative improvement over OpenAI's memory on a metric judged by a language model. Its existence is evidence that the engineering direction is commercially credible. Mem0 writes memories automatically, however, and it was evaluated on conversational recall, so it does not measure gap closing per task type. Figure 2.5 shows where the memory layer sits in an agent stack.

!fig figures/related/fig2-5-mem0.png | Figure 2.5: The Mem0 memory layer within an agent stack. Source: Mem0 documentation, https://docs.mem0.ai. | 6.0

### 2.4.6 Chroma

Chroma is an open-source vector database (Chroma, 2026). Documents are cut into pieces, each piece is stored with an embedding vector and its text, and at question time the pieces nearest to the question are pasted into the prompt. It was the baseline of this study because it is what a developer would build without a memory engine. A vector database is a store and not an engine: it answers every question with its nearest pieces, and highly ranked pieces without the answer are the ones that hurt (Cuconasu et al., 2024). Chroma's own researchers reported that reliability falls as input grows (Hong et al., 2025). Figure 2.6 shows the distributed architecture.

!fig figures/related/fig2-6-chroma.png | Figure 2.6: The architecture of distributed Chroma. Source: Chroma (2026), https://docs.trychroma.com/reference/architecture/distributed. | 5.8

### 2.4.7 Context Files for Coding Agents

Context files are Markdown files kept in a code repository that a coding agent reads at the start of every session, such as CLAUDE.md for Claude Code and AGENTS.md for several other agents (Anthropic, 2026b). Chatlatanagulchai et al. (2025) studied 2,303 of them from 1,925 repositories and found testing described in 75.9% of files, implementation details in 70.8% and architecture in 68.1%, but security in only 14.8%. They are the simplest shared memory for coding tools, but Gloaguen et al. (2026) found that they did not generally raise the success of coding agents while adding more than 20% to the cost of running them. A context file holds only what a person remembered to write, is read only by tools working in that repository, keeps no reason unless one is written, and is not marked when the code it describes changes. Figure 2.7 shows an example.

!fig figures/related/fig2-agent-readme.png | Figure 2.7: An example of a context file for a coding agent. Source: Chatlatanagulchai et al. (2025) | 5.2

### 2.4.8 Architecture Decision Records

An architecture decision record (ADR) is a short document that records one design decision with its context, the decision itself, its status and its consequences (Nygard, 2011). An accepted record is not edited; when a decision changes, a new record supersedes it, so the history of decisions is kept (Kunce & Goby, 2022). ADRs helped teams follow through on decisions (Keeling, 2022), and language models have checked code against them with good accuracy for decisions that can be read from the code (Su et al., 2026). Their adoption remains low, with about half of the GitHub repositories that use them holding only one to five records (Buchgeher et al., 2023), and they are written by people after the fact, kept in one repository and checked only at human review. Figure 2.8 shows an ADR used to review a change.

!fig figures/related/fig2-adr-aws.png | Figure 2.8: Using an architecture decision record to review a change. Source: Kunce and Goby (2022) | 4.4

!tab Table 2.1: Comparison of representative memory systems
!widths 1.3,1.8,1.5,1.7
| System | Core idea | Strength | Limitation for a memory shared by local and cloud models |
| MemGPT (Packer et al., 2023) | Pages context in and out of the window like an operating system | Sustains very long interactions on a fixed window | Works within one agent; does not target capability gain or keep decisions |
| Generative Agents (Park et al., 2023) | Memory stream scored by relevance, recency and importance | Simple, effective retrieval scoring | Designed for simulation; verbose natural-language records |
| MemoryBank (Zhong et al., 2024) | Memories strengthen and decay over time | Principled forgetting | No accounting of token cost or device latency |
| HippoRAG (Gutiérrez et al., 2024) | Knowledge-graph index walked with Personalized PageRank | Strong multi-hop recall in one retrieval step | A language model must build the graph, which is heavy for a device |
| Mem0 (Chhikara et al., 2025) | Salient facts extracted and consolidated into a managed store | Production-ready; gains on a long-conversation benchmark | Writes memories automatically; reasons not required; no check of work |
| Chroma (Chroma, 2026) | Vector database queried for the pieces nearest to the question | Simple, runs locally, the standard pipeline | A store, not an engine; same retrieval for every question and model |
| Context files (Chatlatanagulchai et al., 2025) | Instruction files read at the start of each session | Simple, versioned with the code | Written by people; one repository; often not followed |
| Architecture decision records (Nygard, 2011) | One record per decision, superseded but never lost | Keeps each decision with its reason | Written after the fact; read only by people at review |

## 2.5 Gaps in Related Works

The reviewed literature establishes each ingredient separately. Retrieval can substitute for model scale on knowledge-heavy tasks (Borgeaud et al., 2022; Izacard et al., 2023; Lewis et al., 2020), and it helps most on the long-tail knowledge where small models fail (Kandpal et al., 2023; Mallen et al., 2023). Memory systems can accumulate, organise, score and forget information across long interactions (Chhikara et al., 2025; Gutiérrez et al., 2024; Packer et al., 2023; Park et al., 2023; Zhong et al., 2024), and software engineering has long kept decisions with their reasons in decision records (Nygard, 2011).

What is missing is the combination and the measurement. As Table 2.1 shows, the memory systems of Section 2.4 serve one agent or one application, the context files and decision records serve one repository and are written by people, and none is reached in the same way by a local and a cloud model. None keeps the decisions that models make with a person, together with their reasons, and hands them to the next model, and none checks new work against them. No reviewed work places such a memory beside a small local model on a consumer laptop and reports both how much of the knowledge gap to a cloud model it closes and whether models that share it keep each other's decisions. Narayan et al. (2025) came nearest on the first question, but their on-device model depended on the cloud throughout. This intersection defines the gap that the study addressed.

## 2.6 Conceptual Framework

### 2.6.1 Definition and Purpose

The conceptual framework shows how Burrow gives local and cloud models one shared memory and how that memory was expected to affect what the models do. It brings together the variables and relationships drawn from Sections 2.2 to 2.5 and links them to the objectives, guiding the methodology in Chapter 3, the design in Chapter 4 and the evaluation in Chapter 5.

### 2.6.2 Key Variables

The input variables are the question or task a model is given, the person's vault of notes, documents and code, and the decisions reached with earlier models. The processing variables are the steps of Burrow: deciding whether the vault is needed and finding the right excerpts, keeping each decision with its reason and files, handing decisions over to every model that connects, checking a change against the decisions it touches, and sharing decisions within a team. The models themselves are held constant, with their weights unchanged, so that every measured effect can be attributed to the memory. The output variables are the answer with its sources, whether the next model keeps an earlier decision, and whether it carries the earlier work on, measured together with the time each step took.

### 2.6.3 Theoretical Foundation

The framework rests on three findings. Retrieval closes the gap on rare and private facts (Kandpal et al., 2023; Mallen et al., 2023), while irrelevant text harms reasoning (Shi et al., 2023), so memory should be supplied when it is needed and left out when it is not. The reasons behind decisions vaporise unless they are kept as a first-class record (Jansen & Bosch, 2005), so decisions should be kept with their reasons. Design Science Research frames the whole, since an artefact is built to address a problem and evaluated against it (Hevner et al., 2004).

### 2.6.4 Visual Representation

Figure 2.9 presents the conceptual framework as a flow from input, through processing, to output, with a feedback loop by which each new decision returns to the vault for the models that follow.

!fig figures/v5/framework.png | Figure 2.9: Conceptual framework of the study, drawn by the author | 6.27

### 2.6.5 Relationships between Variables

The kind of task moderates the effect of memory: the study predicted that the vault would close much of the gap on knowledge-bound questions and little on reasoning-bound ones. What the next model receives depends on what earlier models kept and on how it is handed over, and whether the model then keeps a decision depends on the model as well as on the memory, which is why the check holds a change that touches a decision whatever the model chooses.

### 2.6.6 Flexibility and Refinement

The framework was refined as Burrow was tested with real models. Early runs showed that decisions handed over without their reasons were kept in letter but defeated in purpose, and that some programs never showed Burrow's instructions to their model, which led to keeping reasons with every decision and to sending decisions with a model's first result.

### 2.6.7 Narrative Flow

A person asks a local model how many hours a company has to report a data breach in Kenya; Burrow finds the relevant section of the law in the vault and the model answers with its source. Later, the person settles with a cloud coding model that payments are matched by account reference only, because a conductor pays for a whole group from one phone, and the model keeps that decision in Burrow with its reason. When a local model in another program is asked to handle unmatched payments, Burrow hands it the decision, and if its change brings back matching by phone, Burrow holds the change until it is undone.

### 2.6.8 Alignment with the Objectives

Finding the right material serves the fourth objective, which measures how much of the knowledge gap the vault closes, and keeping, handing over and checking decisions serve the fifth, which measures whether models keep earlier decisions and carry earlier work on. The design of these steps is the second objective and their development the third.
