# Acknowledgement

First and foremost, I thank God for the guidance, strength, and good health that carried me through this work. I am sincerely grateful to my supervisor, Mr. Tiberius Tabulu, for his steady guidance, patience, and constructive feedback, which shaped the direction of this project from the proposal to the finished system. I also thank the faculty of the School of Computing and Engineering Sciences at Strathmore University for the foundation they have given me. Finally, I am deeply thankful to my family and friends for their encouragement and unwavering support throughout this journey.

# Abstract

Cloud language models are highly capable, but every request costs money and sends the user's data off the device, while small models on a consumer laptop are private and free but weaker, most visibly on knowledge they have not memorised. Both kinds of model also share a second weakness: they keep nothing between sessions, so what a person settled with one tool, and why, is lost to the next.

To address these challenges, this study designed, developed and evaluated Burrow, a local vault that gives local and cloud language models one shared memory. Burrow keeps the person's notes, documents and code on their own computer, with a ledger of the decisions AI tools make with the person and their reasons, and any model reaches it through the Model Context Protocol. Following Design Science Research, it was built in Swift with SQLite and evaluated on 120 knowledge questions and on coding tasks with hidden tests.

With Burrow, a local model answered 102 of the 120 knowledge questions, against 9 alone and 75 with a vector database, close to the cloud model given the same memory (109). Once reasons were kept with decisions, a cloud coding model kept to an earlier decision in all 9 runs, and a local model in a different program carried earlier work on in 3 of 3 runs, against none before. A shared local memory therefore narrows the gap between local and cloud models and lets them build on each other's work.

***Keywords: on-device language models, external memory, shared memory, retrieval-augmented generation, Model Context Protocol***

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
API - Application Programming Interface
BM25 - Best Matching 25
CAMR - Capability-Adaptive Memory Retrieval (the engine's earlier name)
DR - Data Requirement
FR - Functional Requirement
FTS5 - Full-Text Search version 5 (SQLite)
GB - Gigabyte
GPT - Generative Pre-trained Transformer
GSM8K - Grade School Math 8K
HTTPS - Hypertext Transfer Protocol Secure
ID - Identifier
IEC - International Electrotechnical Commission
IEEE - Institute of Electrical and Electronics Engineers
IR - Interface and Integration Requirement
ISO - International Organization for Standardization
JSON - JavaScript Object Notation
JSON-RPC - JSON Remote Procedure Call
KB - Kilobyte
MCP - Model Context Protocol
NFR - Non-Functional Requirement
OOAD - Object-Oriented Analysis and Design
RAG - Retrieval-Augmented Generation
RETRO - Retrieval-Enhanced Transformer
SHA-256 - Secure Hash Algorithm with a 256-bit digest
SMART - Specific, Measurable, Achievable, Relevant and Time-bound
SSD - Solid-State Drive
TC - Test Case
UML - Unified Modeling Language
US$ - United States dollar
