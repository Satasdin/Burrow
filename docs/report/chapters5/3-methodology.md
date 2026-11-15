# Chapter 3:  Methodology

## 3.1 Introduction

This chapter describes how the study was carried out. Section 3.2 sets out the experimental paradigm: the data, how it was prepared, why no model was trained, and how results were validated. Section 3.3 names the development methodology and justifies it, and Section 3.4 shows it as a diagram with its stages. Sections 3.5 and 3.6 name the analysis and design diagrams presented in Chapter 4, and Sections 3.7 and 3.8 list the deliverables and the tools. The system was analysed and designed with Object-Oriented Analysis and Design (OOAD), and the study followed Design Science Research (DSR), in which an artefact is built to address a problem and then evaluated against it (Hevner et al., 2004; Peffers et al., 2007).

## 3.2 Research Paradigm

The study followed an experimental paradigm. Each claim about the engine was turned into a measurable question, answered by running real AI tools on prepared tasks with and without Burrow, or with a baseline in its place, and scoring the outcome by a rule fixed before the run. The independent variable was what the tool was given: nothing, a baseline memory, or Burrow. The dependent variables were whether the right material reached the model, whether the model kept an earlier decision, whether it carried on the earlier work, and the time each step took.

### 3.2.1 Data Acquisition

Two kinds of data were used. The first was a vault of notes and documents on three subjects, assembled for the study from public sources: the Kenya Data Protection Act (Data Protection Act, 2019), documentation of software released in 2026, and the notes of a private software project, together with 120 knowledge questions written from those documents and 50 reasoning problems from the public GSM8K benchmark (Cobbe et al., 2021). The second was Matatu, a fixture project written for the study: a Python service of about 1,500 lines that records matatu (minibus) fares paid by M-Pesa and reconciles them against payment statements. Matatu came with written tasks, a set of hidden tests that the AI tools could not read, and a business decision with a reason and two rejected options. No personal data of real people was used; the names in the fixture are invented.

### 3.2.2 Data Processing

The documents were converted to Markdown where needed and placed in the vault, and the Matatu code was linked into the vault as a read-only folder. Burrow indexed both: each file was split into pieces at its headings or code boundaries, and each piece was stored with its file and line numbers, its words for full-text search, and an embedding vector for search by meaning. The questions, their answer keys and the hidden tests were kept outside the vault, so that no answer could be read from the memory under test.

### 3.2.3 Model Training

No model was trained or fine-tuned. Burrow sits beside the model and changes only what the model is given, so the local and cloud models were used as published, with their versions recorded. What was set instead was the engine's own behaviour: how many decisions are handed over when a tool connects, how decisions are chosen for a request, and how much text a resumed session receives. These settings were fixed from cases written for that purpose, not from the evaluation tasks.

### 3.2.4 Model Validation and Testing

Each evaluation was scored by a rule written before it was run. Knowledge answers were scored against an answer key, decisions were scored by the hidden tests of the fixture, and carrying on was scored by whether the next session continued the right step with the right constraint. Every run kept its full transcript, which was read to rule out a tool finding the answer outside Burrow. Because real tool runs are slow and their models are not deterministic, the samples were small; counts are therefore reported with their sample sizes, and paired results were compared with an exact sign test where the design allowed it.

## 3.3 System Development Methodology

The system was developed incrementally, with OOAD for analysis and design. Each increment added one capability to a working engine (the vault and its search, the Ledger, the connection to AI tools, the check of new work, and sharing within a team), was tested with real tools, and was corrected before the next began. Where a real run exposed a fault, the fault, the fix and its evidence were recorded as a numbered design decision in the repository.

### 3.3.1 Justification of the Methodology

An incremental method suited the study because the requirements could not be fixed in advance. How AI tools actually use a memory was only learned by running them, and several requirements, such as handing decisions over with a tool's first result, came from failures seen in real runs. Iterative and incremental development has a long record of handling such changing requirements (Larman & Basili, 2003). OOAD suited it because the engine is made of well-separated objects (a vault, a ledger, a commit, a session, a check) whose responsibilities stayed stable while their behaviour grew. DSR framed the whole: the artefact was built to address the problem of Section 1.2 and evaluated against the objectives of Section 1.3 (Hevner et al., 2004).

## 3.4 Methodology Diagram

Figure 3.1 shows the incremental methodology as it was applied in this study. Each increment passed through planning, analysis and design, implementation, testing, and evaluation with real tools, and its result fed the plan of the next.

!fig figures/v5/incremental.png | Figure 3.1: Incremental development approach applied to Burrow, drawn by the author | 6.2

### 3.4.1 Planning

Each increment began from the objectives and from the faults left by the previous one. The plan named the capability to add, the requirement it served, and the run that would show whether it worked.

### 3.4.2 Analysis and Design

The capability was analysed with UML use case, sequence and activity diagrams, and designed as classes and stored records within the existing architecture. Chapter 4 presents the resulting design.

### 3.4.3 Implementation

The engine was written in Swift as one package with no third-party dependency, with the desktop application in SwiftUI. Each change was committed with a message naming its decision, and each evaluation was run on a tagged build.

### 3.4.4 Testing

Unit tests checked each type alone, integration tests drove the engine through the protocol and the command line with scripted clients, and system tests ran the requirements end to end. Positive, negative and boundary cases were included, together with security cases written by an independent automated review of each change.

### 3.4.5 Evaluation

Each increment ended with runs of real AI tools on the fixture tasks, scored by their hidden tests and read in full. The results decided whether the capability stayed, changed or was taken out.

## 3.5 System Analysis Diagrams

The analysis diagrams describe what the system does and for whom. Chapter 4 presents them.

### 3.5.1 Use Case Diagram

The use case diagram shows the actors (the person, a connected AI tool, a teammate and the local model service) and what each does with Burrow.

### 3.5.2 Sequence Diagram

The sequence diagram shows the messages exchanged when an AI tool connects, resumes, looks something up, keeps a decision, and has its change checked.

### 3.5.3 Activity Diagram

The activity diagram shows the flow of a change through the check, from the edit to the verdict and the person's choice.

### 3.5.4 Class Diagram

The class diagram shows the main types of the engine and their relationships.

## 3.6 System Design Diagrams

The design diagrams describe how the system is built and where it runs. Chapter 4 presents them.

### 3.6.1 System Architecture

The architecture diagram shows the programs that connect, the interfaces they use, the parts of the engine, and the stores on disk.

### 3.6.2 Database Schema

The schema shows the records Burrow keeps: the index of the vault, the Ledger commits, the sessions, and how they refer to one another.

### 3.6.3 Wireframes

The wireframes show the main screens of the desktop application: the Ledger, the Watch panel and the Programs page.

### 3.6.4 Deployment Diagram

The deployment diagram shows the nodes on which the parts run and the connections between them.

## 3.7 Deliverables

### 3.7.1 The Burrow Engine

A Swift library that indexes a vault, keeps the Ledger, serves both through MCP, and checks changes against decisions.

### 3.7.2 The Programs and the Application

The burrow command-line program, its MCP server, hooks and setup commands for coding tools, and the Burrow desktop application for macOS.

### 3.7.3 The Evaluation Material

The Matatu fixture with its tasks and hidden tests, the scripts that ran each evaluation, and the saved transcripts and results.

### 3.7.4 Documentation

This report, a README and user guide, the record of design decisions, and the repository with its tagged releases.

## 3.8 Tools and Techniques

### 3.8.1 Swift and SwiftUI

Swift was used for the engine and the programs, and SwiftUI for the desktop application, because both run natively on the target Mac and need no separate runtime.

### 3.8.2 SQLite with FTS5

SQLite stores the index as one file inside the vault, and its FTS5 extension ranks pieces by word match with BM25 (SQLite, 2026; Robertson & Zaragoza, 2009). No database server is needed.

### 3.8.3 Ollama and Local Models

Ollama serves the local chat and embedding models on the same computer (Ollama, 2026). Gemma 4 12B and Qwen3 4B were the local models of the evaluation, and Qwen3 Embedding 0.6B gave the vectors for search by meaning (Gemma Team, 2026; Zhang et al., 2025).

### 3.8.4 Model Context Protocol

MCP is an open protocol through which an AI program discovers and calls the tools of a server (Model Context Protocol, 2026). Burrow is an MCP server, so any program that speaks MCP can use it without changes to that program.

### 3.8.5 AI Programs Used as Clients

Claude Code (Anthropic, 2026a), OpenCode, OpenClaw, Hermes Agent, n8n and the llama.cpp server were the programs that connected to Burrow in the evaluation. They were used as their makers ship them, with settings written only into each run's own folder.

### 3.8.6 Git and GitHub

Git kept the history of the engine and of this report, and GitHub held the repository, ran the automated tests on each push, and published the releases.
