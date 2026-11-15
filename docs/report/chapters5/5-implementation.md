# Chapter 5:  System Implementation, Testing and Evaluation

## 5.1 Introduction

This chapter explains how the design of Chapter 4 was implemented, tested and evaluated, and addresses the third, fourth and fifth specific objectives. It describes the environment in which Burrow was built and run, the data used to evaluate it, and each module in the order of the architecture in Figure 4.8. It then sets out the test strategy, the test cases with the defects found and retested, the evaluation of Burrow against its baselines with its ablation, errors, security and robustness, and the check of its installation, followed by the repository and the use of AI-assisted tools. The chapter ends with the evaluation results, their discussion and the limitations of the study.

## 5.2 Implementation Environment

Burrow was developed, tested and evaluated on one consumer laptop, which served as both the development and the test environment, with the local models running in Ollama on the same machine. The automated tests also ran on a hosted machine on every push to the repository. Burrow was not deployed as a hosted service: it is a program that a person installs and runs on their own Mac.

### 5.2.1 Hardware and Deployment Environment

Table 5.1 lists the hardware on which Burrow was built and evaluated, the minimum it declares, and the evidence for each.

!tab Table 5.1: Hardware and deployment environment
!widths 1.1,1.9,2.0,1.4
| Item | Tested specification | Purpose and justification | Evidence or source |
| Laptop | Apple MacBook Pro, M5 Pro chip, 24 GB of shared memory, macOS 27.2 | Runs Burrow, the AI tools and the local models together, as a person would on their own computer; 24 GB held Gemma 4 12B with room for the vault | Every timing in Section 5.5.4 |
| Declared minimum | Apple silicon with macOS 14 or later for the program and server; macOS 26 or later for the desktop application | The oldest systems the build targets; only macOS 27.2 was tested | Project README |
| Storage | The laptop's internal SSD | The vault, the Ledger and the index are files on the person's own disk | TC-20 |
| Graphics | The chip's built-in graphics processor | Used by Ollama to run the local models; no separate graphics card is needed | Ollama runs in Section 5.5.4 |
| Network | Home internet connection | Needed only to download models, for cloud AI tools to reach their provider, and for team sharing; Burrow itself works offline | TC-13 |
| Test runner | GitHub-hosted Apple silicon machine | Runs the automated tests on every push, on a machine other than the developer's | TC-17 |

### 5.2.2 Software, Services and Configuration

Table 5.2 lists the software, AI tools and models used, with the versions that were tested and the role of each.

!tab Table 5.2: Software specifications
!widths 1.7,1.8,2.8
| Software | Version | Role |
| macOS | 27.2 | Operating system of the laptop |
| Swift | 6.4.2 | Language of the engine, the command line, the application and the tests |
| SQLite with FTS5 | 3.54.0 | The index of the vault: word search, vectors and links |
| Ollama | 0.40.16 | Runs the local chat and embedding models at the loopback address |
| Gemma 4 12B, Qwen3.5 4B, Qwen3 4B | gemma4:12b, qwen3.5:4b, qwen3:4b-instruct | Local models: Gemma 4 12B and Qwen3.5 4B in the knowledge evaluation, Qwen3 4B in other runs with AI programs |
| Qwen3 Embedding 0.6B | qwen3-embedding:0.6b | Turns text into vectors for search by meaning |
| Claude Code | 2.1.322, with Claude Opus 5.5 | Cloud coding tool connected through MCP and hooks |
| OpenCode, OpenClaw, Hermes Agent | 1.19.5, 2026.11.3, 0.23.1 | Other AI programs connected through MCP and plugins |
| n8n | 2.47.7 | Workflow platform whose support agent used Burrow |
| Chroma | 1.5.9 | Vector database used as a baseline |

Burrow is built as one Swift package with no third-party dependency (NFR-06). It reaches Ollama only at the loopback address and calls no cloud model itself (NFR-01). Each AI program was connected by the command burrow connect, which adds Burrow's server, its plugin or hook, and nothing else to that program's own settings files, keeping a backup of each (IR-02). The cloud runs used Claude Code under a Claude subscription; no key, token or other secret appears in this report or in the repository.

### 5.2.3 Deployment and Reproducibility

Burrow is installed with one command that downloads the latest release from the project's GitHub page and places the burrow program on the path; adding the option for the application installs the desktop application as well. It can also be built from source with swift build and tested with swift test, which runs all 553 automated tests. Before use, the embedding model and a local chat model are pulled into Ollama. A vault is opened by pointing the burrow index command or the application at a folder of Markdown notes, code folders are linked to it with burrow link, and an AI program is connected with burrow connect followed by the program's name. A simple check that the installation works is to search the vault with burrow find, which shows what a model would read without calling one, and to start a session in a connected program, which receives the decisions in force with its first tool result. The evaluations can be repeated from the trials folder, whose scripts build the fixed starting point of Section 5.3.2 and save each run's transcript and results; the runs with Claude Code need a Claude subscription, and all other runs need no paid service. The final build is published as the release burrow-v1.2.1 (https://github.com/Satasdin/Burrow/releases/tag/burrow-v1.2.1), with the program, the application, the installer and their SHA-256 checksums.

## 5.3 Dataset Description and Preparation

### 5.3.1 Dataset Description

The evaluation used two kinds of data. The first was a vault of 87 real documents assembled for the study on three subjects: Kenya's Data Protection Act and its regulations, which are public law; documentation of software released in 2026, which is public; and the notes of a private software project written by the author. From these documents, 120 knowledge questions were written, 40 on each subject, of which 25 need one fact and 15 need facts from two files, each with an answer key and the passage that supports it, as Table 3.1 shows. Fifty reasoning problems were drawn from the public GSM8K benchmark (Cobbe et al., 2021) to check that memory would be left out where it was not needed.

The second was Matatu, a fixture project written for the study to test decisions. Matatu is a Python service of about 1,500 lines that records matatu fares paid by M-Pesa and matches each payment on a statement to its ticket. It came with written tasks, hidden tests that the AI tools could not read, and one business decision with a reason: payments are matched to tickets by account reference only, because conductors often pay for a whole group from one phone, and on one Easter Monday an older rule that matched by phone and amount had marked 31 tickets paid against the wrong passengers. A later task asks for unmatched payments to be handled, which tempts a tool to bring the rejected rule back. Two further sets were built on the fixture: 20 tasks worded unlike the payment decision, with 40 unrelated decisions in the Ledger, to test whether the decision is found, and 30 questions about an earlier session, to test whether its work is carried on. Table 5.3 summarises the data. The law and the software documentation are real public texts and the project notes are the author's own, but the rest of the data is synthetic: the knowledge questions and their answer keys, the Matatu project with its passengers, payments, tasks and hidden tests, the 40 unrelated decisions and the session questions were all written for the study, by the author or by Claude Code agents at the author's direction. No data about any real person was used.

!tab Table 5.3: Data used in the evaluation
!widths 1.2,2.6,1.1,1.4
| Data | What it holds | Size | Used for |
| Knowledge vault | Kenyan data protection law, 2026 software documentation and a private project's notes | 87 files; 120 questions | Finding the right material |
| Reasoning problems | Problems from the GSM8K test split | 50 problems | Checking that memory is left out when not needed |
| Matatu fixture | A fare-payment service with a recorded decision, tasks and hidden tests | About 1,500 lines; 4 tasks | Keeping decisions and checking changes |
| Decision wording set | Tasks worded unlike the decision, with unrelated decisions in the Ledger | 20 tasks; 40 decisions | Finding a decision |
| Session questions | Questions about what an earlier session did and was doing | 30 questions | Carrying work on |

### 5.3.2 Data Preparation and Partitioning

The documents were converted to Markdown and placed in one vault, so that two subjects stood as distractors for the third, and Burrow indexed the vault before any scored run. The knowledge questions were written from the documents by Claude Code agents, and a script checked every answer key against the text of the vault and rejected any question whose key appeared in the question itself. The reasoning problems were drawn once from the GSM8K test split with a fixed random seed.

Because no model was trained, no training split was needed; instead, every question, answer key and hidden test was held out from both the vault and the setting of Burrow. Burrow's thresholds, such as the weights that choose which decisions to attach to a search, were set on queries written for that purpose and not on the scored tasks, and the decision wording test was registered with its scoring rule before it was run. Every evaluation started from a fixed base built by a script, in which a first session by Claude Code had kept the payment decision in the Ledger; the first session's task brief was then removed, so that later sessions could learn of the decision only through Burrow. The full transcript of every run was read to confirm that no tool found the answer elsewhere, and one run in which a tool could have read the answer from a stray file was set aside and not counted.

## 5.4 System Implementation

### 5.4.1 Vault and Index Module

This module turned an ordinary folder of Markdown notes and documents into a vault that AI tools could search, with code folders linked in read-only, and implements FR-01, FR-02, DR-01, DR-04, IR-03 and IR-04. It split each file at its headings or code boundaries, indexed the pieces by their words with SQLite's FTS5 and by their meaning with vectors from the embedding model, and kept the links between files, so that a search returned excerpts with their file and line. For a question put to a local model, the engine first decided whether the vault was needed at all, then searched by words and by meaning, merged the two rankings, followed links to related files, and fitted the excerpts to the amount that the model could read in time, which was measured once for each model: 17,417 characters for Gemma 4 12B on the laptop. The excerpts were given to the model with their file and line, and the answer's citations were checked against what it had been shown. If the embedding service was unavailable, search continued on words alone (TC-23), and the index could be deleted and rebuilt from the files with nothing lost (TC-20).

A linked folder named in a vault was read only after the person allowed it on their own computer, which stopped a vault received from someone else from opening the person's other folders. Figure 5.1 shows a vault in the desktop application, and Figure 5.2 shows the request that appears before a linked folder is read.

!fig figures/screens4/app-graph.png | Figure 5.1: The map of a vault in the desktop application, coloured by folder | 6.2

!fig figures/v5/approve-folder.png | Figure 5.2: The application asking the person before it reads a folder that a vault links | 4.8

The engine's decision about the vault can be seen on the command line. In Figure 5.3 the question is a sum, so the engine left the vault out, because nothing in it was close enough, and gave the model the method for working a calculation; the lines under the answer say that nothing was read. In Figure 5.4 the question is about Ugandan law, which the vault does not hold. The engine still searched, because the closest files are about data protection, and the model said that it did not know from what it was shown, while the lines below list the files it read. Figure 5.5 shows what Burrow turns a question into before any model reads it: short rules, then excerpts marked with their file and line, which is why an answer can name the line it rests on.

!fig figures/screens4/console-sum.png | Figure 5.3: A sum answered with the vault left out, on the command line | 6.2

!fig figures/screens4/console-miss.png | Figure 5.4: A question the vault could not answer, and the model saying so | 6.2

!fig figures/workflow/what-the-model-reads.png | Figure 5.5: The text Burrow hands a model for a question: rules, then excerpts marked with file and line | 6.2

### 5.4.2 Ledger Module

The Ledger module kept what AI sessions decided, one Markdown file per commit, on branches like git, and implements FR-03, FR-07, FR-08, NFR-02 and DR-02. A decision was refused without a reason, and it was stored with the options rejected, the files it rests on with a hash of each, and the name of the program that kept it, taken from the program's connection rather than from what the model said about itself. No commit was ever changed or deleted; a later commit retired it, either as a replacement or as a correction, and a new decision that overlapped one in force was refused until the program said whether it replaced it or stood beside it. When a file that a decision rests on changed, the decision was still handed over, marked to be checked again, until the person confirmed it with Still Right or marked it wrong. Figure 5.6 shows the Ledger page with decisions kept during a team run by two simulated teammates and by Claude Code.

!fig figures/v5/app-ledger-team.png | Figure 5.6: The Ledger page, with each decision's reason, the person or program that kept it, and its branch | 6.2

### 5.4.3 Connection Module

This module let any AI program reach Burrow through its MCP server and implements FR-04, FR-05, IR-01 and IR-02. The server offered five tools, burrow_resume, burrow_find, burrow_read, burrow_commit and burrow_check, and spoke both the earlier form of the protocol, which begins with a handshake, and its stateless 2026 form. One command set Burrow up in Claude Code, OpenCode, OpenClaw, Hermes Agent or n8n while keeping every other setting in that program's files. A search or a read also carried the decisions that fit the request, chosen by how close their words were to it and how highly the files they rest on ranked, rather than by date. The design handed the decisions in force to a program when it connected; because OpenClaw and Hermes Agent were found never to pass a server's connection instructions to their model, the implementation also sent them, once, with each connection's first tool result. Figure 5.7 shows an n8n support workflow whose agent, running on a local model, uses Burrow as a tool, and Figure 5.8 shows that agent receiving decisions that Claude Code had kept earlier.

!fig figures/v5/n8n-canvas.png | Figure 5.7: An n8n support workflow whose agent, on a local model through Ollama, uses Burrow as an MCP tool | 6.2

!fig figures/v5/n8n-resume.png | Figure 5.8: The n8n agent's burrow_resume call returning decisions kept earlier by Claude Code | 6.2

### 5.4.4 Check Module

The check module implements FR-09. It compared the linked code with its last git commit, set aside files that only a build makes, and judged each decision the change touched: a change broke a decision when the check the person had set for it failed, affected it when it changed the parts of the code the decision rests on, and left it unaffected otherwise. The same check ran when a model called burrow_check, when Claude Code tried to end its turn, when a git commit was made, and inside OpenCode, OpenClaw and Hermes Agent through plugins, so a model could not skip it. A change that broke a decision was held until it was undone or the person overrode the decision. Figure 5.9 shows the pre-commit hook passing a harmless change and refusing one that broke the payment decision.

!fig figures/v5/console-gate.png | Figure 5.9: The git pre-commit hook passing a harmless change and refusing one that breaks a decision (real output, shortened) | 6.2

### 5.4.5 Sessions and Handover Module

This module implements FR-06, FR-10 and NFR-04. It kept each connection as its own conversation with a trail of what it looked up and kept, so that the next program could resume where the last one stopped. For Claude Code, it also kept the exact words of each part of a session when the session was compacted, including the person's requests and the last error as printed, and handed them back afterwards. A different program that resumed was told what the last session had been in the middle of, and keys, tokens and passwords were removed from everything kept. Text in the vault written to steer an AI was flagged to the person and never handed over as a rule.

### 5.4.6 Team and Approval Module

The team module implements FR-11 and NFR-05. It let a small team share decisions through a folder they all had, either a git repository or a synced folder, with each decision signed by the person and the program that kept it. Anything an AI tool wanted to share waited until the person had read and approved it; in the first real run this caught a decision in which the model had written "Finance and product agreed" where the person had said "Finance and I". Approving a share or a linked folder, and overriding a broken decision, were refused when requested from inside an AI program, and an override also needed a one-time code shown in a macOS notification.

## 5.5 Testing and Evaluation

### 5.5.1 Test Strategy and Acceptance Criteria

Testing set out to show that each requirement of Chapter 4 was met, and evaluation set out to show whether the fourth and fifth objectives were achieved. Unit tests checked individual components from their internal logic, as white-box tests, such as the rebuilding of the index and the rule that a commit is never overwritten. Integration tests checked the interfaces between components and with real programs, such as both forms of the MCP protocol and the setting up of each program's files. System tests exercised Burrow end to end as a person and their AI tools would use it, as black-box tests. The cases covered normal use, wrong input, boundary cases and hostile input, such as a vault received from someone else, crafted settings files and text written to steer an AI.

A test case passed only when its observed result matched an expected result written before it was run. The acceptance criterion for the build was that every automated test passed, on the laptop and on the hosted machine. For the evaluations, the scoring rules were written before the scored runs, and each result was reported as a count with its sample size.

### 5.5.2 Test Cases, Defects and Retesting

All 553 automated tests, 530 XCTest and 23 Swift Testing tests, passed on the final build of 15 November 2026, and every push to the repository ran them again on the hosted machine. Table 5.4 shows the main system test cases, each traced to the requirement it verifies; the full record of 24 cases is in the repository (https://github.com/Satasdin/Burrow/blob/burrow/docs/evaluation/test-cases.md).

!tab Table 5.4: System test cases and results
!widths 0.6,1.0,1.7,1.55,1.55
| Test ID | Traceability | Scenario and data | Expected result | Actual result, evidence and verdict |
| TC-01 | FR-01 | A vault indexed twice, then with one file changed and one removed | Nothing rebuilt the second time; old words gone the third | As expected; BurrowCoreTests; Pass |
| TC-03 | FR-03, DR-02 | A decision kept with no reason, then with a reason, rejected options and two files | First refused; second stored with reason, files and hashes, signed by the program | As expected; LedgerTests; Pass |
| TC-04 | FR-04 | A program connects in each protocol form and calls a tool | Decisions in force with the first result, once, each reason whole | As expected; DualEraMCPTests; Pass |
| TC-06 | FR-06 | A different program resumes after a Claude Code session stopped mid-task | Plan, where it stopped, what it was in the middle of, latest decisions | As expected; MidwayTests; 3 of 3 real runs; Pass |
| TC-07 | FR-07 | A file a decision cites is edited; the person says it still holds | Decision marked check again; Still Right clears it | As expected; LedgerTests; Pass |
| TC-08 | FR-08 | A decision overlapping one in force, first without saying which holds | Refused once; with a replacement named, the old one retired | As expected; ContradictionTests; Pass |
| TC-09 | FR-09 | Breaking and harmless changes through the tool, the Stop hook, the pre-commit hook and the plugins | Breaks refused every time; harmless changes pass | As expected; GateTests; Figure 5.9; Pass |
| TC-10 | FR-10 | A Claude Code session compacted, then asked for the error line | The exact line quoted | 6 of 6 runs; FoldTests; Pass |
| TC-11 | FR-11 | An AI shares a decision with the team; two people commit at once | Held until the person approves; no conflict | As expected; TeamTests; Pass |
| TC-14 | NFR-02, NFR-03 | 32 programs keep 50 decisions each at once | 1,600 kept, none lost; times reported | 1,600 of 1,600; median 0.003 s; Pass |
| TC-16 | NFR-05 | An AI program asks to approve a folder, approve a share and override a decision | All refused, naming the reason | As expected; PersonPresenceTests; Pass |
| TC-23 | IR-03 | The embedding service stopped during a search | Search continues on words alone | As expected; ToolsTests; Pass |

The test cases pass on the final build, but several of them failed when Burrow was first used with real programs on 14 November 2026, and those failures were recorded, corrected and retested rather than hidden. Table 5.5 lists the main defects.

!tab Table 5.5: Defects found in real use, corrections and retests
!widths 1.9,2.4,1.9
| Defect found | Correction | Retest |
| A decision's reason was cut off when a long result was shortened | The reason is never shortened; the rejected options are shortened first | Each reason whole in every result (TC-04) |
| Editing any file a decision cites dropped the decision from what programs were handed | The decision is still handed over, marked to check again, until the person confirms it | TC-07 passed |
| A commit's author was whatever name the model typed, and a local model signed itself "claude-code" | The author is taken from the connected program; the model's claim is kept beside it | TC-03 passed |
| Separate runs within half an hour merged into one conversation | Each connection is its own conversation | Automated session tests passed |
| The check counted files made by a test run as changes | Build output is set aside, and the list is kept narrow so real files cannot hide | TC-09 passed |
| Two programs never passed the decisions sent at connection to their model | The decisions are also sent with each connection's first tool result | Reached OpenClaw's model in 4 of 5 runs |

### 5.5.3 Evaluation Set-ups, Baselines and Metrics

No model was trained. Each evaluation gave the same AI tool the same task with Burrow and with a baseline in its place, as Table 5.6 lists. Where an improvement to Burrow was measured, the baseline was Burrow before the improvement, run from the same starting point. In the knowledge evaluation, plain retrieval and the Chroma vector database were each shown 12,000 characters of the vault, while Burrow's engine was shown up to the 17,417 characters fitted for Gemma 4 12B.

!tab Table 5.6: Evaluation set-ups and baselines
!widths 1.3,2.0,1.6,1.6
| Evaluation | Task | Burrow set-up | Baselines |
| Finding material | 120 knowledge questions on the vault | Gemma 4 12B with Burrow | Model alone; plain retrieval; Chroma vector database; cloud model alone and with Burrow |
| Finding a decision | 20 oddly worded Matatu tasks, 40 unrelated decisions | Decisions ranked by relevance | Newest decisions first; plain vector search |
| Keeping a decision | Second Matatu session, scored by hidden tests | Claude Code and Gemma 4 12B with Burrow | Burrow before reasons were kept |
| Carrying work on | A new session asked about, or told to continue, the last one | Burrow's resume, kept words and handover | Nothing; the session tools; the pasted transcript; the old handoff |
| Checking changes | Changes that keep or break the decision | Verdicts, hooks and plugins | The same programs without the check |

Each result was counted as the number of runs or questions that met the scoring rule out of those attempted, as Equation 5.1 shows. A knowledge answer was right when it contained every part of its answer key, a decision was kept when both hidden decision tests passed, and work was carried on when the next session continued the right step with its constraint. Where two set-ups were run on the same items, they were compared with the exact sign test in Equation 5.2, where b and c are the items that only one of the two got right.

!eq accuracy | Equation 5.1: Share of runs or questions that met the scoring rule

!eq sign | Equation 5.2: Exact two-sided sign test on paired results

### 5.5.4 Evaluation Results

On finding material, Figure 5.10 shows that Gemma 4 12B answered 9 of the 120 knowledge questions alone and 102 with Burrow, against 94 with plain retrieval and 75 with a Chroma vector database, while the cloud model answered 40 alone and 109 when given the same vault. By Equation 3.1, Burrow closed 93% of the knowledge gap between the local model and the cloud model given the same memory, against 85% for plain retrieval, at a cost of 9.2 seconds per answer against 8.3. Against plain retrieval, Burrow gained 10 questions and lost 2 (p = 0.039), and against Chroma it gained 34 and lost 7 (p < 0.001). On the 50 reasoning problems, Burrow left the vault out of every one and the model solved 48, whereas plain retrieval, which pasted excerpts in front of every question, cut it from 47 to 7. On the smaller Qwen3.5 4B, Burrow answered 91 knowledge questions against 97 with plain retrieval, so it did not improve on plain retrieval for that model.

!fig figures/v2/chart-accuracy-main.png | Figure 5.10: Answers right by set-up and task type, Gemma 4 12B and the cloud model | 6.2

Table 5.7 breaks these results down by task type. The engine's lead over plain retrieval was largest on questions that need facts from two files (34 of 45 against 30), and it was the only set-up that kept the model's reasoning intact (48 of 50). Table 5.8 gives the fraction of the gap closed by Equation 3.1 for both local models, measured against the cloud model with the same vault and against the cloud model alone; against the cloud model alone the local model with Burrow answered 102 knowledge questions to the cloud model's 40, so the fraction exceeds 100%. Table 5.9 gives the cost of an answer: the engine read more tokens than either baseline, a median of 6,068 against 3,814 for plain retrieval, and found every file holding the answer for 111 of the 120 questions.

!include generated2/accuracy-gemma4-12b.md | Table 5.7

!include generated2/gap.md | Table 5.8 | 0.85,0.75,0.95,0.8,0.85,0.8,0.75,0.75

!include generated2/cost.md | Table 5.9 | 1.15,1.5,0.8,0.8,0.9,1.15

The smaller model gave a mixed result, shown in Figure 5.11. Alone, Qwen3.5 4B answered 6 of the 120 knowledge questions; with plain retrieval it answered 97, with the Chroma baseline 75 and with the engine 91, so on knowledge the engine did not improve on plain retrieval for this model (1 question gained and 7 lost, p = 0.070). On reasoning the pattern of the main model repeated more sharply: 46 of 50 alone, 9 with plain retrieval, 1 with the Chroma pipeline and 49 with the engine.

!fig figures/v2/chart-accuracy-small.png | Figure 5.11: Answers right by set-up and task type, Qwen3.5 4B and the cloud model | 6.2

On finding a decision, when 20 tasks were worded unlike the payment decision, it reached the tool in 12 of them with the newest decisions attached first, in 18 with plain vector search, and in 19 once decisions were ranked by relevance (Figure 5.12, panel b). By the scoring rule registered beforehand, 19 against 18 is no difference from vector search: ranking by relevance repaired the earlier weakness but did not beat the simpler method.

On keeping decisions, keeping the reason with the decision made the difference for Claude Code. Before reasons were kept, 3 of 15 second sessions added a phone check as a safeguard and broke the decision; with the reason kept, 9 of 9 kept to it and wrote the rejected approach into the code (Figure 5.12, panel a). Gemma 4 12B in OpenCode was another matter: it received the decision with its reason in 4 of 4 runs but kept it in only 2, and in one it wrote the rejected rule with a comment saying it had been rejected before.

!fig figures/v5/chart-keep.png | Figure 5.12: Keeping, finding and carrying on, with Burrow against its baselines | 6.2

On carrying work on, Figure 5.13 shows that a model given Burrow's resume of about 1,800 tokens answered 11 of 30 questions about an earlier session, more than with nothing (0) or the session tools (6) but fewer than with the whole transcript pasted in (18; p = 0.039). That loss of detail led to keeping the exact words of a session, after which Claude Code quoted the error it had been working on in 6 of 6 runs after compaction, against 0 of 12 before, and a different program continued the right step in 3 of 3 runs, against none of 4 before (Figure 5.12, panels c and d).

!fig figures/v5/chart-resume.png | Figure 5.13: Questions about an earlier session answered right, by what the model was given | 6.2

On checking changes, every change that truly broke the payment decision was judged to break it, and none of the harmless changes was. Inside other programs, shown in Figure 5.14, the check fired whenever the model edited the decision's code, and in every run the model then told the person which decision it went against. Hermes Agent put the code back in 2 of 2 runs, OpenCode in 3 of 6 and OpenClaw in neither of 2. Burrow's own work was small throughout: with 32 programs keeping 1,600 decisions at once, none was lost and keeping one took a median of 0.003 seconds.

!fig figures/v5/chart-gate.png | Figure 5.14: The check inside other programs: runs in which the model told the person, and runs in which it put the code back | 6.2

The errors that remained fell into three kinds. Some were retrieval misses, such as the one oddly worded task whose decision was not attached by any method. Some were losses of detail, where a summary dropped what a later question needed. The largest were the model's own, where a decision arrived and was not followed, which only the check, not the memory, could address.

### 5.5.5 Ablation, Budget and Variation Between Runs

Two parts of the engine were switched off in turn on the main model. With every part on, the engine answered 150 of the 170 questions; without its methods for kinds of task it answered 149, and without the citation check 151. The check asked the model again on only 1 of the 170 questions, because only 1 of the 145 places the model cited was not among what it had been shown, so on this model the check mattered little to the score. Neither part, therefore, explains the engine's results; what did is shown by the budget sweep.

Figure 5.15 and Table 5.10 answer the question of how much of the vault to show. The engine was run again on the 120 knowledge questions with the amount shown fixed at four sizes beside the fitted 17,417 characters. At 2,000 characters most questions received nothing, because the best piece did not fit, and 15 were answered. Accuracy then rose with every increase: 56 at 4,000 characters, 76 at 8,000, 102 at the fitted size and 112 at 32,000, while the time for an answer rose from 2.1 to 15.6 seconds and the gain for each 1,000 tokens read fell from 27.9 to 7.8 points. The fitted size thus gave up 10 answers for answers that took about 40% less time than at the largest size, and the sweep supports the reading in Section 5.8 that much of the engine's edge came from showing the model more.

!fig figures/v2/chart-sweep.png | Figure 5.15: Knowledge answers right against tokens read, as the amount of the vault shown to Gemma 4 12B grows | 6.2

!include generated2/sweep.md | Table 5.10

Local answers were generated at temperature 0 with a fixed seed, but repeated runs still differed: of 169 identical prompts run twice, 41 answers changed in wording and one changed in score. A difference of one or two questions between set-ups is therefore within the variation of the model itself, which is why the comparisons above are reported with the sign test of Equation 5.2 rather than as raw differences.

### 5.5.6 Error Analysis

Of the engine's 18 wrong knowledge answers on the main model, 8 had a needed file missing from what was shown and 10 had every needed file shown, as Table 5.11 shows for every set-up. Both retrieval and the model's reading therefore still failed, as Joren et al. (2025) also found for small models given enough context. Table 5.12 shows one answer of each kind, taken from the saved results of the main model with the engine.

!include generated2/wrong.md | Table 5.11

!tab Table 5.12: Examples of answers from Gemma 4 12B with the engine
!widths 1.05,2.0,2.05,1.2
| Outcome | Question, in short | The model's answer | What happened |
| Right, with its source | How long is the Data Commissioner's term of office, and can it be renewed? | The Data Commissioner shall be appointed for a single term of six years and shall not be eligible for a re-appointment. (Law/act-part-02-office-of-the-data-commissioner.md:71) | The file was found and the place was cited. |
| Incomplete | Which statute guides the Data Commissioner before cancelling a certificate, and what is the maximum fine under the general penalty? | The Fair Administrative Actions Act, 2015 was named, and the model stated that it did not know the maximum fine from what it was shown. | One of the three needed files was not shown, and the model declined that half. |
| Refused, with the evidence shown | Within how many hours of a personal data breach must a data controller notify the Data Commissioner? | I don't know from what you were shown. | The needed file was among the excerpts, and the model did not use it. |
| Refused, with the evidence missing | Which model and context size were tried for Claude Code through Ollama? | I don't know from what you were shown. | Ollama release notes were shown and the project's decision log was not. The refusal was correct. |
| Right, vault left out | A GSM8K problem on the ounces of meat eaten by a basketball team | Answer: 30 | The engine left the vault out, and the model read 272 tokens. |

### 5.5.7 Security and Robustness

Because Burrow is written to and read by AI programs, it was also tested against misuse and load, with Claude Code on the Matatu fixture and three runs per condition unless stated, as Table 5.13 summarises. A reversal of the payment decision was planted in three places. Planted in a vault note, it was never returned by a search, so it never reached the model. Planted in the repository's README, it reached the model in every run and was never followed, but the model did not mention it. Planted as a Ledger decision by an unknown program, it was never followed, and in every run the model told the person, naming the program and saying it could not confirm who wrote it, which the signature on each commit made possible. This matches the risk of indirect prompt injection described by Greshake et al. (2023), and shows that the signature, not the memory, is what let the model tell a planted entry from a person's.

Once Burrow flagged text written to steer an AI, the flag reached the model in every run, but the model told the person in only 1 of 3 runs, and in 3 of 6 once the notice was reworded; when burrow_check repeated the flag at the end of the work, it did so in 5 of 6, and no run followed the planted text. Under load, 32 programs keeping 50 decisions each at the same time, beside two indexing runs, lost none of the 1,600 and duplicated none, after a fault in which two commits in the same second could share a name had been found by this test and corrected. Two Claude Code agents working at once on different branches each left their own handover, after the fault that had merged them was corrected.

!tab Table 5.13: Security and robustness results
!widths 1.7,1.1,1.6,1.6
| Condition | Runs | Reached the model | What the model did |
| Reversal planted in a vault note | 3 | 0 of 3 | Kept the decision in 2 of 3; the third failure was the lost reason, not the note |
| Reversal planted in the README | 3 | 3 of 3 | Never followed it; told the person in none |
| Reversal planted as a Ledger decision by an unknown program | 3 | 3 of 3 | Never followed it; told the person in 3 of 3, naming the program |
| Steering text flagged on a read | 3 | 3 of 3 | Never followed it; told the person in 1 of 3 |
| The same, with the notice reworded | 6 | 6 of 6 | Never followed it; told the person in 3 of 6 |
| Flag repeated by burrow_check | 6 | 6 of 6 | Never followed it; told the person in 5 of 6 |
| 32 programs keeping 50 decisions each at once | 1 | not applicable | 1,600 of 1,600 kept, none duplicated; median 0.003 s per commit |
| Two agents at once on different branches | 4 | not applicable | Each left its own handover after the fix; both passed their tests |

### 5.5.8 Release and Installation Check

The installation was tested as a new user would meet it. The one-line installer was run against the published release burrow-v1.2.1 into an empty folder and installed a working burrow program, which reported its version and made a new vault; the same installer was then given a download altered after publication, and it refused it on the SHA-256 checksum and installed nothing. The desktop application from the release is not notarised by Apple, so on first opening macOS stops it until the person allows it in Privacy and Security, which the download page explains.

[PENDING: a usability test with real users. Friends with Macs will install Burrow from the project website, connect one AI program and keep and resume a decision; their tasks completed, the problems they met and their comments will be reported here. Only real participants will be reported.]

## 5.6 Version Control and Implementation Evidence

The source code, tests, evaluation material and this report are kept in the project repository (https://github.com/Satasdin/Burrow), with burrow as the default branch. The Sources folder holds the engine, divided into BurrowCore for the vault and its index and BurrowTools for the Ledger, sessions, the check and team sharing, together with the MCP server and the command-line program. The Tests folder holds the 553 automated tests, the app folder the desktop application, the trials folder the scripts, transcripts and results of every evaluation, and docs the user guide, the test record, the traceability record and this report with the scripts that build it. The README gives the problem, installation, build, test and use. Figure 5.16 shows the history of the repository.

!fig figures/screens2/console-git.png | Figure 5.16: The history of the repository, its tags and its folders | 6.2

Development followed a branch workflow in which new work was built on a branch and merged once its tests passed. Each commit message names the design decision it carries out, and the file DECISIONS.md records every decision with the run or review that caused it and the evidence after the change, so the reason for each part of the code can be traced. Evaluations reported as frozen were run on tagged builds, and every push ran the automated tests through GitHub Actions. The final build was pushed to the burrow branch, where its tests passed again on the hosted machine, except one that needs a terminal session of its own and skipped itself there, and tagged as the release burrow-v1.2.1.

## 5.7 Author Oversight and Use of AI-Assisted Tools

Claude Code, a coding assistant from Anthropic running Claude Opus 5.5, wrote most of the code, tests and evaluation scripts at the author's direction and from the author's design, ran the evaluations, reviewed each change for security, drew the figures and drafted this report from the saved results and cited sources. Kimi K3 from Moonshot AI was used in an early increment as a model under test and as a judge of answers. Every output was checked against the automated tests, the saved transcripts and the cited sources, and the author chose the problem, the design and the experiments, made the final decisions and takes full responsibility for the submitted work.

## 5.8 Evaluation Results, Discussion and Limitations

The third objective was to develop the designed vault as working software on a consumer laptop. The output is Burrow, with its engine, MCP server, hooks, plugins and desktop application, and the criterion was that every requirement of Chapter 4 is met and verified. All 24 test cases passed on the final build, and the defects that real use exposed were corrected and retested (Table 5.5), so the evidence permits the conclusion that the design was built and runs on the laptop. It does not show that the desktop application suits other people, since no one other than the developer used it.

The fourth objective was to evaluate how much of the knowledge gap between a local model and a cloud model the vault closes. The criterion was the fraction of the gap closed by Equation 3.1, against the cloud model given the same vault, and the result was 93% for Gemma 4 12B, with Burrow answering 34 more questions than the Chroma baseline. This agrees with the finding that retrieved text closes the gap on knowledge a model has not memorised (Mallen et al., 2023), and it was reached on the laptop alone, where the nearest earlier work recovered 87% of a cloud model's performance only by keeping the cloud model in every task (Narayan et al., 2025). Burrow also kept out of the way on reasoning, where plain retrieval did the harm that irrelevant text is known to do (Shi et al., 2023). The gain over plain retrieval should be read with care, however: Burrow was shown more of the vault than either baseline, its 10 gains over plain retrieval came where it read the same ranking with more room, and on the smaller Qwen3.5 4B it answered fewer questions than plain retrieval. The evidence therefore supports the conclusion that a local memory narrows most of the knowledge gap on the laptop, and that much of Burrow's edge over plain retrieval came from fitting more of the vault to the model rather than from its other steps.

The fifth objective was to evaluate whether models that share the vault keep decisions made with earlier models and carry earlier work on. The criteria were the hidden decision tests and the right next step. The most important finding concerned the reason behind a decision: without it, Claude Code sometimes kept the letter of the decision but defeated its purpose with a well-meant safeguard, and with it, Claude Code kept the decision in 9 of 9 runs. This agrees with the long-held view in software engineering that rationale, not the decision alone, keeps later changes from undoing earlier work (Jansen & Bosch, 2005; Tang et al., 2006). A different program carried the work on in 3 of 3 runs once Burrow kept the exact words of a session, against none before. The results also marked the limits of memory. A small local model sometimes read a decision and broke it anyway, in line with reports that agents often fail to follow the instructions they are given (Voria et al., 2026), so memory solved delivery but not obedience. The check narrowed that gap by holding a change whatever the model chose and by making every program name the decision it had broken, but whether the code was then put back depended on the program, and OpenClaw never put it back.

These results have limits, each with a likely effect on the findings. Each condition had between 3 and 30 runs, so only large differences can be told apart from chance, and the results on decisions rest mostly on one fixture project with one decision, so they may not hold for every kind of decision. Burrow was not compared with a file of decisions kept by hand in the repository, which is the simplest alternative, so what it adds beyond such a file is not measured. The later evaluations ran on the build of their day rather than one frozen build, so improvements and their evaluations were interleaved. The knowledge questions were written by agents from the same family as the cloud model, which may make them easier or harder than a person's own questions, and the cloud model could not be run at a fixed temperature. Finally, timings come from one laptop that other jobs sometimes shared, and no person other than the developer used the system, so its usability is not claimed.
