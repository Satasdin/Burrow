# Chapter 1:  Introduction

## 1.1 Background Information

Artificial intelligence (AI) tools built on large language models are now part of everyday knowledge work. Programmers use coding assistants that read a project and change it, writers and students use chat assistants, and automation platforms run AI agents that answer email or route requests. In the Stack Overflow Developer Survey of 2025, 84% of respondents said that they used or planned to use AI tools in their work (Stack Overflow, 2025). A person rarely uses only one such tool. The same project may be planned in a cloud assistant, edited by a coding agent, and handed to a smaller model that runs on the person's own computer because the material is private or because each cloud request costs money (J. Xu et al., 2024).

Each of these tools starts its work with little memory of what came before. A language model keeps nothing between requests, so what it knows about a project is whatever its program supplies at the start of a session. The products have begun to add memory, but each keeps its own: Claude Code keeps a project's instructions in files that the person writes (Anthropic, 2026b), and a cloud assistant's memory serves only that assistant. Even within one long session, models lose track. Laban et al. (2026) measured an average drop of 39% when an instruction was spread over several turns of a conversation instead of given at once, and Wu et al. (2025) found that commercial assistants lost about 30% accuracy on facts that had to be remembered across sustained interaction.

What is most often lost is not a fact but a decision: what was settled, why, and what was turned down. Software engineering has long recognised this problem. Bosch (2004) argued that the main weakness of software architecture was the lack of a first-class representation of design decisions, and Jansen and Bosch (2005) named the result knowledge vaporisation: the reasons behind a design disappear into the design itself. Tang et al. (2006) surveyed 81 practitioners and found that they valued design rationale but met barriers to recording it, and architecture decision records were proposed as a light way to keep each decision with its context and consequences (Nygard, 2011). Their adoption on GitHub nevertheless remains low (Buchgeher et al., 2023). AI tools make the problem sharper. Decisions are now made inside conversations with a model, in several programs, at a pace no person documents by hand, and the next model to touch the work has no way of knowing what the last one agreed with the person. A memory that keeps those decisions with their reasons, and gives them to every tool the person uses, would address a gap that both the AI tools and the older practice of decision records leave open.

## 1.2 Problem Statement

Ideally, a decision that a person reaches with one AI tool, together with its reason and the options it rejected, should bind every tool that works on the same material afterwards, whether that tool runs in the cloud or on the person's own computer. In reality, each AI tool starts from what its own program supplies. Memory features are tied to one product (Anthropic, 2026b), and instruction files hold only what the person remembered to copy into them: coding agents followed such files only 59.8% of the time on average, and 37.3% of instructions were never followed (Voria et al., 2026). When a file went stale, agents followed it over the code in 90.1% of choices (X. Xu & Wu, 2026). Retrieval returns text that resembles the request, which a decision such as "never match by phone number" may not, since most retrieval models handle negation no better than random ranking (Weller et al., 2024). The consequence is that the next tool reintroduces an option that was already rejected, often with a convincing reason, and nothing warns the person. Each repeat costs time, and in practice it can ship a change that a team had ruled out for a known cause. Small on-device models, which a person may use precisely because the material is private, are the most exposed, since they bring the least knowledge of their own.

This study developed Burrow, a private memory engine on the person's own computer. Burrow keeps the person's notes, documents and linked code, and a Ledger of the decisions made during AI-assisted work, each with its reason and the files it rests on. It hands those decisions to every local and cloud tool that connects through the Model Context Protocol (MCP), marks a decision when its files change, and checks a change against the decisions it touches before the work is called done. The study then evaluated whether this lets AI tools find the right material, keep earlier decisions and carry on earlier work.

## 1.3 Research Objectives

This section states the general objective of the study and the specific objectives that guided the work.

### 1.3.1 General Objective

To design, develop and evaluate a private on-device memory engine that preserves the decisions made during AI-assisted work, with their reasons, and hands them to every local and cloud AI tool that a person uses.

### 1.3.2 Specific Objectives

i) To analyse how decisions and their reasons are lost when a person works with several AI tools across sessions, and the challenges that this loss causes.
ii) To review how existing memory systems for AI tools preserve and deliver knowledge and decisions.
iii) To identify the gaps that existing systems leave in keeping decisions across tools on a person's own computer.
iv) To design and develop a memory engine that keeps a person's material and a ledger of decisions tied to files, serves both to local and cloud AI tools, and checks new work against the decisions it touches.
v) To evaluate whether the engine lets AI tools find the right material, keep earlier decisions and carry on earlier work, compared with baselines, and at what cost in time.

## 1.4 Research Questions

i) How are decisions and their reasons lost when a person works with several AI tools across sessions, and what challenges does this cause?
ii) How do existing memory systems for AI tools preserve and deliver knowledge and decisions?
iii) What gaps do existing systems leave in keeping decisions across tools on a person's own computer?
iv) How can a memory engine be designed and developed that keeps a person's material and a ledger of decisions tied to files, serves both to local and cloud AI tools, and checks new work against those decisions?
v) Does the engine let AI tools find the right material, keep earlier decisions and carry on earlier work, compared with baselines, and at what cost in time?

## 1.5 Justification

It is known that language models forget across sessions and lose track within them (Laban et al., 2026; Wu et al., 2025), and software engineering has known for two decades that undocumented decisions vaporise (Jansen & Bosch, 2005). What is missing is a memory that keeps decisions made during AI work, in whichever tool they were made, and makes the next tool keep them. Without it, people repeat their reasons to each new tool and still meet rejected options again, and the risk is greatest with the small local models chosen for privacy. Kenyan law also protects personal data (Data Protection Act, 2019), which favours memory that stays on the person's own device. This study contributes a working engine, a design in which decisions are tied to the files they govern, and an evaluation of when this memory helps and when it does not. It benefits individuals and small teams who work with several AI tools, especially on private material, and it gives researchers measured evidence on decision memory for AI tools.

## 1.6 Scope

The study covered one person's work, and later a small team's, on a consumer Mac with Apple silicon. The material was the person's own Markdown notes, documents and linked code folders. The tools connected through MCP were Claude Code, OpenCode, OpenClaw, Hermes Agent, an n8n workflow and the llama.cpp server, with local models run through Ollama and cloud models used where a comparison needed them. The system delivered was the Burrow engine with its Ledger, a command-line program, an MCP server, hooks for coding tools, and a desktop application. The evaluation used scripted tasks on a fixture project, Matatu, a simulated fare-payment service, and knowledge questions on three curated subjects. The work ran from June to November 2026. Phones, other operating systems, languages other than English, and use by real end users outside the developer were outside the scope.

## 1.7 Limitations and Delimitations

### 1.7.1 Limitations

The study faced four constraints outside its control. First, the behaviour of the AI tools and of their models depends on their makers and can change between versions. Second, whether a model obeys a decision that it has been given depends on the model, not on the memory. Third, the time and cost of running real AI tools limited the number of runs per condition. Fourth, no group of real users was available within the project's timeline.

### 1.7.2 Delimitations

Each delimitation answers the limitation of the same number. First, the study recorded the exact versions of every tool and model and kept the full transcript of every run. Second, the study measured delivery and keeping separately, and added a check that holds a change touching a decision whether or not the model calls it. Third, the study pre-registered its scoring for the main comparisons and reported counts with their small sample sizes rather than percentages alone. Fourth, the study used scripted tasks on a fixture project with hidden tests, called the simulated tools agents and never participants, and stated that no claim about real users is made. Chapter 2 reviews the literature on which these choices rest.
