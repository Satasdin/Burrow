# Chapter 2:  Literature Review

## 2.1 Introduction

Every language model starts a session knowing nothing about the person or their work. A local model lacks the person's material and therefore answers worse than a cloud model, and every model, local or cloud, forgets what was settled with the models before it. This chapter grounds that problem in existing scholarship: it establishes what is known about the gap between local and cloud models and about memory for language models, examines how existing systems have tried to supply knowledge and keep earlier work, and identifies what they leave undone.

The first specific objective groups three related tasks, analysing the current state of the field, studying existing systems and identifying their gaps, and the chapter takes them in turn rather than repeating material across them. Section 2.2 analyses the current state of local and cloud language models and the memory available to them, and closes with the key challenges. Section 2.3 reviews eight related systems, each by its description, its technology and performance, and its gaps, and compares them in a table. Section 2.4 draws these gaps together and states the unmet need that the study targets. Section 2.5 presents the conceptual framework, which links the review to the design under the second objective and to the evaluation under the fourth and fifth.

The works reviewed are peer-reviewed conference and journal papers, technical reports for the models, preprints for topics from 2026 that have not yet been peer reviewed, and official documentation for products and protocols. A source was included when it reported a method or a measurement bearing on knowledge, memory or decisions for language models. Most were published between 2023 and 2026; older works were kept only where they first stated an idea still in use, such as the BM25 ranking function (Robertson & Zaragoza, 2009) or the loss of the reasons behind design decisions (Jansen & Bosch, 2005).

## 2.2 Current State of Local and Cloud Language Models and Their Memory

### 2.2.1 Overview of Local and Cloud Language Models and Their Memory

A cloud language model is a large model run by a provider on its own hardware and reached over the internet, while a local model is an open-weight model that runs on the person's own computer (J. Xu et al., 2024). A model draws knowledge from two places: its parameters, which hold what it memorised in training, and text supplied to it when it answers (Mallen et al., 2023). In agent research, memory is used in a wider sense for anything a model or its program keeps beyond a single exchange, and is divided into working, episodic, semantic and procedural memory (Sumers et al., 2024).

Current approaches to making models more capable follow four lines. The first is scale: a model's loss falls smoothly as its parameters, data and compute grow (Kaplan et al., 2020), which drove the field towards ever larger cloud models. The second is smaller models built to run on a device. Qwen2.5 (Yang et al., 2024), Llama 3, whose smallest model has 8 billion parameters (Grattafiori et al., 2024), and Phi-3 (Abdin et al., 2024) were released as open weights, and later generations reached similar quality at smaller sizes: sub-billion-parameter models came close to a 7-billion-parameter model on API-calling tasks (Z. Liu et al., 2024), and the Gemma 3 4B model was reported competitive with the previous generation's 27B model (Gemma Team, 2025). Gemma 4 (Gemma Team, 2026) and Qwen3.5 (Qwen Team, 2026) continued the trend in 2026, and Lu et al. (2024) measured 70 open small models for their ability, latency and memory use on a device.

The third line is retrieval-augmented generation, which pairs a model with an index of documents that it reads at answer time (Lewis et al., 2020). Relevant text is found by matching words, ranked with the BM25 function (Robertson & Zaragoza, 2009), or by comparing embedding vectors that capture meaning (Karpukhin et al., 2020), and the two rankings can be merged without training by reciprocal rank fusion (Cormack et al., 2009). Fan et al. (2024) surveyed the architectures that followed. The fourth line is memory kept by agents and their programs across sessions. Surveys separate agent memory from retrieval and classify it by its form, function and dynamics (Hu, Liu, et al., 2025), or trace its development from storage to reflection to experience (Huang et al., 2026; Luo et al., 2026). In practice, coding tools keep memory in plain files: Claude Code reads a codebase and acts on it (Anthropic, 2026a) and loads project instructions from files such as CLAUDE.md at the start of each session (Anthropic, 2026b). Since late 2024, MCP has offered one open standard through which AI programs reach outside services (Model Context Protocol, 2026), and its ecosystem has grown quickly (Hou et al., 2026). Note-taking tools show that a person can own such a memory outright: Obsidian keeps a vault as ordinary Markdown files on the person's own disk (Obsidian, 2025a) and draws the links between notes as a graph (Obsidian, 2025b).

These approaches work in part. Retrieval-augmented models largely outperformed models orders of magnitude larger on less popular facts (Mallen et al., 2023), RETRO matched GPT-3 on language modelling with 25 times fewer parameters (Borgeaud et al., 2022), and across twelve models retrieval beat fine-tuning by a large margin on the least popular knowledge (Soudani et al., 2024). An on-device model reading local documents recovered 87% of a cloud model's performance when the two collaborated (Narayan et al., 2025). The same studies show the limits. Retrieved text lowered accuracy on several question-answering benchmarks when it was not relevant (Yoran et al., 2024), and the most harmful passages were those a retriever scored highly that did not contain the answer (Cuconasu et al., 2024). More text is not simply better: reasoning declined at input lengths far shorter than a model's maximum (Levy et al., 2024), models used information in the middle of a long input less well than at its ends (N. F. Liu et al., 2024), and only half of 17 long-context models kept satisfactory performance at 32,000 tokens (Hsieh et al., 2024). Memory across sessions remains unsolved even for large models: on LoCoMo, models lagged far behind human recall of long conversations (Maharana et al., 2024), and on LongMemEval commercial assistants lost about 30% accuracy when information had to be remembered across sustained interaction (Wu et al., 2025).

### 2.2.2 Key Challenges in Giving Models Knowledge and Memory

The first challenge is the knowledge gap of local models. Models struggle with less popular facts, and scaling barely helps in this long tail (Mallen et al., 2023); 16 public models tested on rarer entities were far from perfect (Sun et al., 2024), and accuracy on a fact depends on how many training documents mention it, so closing the tail by size alone would need many orders of magnitude more parameters (Kandpal et al., 2023). For a person's own notes, documents and code, the tail is the whole of the material, since none of it appeared in training.

The second challenge is that supplying knowledge has costs that fall hardest on small models and on reasoning. Adding irrelevant information to grade-school mathematics problems lowered performance dramatically (Shi et al., 2023), a single clause that only seemed relevant cut accuracy by up to 65% (Mirzadeh et al., 2025), and output quality first rose and then fell as more retrieved passages were added (Jin et al., 2025). Smaller models often answered wrongly or abstained even when the context held enough to answer (Joren et al., 2025). Deciding when to retrieve at all usually needs training, as in Self-RAG (Asai et al., 2024) and Adaptive-RAG (Jeong et al., 2024), which cannot be applied to a model a person simply downloads, although a comparison of 35 methods found that simple estimates of uncertainty often matched these complex pipelines (Moskvoretskii et al., 2025).

The third challenge is that memory is locked inside one program. Each coding tool loads its own instruction files (Anthropic, 2026b), and memory systems are built as a component of one agent (Hu, Liu, et al., 2025). A person who uses one model for private material and another for heavy work therefore keeps separate memories, and what one model learns does not reach the other.

The fourth challenge is that decisions and their reasons are lost or ignored. Software engineering calls this knowledge vaporisation, in which the reasons behind a design disappear into the design itself (Jansen & Bosch, 2005); practitioners value design rationale but find it hard to record (Tang et al., 2006). Where instructions are recorded for models, they are not reliably followed. Coding agents followed the instructions in context files 59.8% of the time on average (Voria et al., 2026), random rules improved an agent as much as rules curated by experts (Zhang et al., 2026), and models lost 39% of their performance on average when instructions arrived over several turns (Laban et al., 2026). Recorded instructions also go stale: agents followed out-of-date guidance even when correct information was available elsewhere (Mehtiyev et al., 2026), and followed a stale instruction file over the existing code in 90.1% of their choices (Xu & Wu, 2026). Decisions are also hard to find, because they are often written as negations, which most retrieval models rank no better than random (Weller et al., 2024), and a memory that only grows hands over decisions that have since been reversed: on reversed facts, memory that only appended scored 0.21 against 0.95 for memory that revoked the old fact (Zhou et al., 2026).

The fifth challenge is that a memory written to by models is an attack surface. Instructions hidden in retrieved data can take over an application (Greshake et al., 2023), a few crafted records in an agent's memory can steer it whenever a trigger appears (Chen et al., 2024), and an attacker who can only send queries can plant such records (Dong et al., 2025). A survey of MCP described 16 threat scenarios for the servers that programs connect to (Hou et al., 2026). A memory shared by several models must therefore treat what it stores as material to read and not as instructions to follow.

Together, these challenges show that the field can supply knowledge to a model and can keep some memory within one program, but that the knowledge gap of local models on personal material is unmeasured, and that decisions are neither kept with their reasons nor carried reliably from one model to another.

## 2.3 Related Works

### 2.3.1 MemGPT

MemGPT treats the memory problem in operating-system terms (Packer et al., 2023). The model's limited context window plays the part of fast main memory and an external store the part of disk, and information is paged between them as a conversation demands, so that a model with a fixed window can sustain interactions far longer than the window allows. The project continues as Letta, which keeps editable blocks of memory inside the model's context (Letta, 2025).

The model manages its own memory by calling functions that search, read and edit the external store, and the system was evaluated on long multi-session conversations and on analysing documents larger than the context window, where it kept answers consistent across sessions. Figure 2.1 shows the two tiers of its virtual context.

!fig figures/related/fig2-1-memgpt.png | Figure 2.1: The MemGPT virtual context architecture. Adapted from Packer et al. (2023). | 6.0

MemGPT serves one agent, whose memory lives inside its own server, and relies on a capable model to manage that memory through function calls, which a small local model does less reliably. It was not evaluated for how much it raises a small model's capability, and it does not distinguish a decision and its reason from any other remembered fact.

### 2.3.2 Generative Agents

Generative Agents gave simulated characters a memory stream of timestamped observations (Park et al., 2023). Each agent retrieved from its stream by combining three scores, relevance to the current situation, recency and importance, and periodically wrote reflections that summarised what it had observed.

In a simulated town of 25 agents, evaluators judged the full architecture more believable than versions without observation, reflection or planning, and the agents produced long-running social behaviour such as organising a party. Later work showed that insights written in natural language and recalled at inference can improve an agent without any change to its parameters (Zhao et al., 2024). Figure 2.2 shows the simulated town.

!fig figures/related/fig2-2-generative-agents.png | Figure 2.2: The Smallville environment of Generative Agents. Source: Park et al. (2023). | 5.6

The system was designed for simulation rather than for answering questions or carrying out work, each memory belongs to one agent, and its records are verbose entries that consume context. It offers a useful scoring idea but says nothing about the gap between local and cloud models or about keeping decisions.

### 2.3.3 MemoryBank

MemoryBank added a model of forgetting to long-term memory (Zhong et al., 2024). It strengthens or weakens stored memories over time in the spirit of the Ebbinghaus forgetting curve, so that what is retained reflects both the time elapsed and the significance of each memory.

The framework was built into SiliconFriend, a companion chatbot, and evaluated on real and simulated dialogues for how well it recalled earlier conversations and adapted to the user. Later work named selective forgetting as one of four competencies of a memory agent (Hu, Wang, & McAuley, 2025). Figure 2.3 shows the memory store, its updating and forgetting, and retrieval into conversation.

!fig figures/related/fig2-3-memorybank.png | Figure 2.3: The MemoryBank framework with updating and forgetting. Source: Zhong et al. (2024). | 6.0

MemoryBank serves one companion model and was not measured for capability gain, cost or speed. Its forgetting is also ill-suited to decisions: a decision taken months ago remains binding until it is replaced, so letting it fade with time would hand later models an incomplete record.

### 2.3.4 HippoRAG

Similarity search finds passages that resemble a question, but some questions need facts that do not resemble the question at all. HippoRAG draws on spreading activation, in which recalling one concept activates linked concepts (Collins & Loftus, 1975), and on the hippocampal indexing theory, in which a compact index links the scattered traces of an experience (Teyler & DiScenna, 1986). A language model extracts entities from stored passages into a knowledge graph, and a Personalized PageRank walk spreads relevance from the question to connected passages (Gutiérrez et al., 2024).

HippoRAG improved multi-hop question answering by up to 20% over standard retrieval, and its single retrieval step was 10 to 30 times cheaper than iterative methods such as IRCoT (Gutiérrez et al., 2024). Figure 2.4 shows the indexing and retrieval pipeline of its successor, HippoRAG 2.

!fig figures/related/fig2-4-hipporag.png | Figure 2.4: HippoRAG 2 offline indexing and online retrieval. Source: Gutiérrez et al. (2025). | 6.0

A language model must build the graph, which is costly on a laptop, as in GraphRAG (Edge et al., 2024) and A-Mem (W. Xu et al., 2025), and the authors of HippoRAG 2 noted that graph methods fall considerably below standard retrieval on basic factual memory (Gutiérrez et al., 2025). A person's own notes often already contain the links that such systems spend a model to extract.

### 2.3.5 Mem0

Mem0 packages memory as a layer that any agent can call (Chhikara et al., 2025). After each exchange it extracts the salient facts from the conversation, consolidates them with what it already holds, and retrieves the relevant ones at question time.

On the LoCoMo benchmark, the authors reported a 26% relative improvement over OpenAI's memory on a score judged by a language model, with far fewer tokens read than feeding the model its full history (Chhikara et al., 2025). Zep, a similar product built on a time-aware knowledge graph, reported up to 18.5% higher accuracy on LongMemEval, although these results come from the vendor (Rasmussen et al., 2025). Figure 2.5 shows where the memory layer sits in an agent stack.

!fig figures/related/fig2-5-mem0.png | Figure 2.5: The Mem0 memory layer within an agent stack. Source: Mem0 documentation, https://docs.mem0.ai. | 6.0

Mem0 writes memories automatically from conversation, so a decision is stored as one more fact without its reason or the options that were rejected. It was evaluated on recalling conversations, not on closing the gap between a local and a cloud model, and its managed service keeps the memory outside the person's computer.

### 2.3.6 Minions

Minions is the work closest to the knowledge gap that this study measures (Narayan et al., 2025). A small model on the device reads long local documents and exchanges messages with a cloud model, which never reads the documents in full.

In the simple version, the collaboration cut cloud costs 30.4 times but recovered only 87% of the cloud model's performance. When the cloud model split the task into small jobs for the local model, 97.9% was recovered at 5.7 times lower cost. The authors traced the local model's shortfall to following multi-step instructions and reasoning over long contexts.

Minions narrows the gap by keeping the cloud model in every task, so it does not work offline and still sends part of the work to a provider. It keeps no memory across sessions and has no notion of decisions, so it addresses one task at a time rather than the person's accumulated work.

### 2.3.7 Context Files for Coding Agents

Context files are Markdown files kept in a code repository that a coding agent reads at the start of every session, such as CLAUDE.md for Claude Code and AGENTS.md for several other agents (Anthropic, 2026b). They are the most widely used way of giving a coding model memory of a project. Figure 2.6 shows an example.

!fig figures/related/fig2-agent-readme.png | Figure 2.6: An example of a context file for a coding agent. Source: Chatlatanagulchai et al. (2025). | 5.2

A study of 2,303 context files from 1,925 repositories found testing described in 75.9% of files and architecture in 68.1%, but security in only 14.8% (Chatlatanagulchai et al., 2025). Their effect is weak. Such files did not generally raise the success of coding agents while adding more than 20% to the cost of running them (Gloaguen et al., 2026), agents followed their instructions 59.8% of the time (Voria et al., 2026), and random rules helped as much as curated ones (Zhang et al., 2026).

A context file holds only what a person remembered to write, is read only by the tools working in that repository, and is not marked when the code it describes changes. When it goes stale, agents follow it over the code (Xu & Wu, 2026) and do not repair it (Mehtiyev et al., 2026), so an outdated file can do more harm than no file.

### 2.3.8 Architecture Decision Records

An architecture decision record (ADR) is a short document that records one design decision with its context, the decision itself, its status and its consequences (Nygard, 2011). An accepted record is not edited; when a decision changes, a new record supersedes it, so the history of decisions is kept. Figure 2.7 shows an ADR used to review a change.

!fig figures/related/fig2-adr-aws.png | Figure 2.7: Using an architecture decision record to review a change. Source: Kunce and Goby (2022). | 4.4

ADRs are recommended in industry guidance as a way to keep decisions consistent and to review changes against them (Kunce & Goby, 2022). Their adoption remains low, however: about half of the GitHub repositories that use them hold only one to five records (Buchgeher et al., 2023).

ADRs keep each decision with its reason, which is what the other systems lack, but they are written by people after the fact and read by people at review time. No model writes them while working, no model is given them as a session begins, and nothing checks new work against them.

Table 2.1 compares the eight systems by their approach, their main strength and their critical gap for a memory shared by local and cloud models.

!tab Table 2.1: Comparative analysis of reviewed systems
!widths 1.3,1.8,1.5,1.8
| System | Approach | Strength | Critical gap |
| MemGPT (Packer et al., 2023) | Pages context between the window and an external store | Sustains very long interactions on a fixed window | Serves one agent; needs a capable model to manage its memory |
| Generative Agents (Park et al., 2023) | Memory stream scored by relevance, recency and importance | Simple, effective retrieval scoring | Built for simulation; verbose records; one agent |
| MemoryBank (Zhong et al., 2024) | Memories strengthen and fade over time | Principled forgetting | One companion model; would let binding decisions fade |
| HippoRAG (Gutiérrez et al., 2024) | Knowledge graph walked with Personalized PageRank | Strong multi-hop recall in one step | A language model must build the graph |
| Mem0 (Chhikara et al., 2025) | Salient facts extracted and consolidated | Production-ready; fewer tokens than full history | Automatic writes without reasons; memory held by a service |
| Minions (Narayan et al., 2025) | Local model collaborates with a cloud model | Recovers most of the cloud model's performance | Needs the cloud model in every task; no memory across sessions |
| Context files (Chatlatanagulchai et al., 2025) | Instruction files read at the start of each session | Simple and kept with the code | Written by people; one repository; often ignored; go stale |
| Decision records (Nygard, 2011) | One record per decision, superseded but never lost | Keeps each decision with its reason | Written after the fact; read by people, not models |

## 2.4 Gaps in Related Works

A critical reading of the systems in Section 2.3 shows five limitations that persist across them, which this study addresses.

First, memory is tied to one agent or one product. MemGPT, Generative Agents and MemoryBank each keep the memory of a single agent (Packer et al., 2023; Park et al., 2023; Zhong et al., 2024), Mem0 keeps it in a managed service (Chhikara et al., 2025), and context files are read only by tools working in one repository (Anthropic, 2026b). As Table 2.1 shows, none is shared in the same way by a local model and a cloud model, so a person who uses both keeps two memories that never meet.

Second, the gap between local and cloud models has not been measured with a memory that stays on the person's computer. The memory systems were evaluated on recall in long conversations (Chhikara et al., 2025; Maharana et al., 2024), not on how far they raise a small model towards a large one, and Minions, the one study that measured the gap, closed it by sending work to the cloud model throughout (Narayan et al., 2025). Retrieval is known to stand in for model size on rare knowledge (Mallen et al., 2023; Soudani et al., 2024), but how much of the gap it closes on a person's own material, held on their own laptop, remains unknown.

Third, decisions are kept without their reasons, or with their reasons but out of the models' reach. Mem0 and the agent memories store a decision as one more fact (Chhikara et al., 2025; Park et al., 2023), while decision records keep the reason but are written by people after the fact and read by people at review (Buchgeher et al., 2023; Nygard, 2011). Since the reasons behind decisions vanish unless they are recorded (Jansen & Bosch, 2005), a later model that receives a decision without its reason, or receives nothing, can bring back an option that was already rejected.

Fourth, what is recorded is not checked against later change. Context files are not marked when the code they describe changes, agents follow them when they are stale and do not repair them (Mehtiyev et al., 2026; Xu & Wu, 2026), and memories that only grow hand over facts that have since been reversed (Zhou et al., 2026). MemoryBank's answer, forgetting with time, would remove decisions that still hold (Zhong et al., 2024).

Fifth, memories that models write are not screened. Records planted in an agent's memory can steer it (Chen et al., 2024; Dong et al., 2025), and none of the reviewed systems treats stored material strictly as text to read rather than as instructions, which matters more once several models share the same store (Greshake et al., 2023; Hou et al., 2026).

**Key unmet need:** one memory, kept on the person's own computer and shared by local and cloud models through a common protocol, that holds both the person's material and the decisions made with their models together with the reasons for them, and that has been measured both for how much of the knowledge gap between a local and a cloud model it closes and for whether models that share it keep each other's decisions. No reviewed system meets this need, and this study targets it directly.

## 2.5 Conceptual Framework

### 2.5.1 Definition and Purpose

The conceptual framework sets out the variables of the study, the process that connects them and the outcomes by which the study was judged. It is drawn from the literature in Sections 2.2 to 2.4 and guided both the design of Burrow and the experiments that evaluated it.

### 2.5.2 Research Focus

The focus of the study is one memory shared by local and cloud language models. The guiding question is how a memory kept on the person's own computer can give a local model the knowledge it lacks and let every model build on the decisions made with the models before it.

### 2.5.3 Key Variables and Concepts

The input variables are the questions and tasks that local and cloud models receive, and the person's material: notes and documents in Markdown and code folders linked to the vault. The processing variable is the shared vault, which finds the material a model needs, keeps each decision with its reason, hands the decisions in force to the next model, checks new work against them, and shares them with a team when the person approves. The models themselves are held constant. The output variables are the answer with its sources, whether a later model keeps an earlier decision, and whether it carries the earlier work on. Each output was measured against baselines that are not part of the vault: the model alone, a vector database, the cloud model, a pasted transcript and earlier builds of Burrow.

### 2.5.4 Theoretical Foundation

The framework rests on four findings from the literature. Retrieved text closes the gap on rare facts that a model has not memorised (Mallen et al., 2023), while irrelevant text harms reasoning (Shi et al., 2023), so the vault must decide when it is needed. The reasons behind decisions are lost unless they are kept as a record (Jansen & Bosch, 2005), which is why a decision is kept only with its reason. A record that is never revisited goes stale and misleads (Mehtiyev et al., 2026; Zhou et al., 2026), which is why decisions are tied to the material they rest on. Design science research frames the whole study, since an artefact is built to address a problem and evaluated against it (Hevner et al., 2004).

### 2.5.5 Visual Representation

Figure 2.8 presents the conceptual framework as a flow from input, through the processing of the vault, to output, with a feedback loop by which each new decision returns to the vault and becomes input for the next model.

!fig figures/v5/framework.png | Figure 2.8: Conceptual framework of the study, drawn by the author | 5.3

### 2.5.6 Relationships Between Variables

The person's material, supplied by the vault, was expected to raise a local model's accuracy on knowledge questions towards that of a cloud model given the same material, and to have little effect on reasoning problems, where the vault should stay out of the way. A decision kept with its reason and handed to the next model was expected to raise the share of later sessions that keep the decision and carry the work on. Whether a model keeps a decision was expected to depend on two things: whether the decision reaches it, which the vault controls, and the model itself, which it does not; the check of new work links the two by catching a change that breaks a decision.

### 2.5.7 Flexibility and Refinement

The framework was refined as the system was built and tested. Runs with real AI programs added the hand-over of decisions when a program connects and the check of new work, the Sprint II review led to the desktop application, and the last increment added sharing within a team, so the processing stage grew from finding material to the five steps shown in Figure 2.8.

### 2.5.8 Narrative Flow

A person asks a local model how many hours a company in Kenya has to report a data breach. The vault judges that the question needs the person's material, finds the relevant section of the Data Protection Act and supplies it with its file and line, and the model answers with its source. Later, the person settles a decision with a cloud coding model, that payments are matched by account reference only because conductors pay for a whole group from one phone, and the model keeps the decision in the vault with its reason. When a different model takes up the work, the vault hands it that decision before it begins, and if its change would break the decision, the change is held until the decision is dealt with. The new decisions it makes return to the vault for the next model.

### 2.5.9 Alignment with the Objectives

The framework links the review to the rest of the study. Its processing stage is what the second objective designs and the third develops, its first output is measured under the fourth objective, and its second and third outputs are measured under the fifth.
