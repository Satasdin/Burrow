# Acknowledgment

I thank God for the strength and good health that carried me through this work. I am grateful to my supervisor, Mr. Tiberius Tabulu, whose patient guidance and honest feedback shaped this project from its first idea to the finished system. I thank the faculty of the School of Computing and Engineering Sciences at Strathmore University for the foundation they gave me, and the Sprint II review panel for asking for something a person can see and use. Finally, I thank my family and friends for their encouragement and support throughout this journey.

# Abstract

People now work with several artificial intelligence (AI) tools at once: a cloud coding assistant, a local model kept private, an automated workflow. A decision reached with one tool, and the reason for it, does not reach the next, which then brings back options already rejected, and nothing warns the person.

This study designed, developed and evaluated Burrow, a private memory engine on the person's own Mac. AI tools record each decision in it with its reason and the files it rests on; Burrow hands the decisions to every tool that connects through the Model Context Protocol, marks them when their files change, and checks a change against them before the work is done. Following Design Science Research, Burrow was built in Swift with an embedded database and tested with six real AI programs on a fixture project with hidden tests and on 120 knowledge questions.

A local model answered 102 knowledge questions with Burrow, against 9 alone and 75 with a vector database. Once reasons were kept, Claude Code kept to an earlier decision in 9 of 9 runs, against 12 of 15 before; another program carried earlier work on in 3 of 3 runs, against none; and every change that broke a decision was held. A small model sometimes broke a decision it had read: memory delivers decisions, and a check at the end makes tools keep them.

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
