# Chapter 4:  System Analysis and Design

## 4.1 Introduction

This chapter presents the analysis and design of Burrow and addresses the second specific objective. The system was analysed and designed with Object-Oriented Analysis and Design (OOAD), as justified in Section 3.3.1, and the diagrams use the Unified Modeling Language (UML). Section 4.2 gives the requirements. Section 4.3 presents the analysis diagrams: a use case diagram, a sequence diagram, an activity diagram and a class diagram. Section 4.4 presents the design diagrams: the system architecture, the logical schema, the wireframes and the deployment diagram. Chapter 5 describes how the design was built and tested.

## 4.2 System Requirements

The system requirements identified for this project are presented in the following subsections. Each requirement has an identifier, names the specific objective it serves, and names the test case of Section 5.6 that verifies it. No time limit was set in advance, because no measurement existed to justify one; where speed matters, the requirement is to measure it.

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

Table 4.2 lists the non-functional requirements. They cover privacy, durability, speed under load, safety, the person's control, and portability.

!tab Table 4.2: Non-functional requirements
!widths 0.75,4.1,0.8,0.75
| ID | Requirement | Objective | Verified by |
| NFR-01 | Privacy: the system shall send the person's material only to the local model service at the loopback address, and shall call no cloud model. | ii, iii | TC-13 |
| NFR-02 | Durability: no Ledger commit shall ever be overwritten or deleted, including when many programs keep decisions at the same second. | ii, iii | TC-14 |
| NFR-03 | Speed: the time to keep a decision and to search shall be measured with many programs writing at once, and reported. | iv, v | TC-14 |
| NFR-04 | Safety: text in the vault written to steer an AI shall be shown to the person and never handed over as a rule, and secrets shall be removed from what Burrow keeps of a session. | ii, iii | TC-15 |
| NFR-05 | Control: following a linked folder, sharing with a team and overriding a broken decision shall need the person, and shall be refused when asked by an AI program. | ii, iii | TC-16 |
| NFR-06 | Portability: the system shall build as one Swift package with no third-party dependency, and its tests shall run with one command on every push. | ii, iii | TC-17 |

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

Table 4.4 lists the interface and integration requirements: how programs and people reach the system, and what happens when a service it depends on fails.

!tab Table 4.4: Interface and integration requirements
!widths 0.75,4.1,0.8,0.75
| ID | Requirement | Objective | Verified by |
| IR-01 | The MCP server shall exchange JSON-RPC messages over standard input and output, in both the initialise-first form of the protocol and its 2026 stateless form. | ii, iii | TC-21 |
| IR-02 | One command shall set Burrow up in Claude Code, OpenCode, OpenClaw, Hermes Agent and n8n, keeping every other setting in each program's files. | ii, iii | TC-22 |
| IR-03 | If the local model service cannot embed a request, search shall continue on words alone. | ii, iii | TC-23 |
| IR-04 | The vault shall stay a folder that Obsidian can open, with links written between double square brackets. | ii, iii | TC-24 |

## 4.3 System Analysis Diagrams

This section presents the diagrams used to analyse the actors, the behaviour and the structure of the system. Each diagram is introduced, shown and then interpreted.

### 4.3.1 Use Case Diagram

Figure 4.1 shows the actors and the use cases. The person and the AI tool are the primary actors; a teammate receives what is shared, and the local model service supports search by meaning.

!fig figures/v5/use_cases.png | Figure 4.1: Use case diagram of Burrow | 6.0

The person owns the vault and the Ledger: they open the vault, review what was kept, and are the only actor who approves what an AI tool cannot decide alone. The AI tool never edits the Ledger directly; it finds, resumes, keeps and checks through Burrow's tools. Both finding and resuming include attaching the decisions that fit, so a tool meets a relevant decision whichever way it starts. Holding a change extends checking only when a decision is touched and has not yet been shown.

### 4.3.2 Sequence Diagram

Figure 4.2 shows one session of an AI tool with Burrow, from connecting to finishing, with the two ways a session can end.

!fig figures/v5/sequence_session.png | Figure 4.2: Sequence diagram of an AI tool resuming, looking up, changing and checking work through Burrow | 6.0

Decisions reach the tool three times: at connection, in the resume, and beside the excerpts of a lookup. The check happens before the tool reports to the person, so a change that goes against a decision is named while it can still be undone. A new decision is kept only after the change keeps to the old ones, and Burrow returns its identifier so the tool can cite it.

### 4.3.3 Activity Diagram

Figure 4.3 shows the activity of checking a change, across the AI tool, Burrow and the person.

!fig figures/v5/activity_check.png | Figure 4.3: Activity diagram of a change checked against the decisions it touches | 6.0

Three verdicts let a change through: no decision rests on its files, it leaves the parts a decision rests on unaffected, or it was already shown. A change that breaks a decision, or touches one not yet shown, is held, and the tool must tell the person which decision it touches and why. Only the person can overturn the decision, with a one-time code that appears in a notification on the Mac; the tool's other path is to undo its change.

### 4.3.4 Class Diagram

Figure 4.4 shows the main classes of the engine and their relationships.

!fig figures/v5/classes.png | Figure 4.4: Class diagram of Burrow's engine | 6.2

VaultTools is the single place where every tool call is handled, whichever interface it arrives through, so the protocol server, the hooks and the command line behave alike. A Ledger holds many commits; a commit may retire an earlier one, which is how a decision is replaced or marked wrong without deleting anything. A check report holds a verdict for each decision touched, and a verdict may carry a check that the person confirmed.

## 4.4 System Design Diagrams

This section presents the design of the system: its architecture, the records it keeps, its main screens and where it runs.

### 4.4.1 System Architecture

Figure 4.5 shows the architecture in four layers: the AI programs, the interfaces they use, the engine, and the stores on disk.

!fig figures/v5/architecture.png | Figure 4.5: Architecture of Burrow | 6.2

The programs need no change to use Burrow: they reach it through MCP, and the hooks reach it when a coding tool tries to finish. The engine is split into BurrowCore, which knows the vault, and BurrowTools, which knows the Ledger, sessions, the check and sharing. What must stay private to the person, such as approvals and the exact words of sessions, is kept in Burrow's own folder outside the vault, so that a vault received from someone else cannot carry approvals with it.

### 4.4.2 Logical Database Schema

Figure 4.6 shows the logical schema of what Burrow keeps, with keys and cardinalities.

!fig figures/v5/schema.png | Figure 4.6: Logical schema of the Ledger, sessions and the index | 6.2

A relational database was used only for the index, which can be rebuilt. The Ledger, sessions and checks are plain files, because they are the lasting record and the person must be able to read them without Burrow. A commit cites files by path and keeps a hash of each; comparing that hash with the file as it is now is how Burrow knows a decision needs checking again.

### 4.4.3 Wireframes

Figure 4.7, Figure 4.8 and Figure 4.9 show the three screens of the desktop application through which the person sees and governs what AI tools keep: the Ledger, the Watch panel and the Programs page.

!fig figures/v5/wire_ledger.png | Figure 4.7: Wireframe of the Ledger page | 6.0

The Ledger page opens with three counts that need attention: rules handed to every program, files changed under a decision, and lines flagged as written to steer an AI. Each commit shows its reason and its rejected options in full, with Still Right and Mark Wrong for the person.

!fig figures/v5/wire_watch.png | Figure 4.8: Wireframe of the Watch panel beside any page | 6.0

The Watch panel stays beside whatever page is open, so the person sees the same three things a connected program is shown, and a status light summarises them.

!fig figures/v5/wire_programs.png | Figure 4.9: Wireframe of the Programs page | 6.0

The Programs page reads each program's own settings and says whether it will find this vault, so the person can see at a glance which tool is connected and connect the others.

### 4.4.4 Deployment Diagram

Figure 4.10 shows where each part runs and how the parts connect.

!fig figures/v5/deployment.png | Figure 4.10: Deployment diagram of Burrow | 6.2

Everything Burrow does runs on the person's Mac. Burrow starts one server process for each program that connects, and talks only to the local model service at the loopback address. A cloud AI tool talks to its own provider, as it would without Burrow. The only network use by Burrow itself is the team remote, when the person shares a decision, and the one-time download of a release.
