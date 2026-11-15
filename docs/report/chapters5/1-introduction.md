# Chapter 1:  Introduction

## 1.1 Background Information

Artificial intelligence (AI) tools built on large language models have become part of everyday work in a short time. Programmers now use coding assistants that read a project, change its files and run its tests, while writers, students and support teams use chat assistants and automated agents that answer email or route requests. According to the Stack Overflow Developer Survey of 2025, 84% of developers used or planned to use AI tools in their work, and about half of professional developers used them every day (Stack Overflow, 2025). The same survey found that the most common frustration, reported by 66% of respondents, was output that was almost right but not quite. A person also rarely works with a single tool. A project may be planned in a cloud assistant, edited by a coding agent and later handed to a smaller model that runs on the person's own computer, because the material is private or because every cloud request costs money. Open models such as Gemma and Qwen now run on an ordinary laptop, and J. Xu et al. (2024) list lower latency, data that stays on the device and personalisation among the main reasons for running a model locally.

Each of these tools begins its work with little knowledge of what came before. A language model keeps nothing between requests, so what it knows about a project is only what its program supplies at the start of a session. Products have started to add memory, but each keeps its own. Claude Code, for example, reads a project's instructions from files that the person writes and maintains (Anthropic, 2026b), and a chat assistant's memory serves only that assistant. Even within one long session, models lose track of what was said. Laban et al. (2026) measured an average drop of 39% in performance when the instructions for a task were spread over several turns of a conversation instead of being given at once, and Wu et al. (2025) found that commercial assistants lost about 30% of their accuracy on information that had to be remembered across a sustained interaction.

What is lost most often is not a fact but a decision: what was settled, why it was settled, and which options were turned down. Software engineering has recognised this problem for two decades. Bosch (2004) argued that the main weakness of software architecture was that design decisions had no first-class representation, and Jansen and Bosch (2005) named the result knowledge vaporisation, in which the reasons behind a design disappear into the design itself. Tang et al. (2006) surveyed 81 practitioners and found that they valued design rationale but faced barriers in recording it. Architecture decision records were later proposed as a light way to keep each decision with its context and consequences (Nygard, 2011), yet their adoption on GitHub remains low (Buchgeher et al., 2023).

AI tools make this old problem sharper. Decisions are now reached inside conversations with a model, across several programs, at a pace that no person documents by hand, and the next model to touch the work has no way of knowing what the previous one agreed with the person. When that happens, the new tool may bring back an option that was rejected for a good reason, and the person must notice it and explain the reason again. A memory that keeps such decisions together with their reasons, and gives them to every tool the person uses, could therefore remove much of this repeated work and the errors it lets through. In this study, such a memory was designed and developed as Burrow, a private memory engine that runs on the person's own computer and serves both local and cloud AI tools.

## 1.2 Problem Statement

Ideally, a decision that a person reaches with one AI tool, together with its reason and the options it rejected, should guide every tool that works on the same material afterwards, whether that tool runs in the cloud or on the person's own computer. However, the current reality falls short of this. Each AI tool starts from what its own program supplies, memory features are tied to one product (Anthropic, 2026b), and instruction files hold only what the person remembered to copy into them. Even when instructions are written down, coding agents followed them only 59.8% of the time on average, and 37.3% of instructions were never followed (Voria et al., 2026). Retrieval does not close the gap either, because it returns text that resembles a request, and a decision such as "never match payments by phone number" may not resemble it at all; most retrieval models handle negation no better than random ranking (Weller et al., 2024). As a result, the next tool brings back an option that was already rejected, often with a convincing reason, and nothing warns the person. Small on-device models, which people choose precisely because their material is private, are the most exposed, since they bring the least knowledge of their own.

This study developed Burrow, a private memory engine on the person's own computer that keeps a ledger of the decisions made during AI-assisted work, each with its reason and the files it rests on, hands them to every tool that connects to it, and checks new work against them.

## 1.3 Research Objectives

### 1.3.1 General Objective

To design, develop and evaluate a private on-device memory engine that preserves the decisions made during AI-assisted work, with their reasons, and hands them to the local and cloud AI tools that a person uses.

### 1.3.2 Specific Objectives

i) To analyse how decisions and their reasons are lost when people work with several AI tools across sessions.
ii) To study how existing memory systems for AI tools keep and deliver knowledge and decisions.
iii) To identify the gaps that existing systems leave in keeping decisions across tools on a person's own computer.
iv) To design and develop a private memory engine that keeps decisions with their reasons, hands them to local and cloud AI tools, and checks new work against them.
v) To test and evaluate whether the engine helps AI tools find the right material, keep earlier decisions and carry on earlier work.

## 1.4 Research Questions

i) How are decisions and their reasons lost when people work with several AI tools across sessions?
ii) How do existing memory systems for AI tools keep and deliver knowledge and decisions?
iii) What gaps do existing systems leave in keeping decisions across tools on a person's own computer?
iv) How can a private memory engine be designed and developed to keep decisions with their reasons, hand them to local and cloud AI tools, and check new work against them?
v) Does the engine help AI tools find the right material, keep earlier decisions and carry on earlier work?

## 1.5 Justification

Research has shown that language models lose information across sessions and even within a single long conversation (Laban et al., 2026; Wu et al., 2025), and software engineering has long shown that decisions which are not recorded tend to be lost (Jansen & Bosch, 2005). AI tools have tried to address this with memory features and instruction files. Claude Code reads a project's instruction files at the start of every session (Anthropic, 2026b), and thousands of open-source projects now keep such files for their coding agents (Chatlatanagulchai et al., 2025).

Despite these efforts, the existing approaches leave the problem largely unsolved. Each product's memory serves only that product, so a decision reached in one tool does not reach the next. Instruction files are written by people after the fact and hold only what someone remembered to copy into them, and when a file falls out of date, agents were found to follow it over the code in 90.1% of their choices (X. Xu & Wu, 2026). Gloaguen et al. (2026) further found that such files did not generally improve the success of coding agents while adding more than 20% to the cost of running them.

When decisions are lost in this way, people repeat their reasons to every new tool and still meet rejected options again, and in software work a rejected option can return as a change that breaks something a team had deliberately ruled out. The risk is greatest for people who use small local models to keep their material private, and in Kenya personal data is protected by law (Data Protection Act, 2019), which favours memory that stays on the person's own device.

This study addressed the problem by building a memory in which the AI tools themselves record each decision with its reason as it is made, which hands those decisions to every later tool, and which checks new work against them before the work is reported as done. The study benefits individuals and small teams who work with several AI tools, especially on private material, and it gives researchers measured evidence on decision memory for AI tools.

## 1.6 Scope

The project developed and evaluated Burrow on a consumer Mac with Apple silicon, within the technical, data, functional and time boundaries described here. Burrow was written in Swift and kept its index in an embedded SQLite database, with local models run through Ollama on the same computer. The material it held was the person's own Markdown notes, documents and linked code folders. The AI tools that connected to it through the Model Context Protocol (MCP) were Claude Code, OpenCode, OpenClaw, Hermes Agent, an n8n workflow and the llama.cpp server. The functions covered were indexing and searching the material, keeping decisions with their reasons, handing them to connected tools, checking changes against them, sharing them within a small team, and a desktop application for the person. The evaluation used scripted tasks on a fixture project called Matatu, a simulated fare-payment service with hidden tests, together with 120 knowledge questions on three subjects. The work ran from June to November 2026. Mobile phones, operating systems other than macOS, languages other than English, and use by real end users other than the developer were outside the scope.

## 1.7 Limitations and Delimitations

### 1.7.1 Limitations

Several factors outside the project's control constrained the study. The behaviour of the AI tools and their models was set by their makers and could change from one version to the next, which made exact repetition of a run difficult. Whether a model followed a decision it had been given depended on the model itself and not on the memory. The time and cost of running real AI tools, each run taking several minutes, limited the number of runs that could be made for each condition. Finally, no group of real users was available within the project's timeline.

### 1.7.2 Delimitations

The study deliberately narrowed its focus to keep the work feasible and its results clear. To deal with changing tools, it recorded the exact version of every tool and model and kept the full transcript of every run. Because obedience depends on the model, it measured separately whether a decision reached the model and whether the model kept it, and it added a check that holds a change touching a decision whether or not the model calls it. To make the most of a limited number of runs, it fixed the scoring rules before the main comparisons and reported every result as a count with its sample size. In place of real users, it used scripted tasks on a fixture project with hidden tests, referred to the simulated tools as agents and never as participants, and made no claim about real users.
