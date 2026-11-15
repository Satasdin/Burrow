# Acknowledgment

I thank God for the strength and good health that carried me through this project. I am sincerely grateful to my supervisor, Mr. Tiberius Tabulu, for his guidance, his honest feedback at every stage and the time he gave to reviewing this work; his comments on the proposal and during the sprint reviews shaped both the system and this report. I also thank Strathmore University and the School of Computing and Engineering Sciences for the opportunity to undertake this project and for the instruction in research writing that guided its documentation. Finally, I thank my family for their encouragement and support throughout my studies.

# Abstract

Artificial intelligence (AI) tools are now used together on the same work, often a cloud coding assistant alongside a local model chosen for privacy. Each tool starts from what its own program supplies, so a decision reached with one tool, and its reason, is lost to the next, which then brings back options already rejected.

This study designed, developed and evaluated Burrow, a private memory engine that runs on the person's own computer. AI tools record each decision in it with its reason and the files it rests on; Burrow hands the decisions to every tool that connects through the Model Context Protocol and checks new work against them. Following Design Science Research, Burrow was built in Swift with an embedded SQLite index and evaluated with six AI programs, including Claude Code, OpenCode and n8n, on a fixture project with hidden tests and on 120 knowledge questions.

With Burrow, a local model answered 102 of 120 questions on private material, against 9 without it and 75 with a vector database. Once reasons were kept, Claude Code kept to an earlier decision in all 9 runs, against 12 of 15 before; another program carried earlier work on in 3 of 3 runs, against none; and every change that broke a decision was held. A shared memory of decisions and their reasons therefore helps AI tools keep earlier decisions, while a final check is still needed where a model does not follow them.

***Keywords: AI coding tools, agent memory, design decisions, Model Context Protocol, on-device language models***

# Table of Contents

!toc TOC \o "1-3" \h \z \u

# List of Figures

!toc TOC \h \z \c "Figure"

# List of Tables

!toc TOC \h \z \c "Table"

# List of Equations

!toc TOC \h \z \c "Equation"

# List of Abbreviations

ADR - Architecture Decision Record
AI - Artificial Intelligence
BM25 - Best Matching 25
DSR - Design Science Research
FTS5 - Full-Text Search version 5 (SQLite)
GSM8K - Grade School Math 8K
JSON - JavaScript Object Notation
JSON-RPC - JSON Remote Procedure Call
MCP - Model Context Protocol
OOAD - Object-Oriented Analysis and Design
RAG - Retrieval-Augmented Generation
SSD - Solid-State Drive
UML - Unified Modeling Language
