# Chapter 4:  System Analysis and Design

## 4.1 Introduction

This chapter presents the analysis and design of Burrow and addresses the second specific objective. The system was analysed and designed with Object-Oriented Analysis and Design (OOAD), as justified in Section 3.3.1, and the diagrams use the Unified Modeling Language (UML). Section 4.2 gives the functional, non-functional, data and interface requirements and traces them to the components and tests that answer them. Section 4.3 presents the analysis diagrams: a use case diagram, two sequence diagrams, two activity diagrams, a state machine diagram and a class diagram. Section 4.4 presents the design diagrams: the system architecture, a component diagram, the logical schema, the wireframes with a screen flow, and the deployment diagram, drawn in the notation of UML 2.5.1 (Object Management Group, 2017). Chapter 5 describes how the design was built and tested.

## 4.2 System Requirements

The system requirements identified for this project are presented in the following subsections, written following the guidance of ISO/IEC/IEEE 29148 (International Organization for Standardization, 2018). Each requirement has an identifier, names the specific objective it serves, and names the test case of Section 5.5.2 that verifies it. No time limit was set in advance, because no measurement existed to justify one; where speed matters, the requirement is to measure it.

### 4.2.1 Functional Requirements

Table 4.1 lists the functional requirements. FR-01 and FR-02 cover the person's material, FR-03 to FR-08 cover the Ledger of decisions, FR-09 covers the check of new work, and FR-10 to FR-12 cover carrying work on, sharing and the desktop application.

!tab Table 4.1: Functional requirements
!widths 0.75,4.1,0.8,0.75
| ID | Requirement | Objective | Verified by |
| FR-01 | The system shall index a vault of Markdown notes, documents and linked code folders, and re-index only the files that changed. | ii, iii | TC-01 |
| FR-02 | The system shall rank pieces of the vault by word match and by meaning, and return excerpts with their file and line numbers. | ii, v | TC-02 |
| FR-03 | The system shall keep a decision only with a reason, together with the options rejected, the files it rests on with a hash of each, and the program that kept it. | ii, iii | TC-03 |
| FR-04 | The system shall hand the decisions in force to every program when it connects and again with its first tool result. | ii, v | TC-04 |
| FR-05 | The system shall attach to a search or a read the decisions that fit the request, chosen by meaning and by the files returned. | ii, v | TC-05 |
| FR-06 | The system shall give a program that resumes the plan, where the last session stopped, what it was in the middle of, and the latest decisions. | ii, v | TC-06 |
| FR-07 | The system shall mark a decision to be checked again when a file it rests on changes, and let the person confirm it or mark it wrong. | ii, iii | TC-07 |
| FR-08 | The system shall catch a new decision that overlaps one in force and ask whether it replaces it or stands beside it. | ii, iii | TC-08 |
| FR-09 | The system shall judge a change to linked code against each decision it touches (breaks, affected, unaffected or unprovable) and hold a change that touches a decision until it has been shown, through its own tool, a coding tool's end-of-turn hook, a git pre-commit hook and plugins for other programs. | ii, v | TC-09 |
| FR-10 | The system shall keep the exact words of a Claude Code session when it is compacted, and hand them back afterwards. | ii, v | TC-10 |
| FR-11 | The system shall share a decision with a team folder only after the person approves it, signed with the person and the program. | ii, iii | TC-11 |
| FR-12 | The desktop application shall show the Ledger, the Watch panel and the programs connected to the vault, and connect a program. | ii, iii | TC-12 |

### 4.2.2 Non-Functional Requirements

Table 4.2 lists the non-functional requirements. They cover privacy, durability, speed under load, safety, the person's control and portability, the characteristics of the ISO/IEC 25010 product quality model that matter for a memory kept on the person's own computer (International Organization for Standardization, 2023). Each is classed by the quality characteristic of that model it addresses.

!tab Table 4.2: Non-functional requirements
!widths 0.7,2.75,1.25,0.85,0.85
| ID | Requirement | Quality characteristic | Objective | Verified by |
| NFR-01 | Privacy: the system shall send the person's material only to the local model service at the loopback address, and shall call no cloud model. | Security | ii, iii | TC-13 |
| NFR-02 | Durability: no Ledger commit shall ever be overwritten or deleted, including when many programs keep decisions at the same second. | Reliability | ii, iii | TC-14 |
| NFR-03 | Speed: the time to keep a decision and to search shall be measured with many programs writing at once, and reported. | Performance efficiency | iv, v | TC-14 |
| NFR-04 | Safety: text in the vault written to steer an AI shall be shown to the person and never handed over as a rule, and secrets shall be removed from what Burrow keeps of a session. | Safety | ii, iii | TC-15 |
| NFR-05 | Control: following a linked folder, sharing with a team and overriding a broken decision shall need the person, and shall be refused when asked by an AI program. | Security | ii, iii | TC-16 |
| NFR-06 | Portability: the system shall build as one Swift package with no third-party dependency, and its tests shall run with one command on every push. | Flexibility | ii, iii | TC-17 |

### 4.2.3 Data Requirements

Table 4.3 lists the data requirements: what the system reads, what it keeps, and how evaluation data is kept apart from the memory.

!tab Table 4.3: Data requirements
!widths 0.75,4.1,0.8,0.75
| ID | Requirement | Objective | Verified by |
| DR-01 | The input shall be plain Markdown files and linked code folders, which the system reads and never changes. | ii, iii | TC-18 |
| DR-02 | Each Ledger commit shall be a readable Markdown file holding its identifier, branch, parent, kind, statement, reason, rejected options, author, program and the hashes of the files it cites. | ii, iii | TC-03 |
| DR-03 | Evaluation tasks, answer keys and hidden tests shall be kept outside the vault, so that no answer can be read from the memory under test. | iv, v | TC-19 |
| DR-04 | The index shall be rebuilt from the vault if it is deleted, with nothing lost. | ii, iii | TC-20 |

### 4.2.4 Interface and Integration Requirements

Table 4.4 lists the interface and integration requirements: how programs and people reach the system, how it reaches them, and what happens when a service it depends on fails.

!tab Table 4.4: Interface and integration requirements
!widths 0.75,4.1,0.8,0.75
| ID | Requirement | Objective | Verified by |
| IR-01 | The MCP server shall exchange JSON-RPC messages over standard input and output, in both the initialise-first form of the protocol and its 2026 stateless form. | ii, iii | TC-21 |
| IR-02 | One command shall set Burrow up in Claude Code, OpenCode, OpenClaw, Hermes Agent and n8n, keeping every other setting in each program's files. | ii, iii | TC-22 |
| IR-03 | If the local model service cannot embed a request, search shall continue on words alone. | ii, iii | TC-23 |
| IR-04 | The vault shall stay a folder that Obsidian can open, with links written between double square brackets. | ii, iii | TC-24 |
| IR-05 | The program and the desktop application shall install with one command from the project's GitHub releases, and the installer shall refuse a download whose SHA-256 checksum does not match. | ii, iii | Release check |
| IR-06 | A project website served over HTTPS from GitHub Pages shall link to the current release, the user guide and the source. | ii, iii | Release check |

### 4.2.5 Requirements Traceability

Every requirement links back to a specific objective, named in Tables 4.1 to 4.4, and forward to the diagrams that model it, the module that implements it and the test that verifies it. Table 4.5 groups the requirements by the module that answers them, so that a change to a requirement can be followed to the design, the code and the evidence it affects.

!tab Table 4.5: Traceability from requirements to diagrams, implementation and tests
!widths 1.2,1.6,1.1,1.2,1.3
| Module | Requirements | Diagrams | Implemented in | Verified by |
| Vault and index | FR-01, FR-02, DR-01, DR-04, IR-03, IR-04 | Figures 4.1, 4.5, 4.7, 4.8 | Section 5.4.1 | TC-01, TC-02, TC-18, TC-20, TC-23, TC-24 |
| Ledger | FR-03, FR-07, FR-08, NFR-02, DR-02 | Figures 4.6, 4.7, 4.10, 4.11 | Section 5.4.2 | TC-03, TC-07, TC-08, TC-14 |
| Connection | FR-04, FR-05, IR-01, IR-02 | Figures 4.2, 4.3, 4.9, 4.13 | Section 5.4.3 | TC-04, TC-05, TC-21, TC-22 |
| Check | FR-09 | Figures 4.2, 4.4 | Section 5.4.4 | TC-09 |
| Sessions and handover | FR-06, FR-10, NFR-04 | Figures 4.3, 4.10 | Section 5.4.5 | TC-06, TC-10, TC-15 |
| Team and approval | FR-11, NFR-05 | Figures 4.1, 4.15 | Section 5.4.6 | TC-11, TC-16 |
| Desktop application | FR-12 | Figures 4.11 to 4.15 | Sections 5.4.1 to 5.4.3 | TC-12 |
| Whole system and release | NFR-01, NFR-03, NFR-06, DR-03, IR-05, IR-06 | Figures 4.8, 4.16 | Sections 5.2 and 5.3 | TC-13, TC-14, TC-17, TC-19; release check |

## 4.3 System Analysis Diagrams

### 4.3.1 Use Case Diagram

Figure 4.1 shows who interacts with Burrow and what each of them can do with it. It sets the boundary of the system: everything inside the boundary is done by Burrow on the person's laptop, while the person, the AI tools they use, a teammate and the local model service act from outside it. The person and the AI tool are the primary actors; a teammate receives what is shared, and the local model service supports search by meaning. The diagram covers the goals behind FR-01 to FR-12 and the actions that NFR-05 reserves for the person.

!fig figures/v5/use_cases.png | Figure 4.1: Use case diagram of Burrow | 6.0

The person owns the vault and the Ledger: they open the vault, review what was kept, and are the only actor who approves what an AI tool cannot decide alone. The AI tool never edits the Ledger directly; it finds, resumes, keeps and checks through Burrow's tools. Both finding and resuming include attaching the decisions that fit, so a tool meets a relevant decision whichever way it starts. Holding a change extends checking only when a decision is touched and has not yet been shown.

### 4.3.2 Sequence Diagrams

Figure 4.2 follows one session of an AI tool with Burrow over time, from connecting to finishing. A sequence diagram was chosen because the order of the messages decides whether a decision reaches a model before it acts, which FR-04, FR-05, FR-06 and FR-09 require. Its scope is a single session and the two ways it can end: with the change and a new decision kept, or with the change held.

!fig figures/v5/sequence_session.png | Figure 4.2: Sequence diagram of an AI tool resuming, looking up, changing and checking work through Burrow | 6.0

Decisions reach the tool three times: at connection, in the resume, and beside the excerpts of a lookup. The check happens before the tool reports to the person, so a change that goes against a decision is named while it can still be undone. A new decision is kept only after the change keeps to the old ones, and Burrow returns its identifier so the tool can cite it.

Figure 4.3 widens the view to two sessions in two different programs, which is the case the study is about: a decision settled with a cloud model in Claude Code reaching a local model in OpenCode. It covers the hand-over of FR-04 and FR-06 and the keeping of a session's exact words in FR-10.

!fig figures/v5/sequence_handover.png | Figure 4.3: Sequence diagram of work carried from a cloud model in one program to a local model in another | 6.0

The two programs never speak to each other; everything passes through the vault. Claude Code's hooks let Burrow keep the session's requests, reasons and errors word for word when the context is compacted and to write a handoff when the session ends, without the model having to remember to do so. The second program receives the decisions in force with its first tool result, whether or not it shows its own connection instructions to the model, and its resume tells it what the last session was in the middle of, so it continues the right step with its constraint rather than starting again.

### 4.3.3 Activity Diagrams

Figure 4.4 shows the steps of checking a change, in lanes for the AI tool, Burrow and the person. An activity diagram was chosen because the check is a flow with branches and a loop rather than an exchange of messages, and it details FR-09 together with the override that NFR-05 keeps for the person.

!fig figures/v5/activity_check.png | Figure 4.4: Activity diagram of a change checked against the decisions it touches | 6.0

Three verdicts let a change through: no decision rests on its files, it leaves the parts a decision rests on unaffected, or it was already shown. A change that breaks a decision, or touches one not yet shown, is held, and the tool must tell the person which decision it touches and why. Only the person can overturn the decision, with a one-time code that appears in a notification on the Mac; the tool's other path is to undo its change.

Figure 4.5 shows the other half of the vault: how a question about the person's material is answered, in lanes for the person or program asking, Burrow's engine and the local model service. It details FR-02 and the path measured under the fourth objective, and its scope is one question from asking to the answer with its sources.

!fig figures/v5/activity_answer.png | Figure 4.5: Activity diagram of a question answered from the person's material | 6.0

The first branch is the most consequential: a question that needs no material, such as a reasoning problem, goes to the model without the vault, because irrelevant excerpts are known to harm reasoning. When the vault is needed, words and meaning are ranked together, links are followed when the closest files are code, and the decisions that fit are added with their reasons, so that knowledge and decisions arrive in one place. The amount shown is fitted to what the model can read in time, and the answer's citations are checked against what was shown before it reaches the person, with one corrected retry when a cited place was not among the excerpts.

### 4.3.4 State Machine Diagram

Figure 4.6 shows the states a decision passes through in the Ledger and the events that move it between them. A state machine diagram was chosen because a decision's handling depends on its state: a decision in force is handed to every program, one marked to check again is handed over with a warning, and a retired one is not handed over at all. The diagram covers FR-03, FR-07 and FR-08.

!fig figures/v5/states_decision.png | Figure 4.6: State machine diagram of a decision in the Ledger | 6.0

A decision enters the Ledger only with a reason. One that overlaps a decision already in force is refused once and shown the overlap, so the program must say whether it replaces the old one or stands beside it; if it says neither, both are kept and marked unresolved until the person chooses. A decision whose file changes is not dropped but marked to check again, because dropping it would let a small edit silently remove a rule, and the person returns it to force with Still Right. Every way out of force is a later commit, so the history is never rewritten.

### 4.3.5 Class Diagram

Figure 4.7 shows the main classes of Burrow's engine with their attributes, operations and relationships. It is the structural view of the objects that the use cases and the sequences rely on, and covers the vault and its index (FR-01, FR-02), the Ledger and its commits (FR-03, FR-07, FR-08), sessions (FR-06, FR-10) and the check (FR-09).

!fig figures/v5/classes.png | Figure 4.7: Class diagram of Burrow's engine | 6.2

VaultTools is the single place where every tool call is handled, whichever interface it arrives through, so the protocol server, the hooks and the command line behave alike. A Ledger holds many commits; a commit may retire an earlier one, which is how a decision is replaced or marked wrong without deleting anything. A check report holds a verdict for each decision touched, and a verdict may carry a check that the person confirmed.

## 4.4 System Design Diagrams

### 4.4.1 System Architecture

Figure 4.8 shows how Burrow is organised in four layers: the AI programs, the interfaces they use, the engine, and the stores on disk. It is the view from which the modules of Chapter 5 were built, and it shows how NFR-01 is met by keeping every part of Burrow on the person's laptop.

!fig figures/v5/architecture.png | Figure 4.8: Architecture of Burrow | 6.2

The programs need no change to use Burrow: they reach it through MCP, and the hooks reach it when a coding tool tries to finish. The engine is split into BurrowCore, which knows the vault, and BurrowTools, which knows the Ledger, sessions, the check and sharing. What must stay private to the person, such as approvals and the exact words of sessions, is kept in Burrow's own folder outside the vault, so that a vault received from someone else cannot carry approvals with it.

Figure 4.9 shows the engine inside that architecture as a pipeline, with what each step hands the next. A question that needs no vault goes straight to the model, a citation the model was not shown sends the answer back once, and nothing is written to the vault without the person's yes. It addresses FR-01, FR-02 and FR-04, and the decisions in force reach the model in the same step that finds the excerpts.

!fig figures/v5/engine_pipeline.png | Figure 4.9: The engine as a pipeline, from a question to a checked answer | 6.2

### 4.4.2 Component Diagram

Figure 4.10 shows the same system as UML components with the interfaces they provide and require. Where the architecture shows layers, this view shows the dependencies that the single Swift package of NFR-06 must respect, and how the three front ends share one engine.

!fig figures/v5/components.png | Figure 4.10: Component diagram of Burrow | 6.2

Every front end, the MCP server, the command line and the desktop application, uses the same VaultTools interface of BurrowTools, which in turn uses BurrowCore's vault; nothing depends upwards, so the engine can be tested without any front end. The only outward dependencies are the files on disk and the local model service at the loopback address. Hooks and plugins in other programs do not link Burrow's code at all: they call the command line, which keeps them working across Burrow's releases.

The interface every program meets is the MCP server. Table 4.6 gives its contract for the five tools a program is shown by default: what each takes, what it returns and whether it writes. The seventeen further tools that a program can be shown on request follow the same pattern and are listed in the repository's tool reference.

!tab Table 4.6: Interface contract of the MCP server's default tools
!widths 1.15,1.9,2.55,0.75
| Tool | Takes | Returns | Writes |
| burrow_find | A query in plain words; optionally a folder | Excerpts with file and line, a line saying how much the vault holds on it, and the decisions that fit the request | No |
| burrow_read | A path; optionally the first line and how many lines | The file with line numbers, and the decisions on it and on the files it imports or is imported by | No |
| burrow_resume | Optionally a branch | The plan, where the last session stopped and what it was in the middle of, corrections and the latest decisions | No |
| burrow_commit | A kind and a message; for a decision its reason, and optionally what was rejected, the files, a check and the decision it replaces | The identifier it was kept as, or a refusal naming an overlapping decision in force | Adds only |
| burrow_check | Nothing | The change in linked code beside each decision resting on it, with a verdict: unaffected, affected, unprovable or breaks | No |

### 4.4.3 Logical Database Schema

Figure 4.11 shows the logical schema of what Burrow keeps: the commits of the Ledger, the sessions and checks, and the index of the vault, with their keys, relationships and cardinalities. It addresses DR-02 and DR-04 and the durability that NFR-02 requires.

!fig figures/v5/schema.png | Figure 4.11: Logical schema of the Ledger, sessions and the index | 6.2

A relational database was used only for the index, which can be rebuilt. The Ledger, sessions and checks are plain files, because they are the lasting record and the person must be able to read them without Burrow. A commit cites files by path and keeps a hash of each; comparing that hash with the file as it is now is how Burrow knows a decision needs checking again.

### 4.4.4 Wireframes and Screen Flow

Figure 4.12, Figure 4.13, Figure 4.14 and Figure 4.15 show the four screens of the desktop application through which the person reads the vault and governs what AI tools keep, as FR-12 requires: the Ledger, the Watch panel, the Programs page and the Ask page. They show the layout and the controls each screen needs.

!fig figures/v5/wire_ledger.png | Figure 4.12: Wireframe of the Ledger page | 6.0

The Ledger page opens with three counts that need attention: rules handed to every program, files changed under a decision, and lines flagged as written to steer an AI. Each commit shows its reason and its rejected options in full, with Still Right and Mark Wrong for the person.

!fig figures/v5/wire_watch.png | Figure 4.13: Wireframe of the Watch panel beside any page | 6.0

The Watch panel stays beside whatever page is open, so the person sees the same three things a connected program is shown, and a status light summarises them.

!fig figures/v5/wire_programs.png | Figure 4.14: Wireframe of the Programs page | 6.0

The Programs page reads each program's own settings and says whether it will find this vault, so the person can see at a glance which tool is connected and connect the others.

!fig figures/v5/wire_ask.png | Figure 4.15: Wireframe of the Ask page | 6.0

The Ask page keeps what the model wrote apart from what it was given: the answer cites each place it used, the decision line says whether the vault was read and why, the files used are listed in order, and a warning appears only when a cited place was not among them. The map beside the answer lights up the files read, so the person can see where an answer came from.

Figure 4.16 joins the screens into the journey of a person's first hour with Burrow, from installing it to reviewing a decision an AI program kept, with the alternative paths when the local model service is not running or a linked folder has not been approved.

!fig figures/v5/screen_flow.png | Figure 4.16: Screen flow of a person's first use of Burrow | 6.0

The flow shows that the person's own actions are few and come at the points where trust is decided: choosing the vault, approving a linked folder, connecting a program, and reviewing what was kept. Everything between them is done by the AI programs through Burrow, and each alternative path ends in an explanation rather than a silent failure.

### 4.4.5 Deployment Diagram

Figure 4.17 shows the machines on which each part of Burrow runs and how the parts connect. It addresses NFR-01, by showing what leaves the laptop and what does not, the single-package build of NFR-06, and the release and project website of IR-05 and IR-06.

!fig figures/v5/deployment.png | Figure 4.17: Deployment diagram of Burrow | 6.2

Everything Burrow does runs on the person's Mac. Burrow starts one server process for each program that connects, and talks only to the local model service at the loopback address. A cloud AI tool talks to its own provider, as it would without Burrow. The only network use by Burrow itself is the team remote, when the person shares a decision, and the one-time download of a release from GitHub, whose installer checks each file's checksum; the project website on GitHub Pages points to that release and to the user guide.
