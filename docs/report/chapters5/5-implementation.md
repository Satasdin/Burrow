# Chapter 5:  System Implementation, Testing and Evaluation

## 5.1 Introduction

This chapter presents how Burrow was implemented, tested and evaluated, and addresses the third, fourth and fifth specific objectives. It describes the implementation environment, the data used in the evaluation, and each module of the system, and then reports how well AI tools found material, kept earlier decisions, carried work on and had their changes checked when Burrow was in use. It closes with the results of the system tests, a discussion of the findings, and the project's GitHub documentation.

## 5.2 Implementation Environment

### 5.2.1 Hardware Specifications

Burrow was developed and evaluated on one consumer laptop, with the local models running in Ollama on the same machine. Table 5.1 lists the hardware and why it suited the project.

!tab Table 5.1: Hardware specifications
!widths 1.2,2.2,2.9
| Component | Specification | Justification |
| Computer | Apple MacBook Pro, M5 Pro chip, 24 GB of shared memory | Runs Burrow, the AI tools and the local models together, as a person would on their own computer |
| Storage | Internal SSD | The vault, the Ledger and the index are files on the person's own disk |
| Graphics | The chip's built-in graphics processor | Used by Ollama to run the local models |
| Network | Home internet connection | Needed only to download models and by cloud AI tools to reach their provider; Burrow itself works offline |

### 5.2.2 Software Specifications

Table 5.2 lists the software, AI tools and models used, with the versions that were tested.

!tab Table 5.2: Software specifications
!widths 1.7,1.8,2.8
| Software | Version | Role |
| macOS | 27.2 | Operating system; the program needs macOS 14 or later and the app macOS 26 |
| Swift | 6.4.2 | Language of the engine, the command line, the app and the tests |
| SQLite with FTS5 | 3.54.0 | The index of the vault: word search, vectors and links |
| Ollama | 0.40.16 | Runs the local chat and embedding models |
| Gemma 4 12B, Qwen3 4B | gemma4:12b, qwen3:4b-instruct | Local models used by the AI tools in the evaluation |
| Qwen3 Embedding 0.6B | qwen3-embedding:0.6b | Turns text into vectors for search by meaning |
| Claude Code | 2.1.322, with Claude Opus 5.5 | Cloud coding tool connected through MCP and hooks |
| OpenCode, OpenClaw, Hermes Agent | 1.19.5, 2026.11.3, 0.23.1 | Other AI programs connected through MCP and plugins |
| n8n | 2.47.7 | Workflow platform whose support agent used Burrow |
| Chroma | 1.5.9 | Vector database used as a baseline |

Burrow is installed with one command from the project's releases or built from source with swift build, and an AI tool is connected with the command burrow connect followed by the program's name. The local evaluations needed no paid service, while the runs with Claude Code used a Claude subscription. [PENDING: tag and publish the evaluated build as a release, and give its name here.]

## 5.3 Description of the Dataset

The evaluation used two kinds of data. The first was a vault of real documents assembled for the study: Kenya's Data Protection Act and its regulations, documentation of software released in 2026, and the notes of a private software project, 87 files in all. From these documents, 120 knowledge questions were written with an answer key for each, and 50 reasoning problems were taken from the public GSM8K benchmark (Cobbe et al., 2021) to check that memory would be left out where it was not needed.

The second was Matatu, a fixture project written for the study to test decisions. Matatu is a Python service of about 1,500 lines that records matatu fares paid by M-Pesa and matches each payment on a statement to its ticket. It came with written tasks, hidden tests that the AI tools could not read, and one business decision with a reason: payments are matched to tickets by account reference only, because conductors often pay for a whole group from one phone, and on one Easter Monday an older rule that matched by phone and amount had marked 31 tickets paid against the wrong passengers. A later task asks for unmatched payments to be handled, which tempts a tool to bring the rejected rule back. Table 5.3 summarises the data.

!tab Table 5.3: Data used in the evaluation
!widths 1.2,2.6,1.1,1.4
| Data | What it holds | Size | Used for |
| Knowledge vault | Kenyan data protection law, 2026 software documentation and a private project's notes | 87 files; 120 questions | Finding the right material |
| Reasoning problems | Problems from the GSM8K test split | 50 problems | Checking that memory is left out when not needed |
| Matatu fixture | A fare-payment service with a recorded decision, tasks and hidden tests | About 1,500 lines; 4 tasks | Keeping decisions, carrying work on and checking changes |

Every evaluation started from a fixed base built by a script, in which a first session by Claude Code had kept the payment decision in the Ledger. The first session's task brief was then removed, so that later sessions could learn of the decision only through Burrow, and the questions, answer keys and hidden tests were kept outside the vault. The full transcript of every run was read to confirm that no tool found the answer elsewhere.

## 5.4 System Implementation

### 5.4.1 Vault and Index Module

This module turned an ordinary folder of Markdown notes and documents into a vault that AI tools could search, with code folders linked in read-only. It split each file at its headings or code boundaries, indexed the pieces by word and by meaning, and kept the links between files, so that a search returned excerpts with their file and line. A linked folder named in a vault was read only after the person allowed it on their own computer, which stopped a vault received from someone else from opening the person's other folders. Figure 5.1 shows a vault in the desktop application, and Figure 5.2 shows the request that appears before a linked folder is read.

!fig figures/screens4/app-graph.png | Figure 5.1: The map of a vault in the desktop application, coloured by folder | 6.2

!fig figures/v5/approve-folder.png | Figure 5.2: The application asking the person before it reads a folder that a vault links | 4.8

### 5.4.2 Ledger Module

The Ledger module kept what AI sessions decided, one Markdown file per commit, on branches like git. A decision was refused without a reason, and it was stored with the options rejected, the files it rests on with a hash of each, and the name of the program that kept it. No commit was ever changed or deleted; a later commit retired it, either as a replacement or as a correction, and when a file that a decision rests on changed, the decision was marked to be checked again until the person confirmed it. Figure 5.3 shows the Ledger page with decisions kept during a team run by two simulated teammates and by Claude Code.

!fig figures/v5/app-ledger-team.png | Figure 5.3: The Ledger page, with each decision's reason, the person or program that kept it, and its branch | 6.2

### 5.4.3 Connection Module

This module let any AI program reach Burrow through its MCP server, which offered five tools: burrow_resume, burrow_find, burrow_read, burrow_commit and burrow_check. One command set Burrow up in Claude Code, OpenCode, OpenClaw, Hermes Agent or n8n while keeping every other setting in that program's files. Because two of these programs were found never to pass a server's connection instructions to their model, the decisions in force were also sent with each program's first tool result. Figure 5.4 shows an n8n support workflow whose agent, running on a local model, uses Burrow as a tool, and Figure 5.5 shows that agent receiving decisions that Claude Code had kept earlier.

!fig figures/v5/n8n-canvas.png | Figure 5.4: An n8n support workflow whose agent, on a local model through Ollama, uses Burrow as an MCP tool | 6.2

!fig figures/v5/n8n-resume.png | Figure 5.5: The n8n agent's burrow_resume call returning decisions kept earlier by Claude Code | 6.2

### 5.4.4 Check Module

The check module compared the linked code with its last git commit and judged each decision the change touched. A change broke a decision when the check the person had set for it failed, affected it when it changed the parts of the code the decision rests on, and left it unaffected otherwise. The same check ran when a model called burrow_check, when Claude Code tried to end its turn, when a git commit was made, and inside OpenCode, OpenClaw and Hermes Agent through plugins, so a model could not skip it. A change that broke a decision was held until it was undone or the person overrode the decision. Figure 5.6 shows the pre-commit hook passing a harmless change and refusing one that broke the payment decision.

!fig figures/v5/console-gate.png | Figure 5.6: The git pre-commit hook passing a harmless change and refusing one that breaks a decision (real output, shortened) | 6.2

### 5.4.5 Sessions and Handover Module

This module kept each connection as a conversation with a trail of what it looked up and kept, so that the next program could resume where the last one stopped. For Claude Code, it also kept the exact words of each part of a session when the session was compacted, including the person's requests and the last error as printed, and handed them back afterwards. A different program that resumed was told what the last session had been in the middle of, and keys, tokens and passwords were removed from everything kept.

### 5.4.6 Team and Approval Module

The team module let a small team share decisions through a folder they all had, either a git repository or a synced folder, with each decision signed by the person and the program that kept it. Anything an AI tool wanted to share waited until the person had read and approved it; in the first real run this caught a decision in which the model had written "Finance and product agreed" where the person had said "Finance and I". Approving a share or a linked folder, and overriding a broken decision, were refused when requested from inside an AI program, and an override also needed a one-time code shown in a macOS notification.

## 5.5 Evaluation

### 5.5.1 Evaluation Set-ups and Baselines

No model was trained. Each evaluation gave the same AI tool the same task with Burrow and with a baseline in its place, as Table 5.4 lists. Where an improvement to Burrow was measured, the baseline was Burrow before the improvement, run from the same starting point.

!tab Table 5.4: Evaluation set-ups and baselines
!widths 1.3,2.0,1.6,1.6
| Evaluation | Task | Burrow set-up | Baselines |
| Finding material | 120 knowledge questions on the vault | Gemma 4 12B with Burrow | Model alone; plain retrieval; Chroma vector database; cloud model alone and with Burrow |
| Finding a decision | 20 oddly worded Matatu tasks, 40 unrelated decisions | Decisions ranked by relevance | Newest decisions first; plain vector search |
| Keeping a decision | Second Matatu session, scored by hidden tests | Claude Code and Gemma 4 12B with Burrow | Burrow before reasons were kept |
| Carrying work on | A new session asked about, or told to continue, the last one | Burrow's resume, folds and handover | Nothing; the session tools; the pasted transcript; the old handoff |
| Checking changes | Changes that keep or break the decision | Verdicts, hooks and plugins | The same programs without the check |

### 5.5.2 Evaluation Metrics

Each result was counted as the number of runs or questions that met the scoring rule out of those attempted, as Equation 5.1 shows. A knowledge answer was right when it contained every part of its answer key, a decision was kept when both hidden decision tests passed, and work was carried on when the next session continued the right step with its constraint. Where two set-ups were run on the same items, they were compared with the exact sign test in Equation 5.2, where b and c are the items that only one of the two got right.

!eq accuracy | Equation 5.1: Share of runs or questions that met the scoring rule

!eq sign | Equation 5.2: Exact two-sided sign test on paired results

### 5.5.3 Evaluation Results

On finding material, Figure 5.7 shows that Gemma 4 12B answered 9 of the 120 knowledge questions alone and 102 with Burrow, against 94 with plain retrieval and 75 with a Chroma vector database, while the cloud model answered 40 alone and 109 when given the same vault. By Equation 3.1, Burrow therefore closed 93% of the knowledge gap between the local model and the cloud model given the same memory, at a cost of 9.2 seconds per answer against 8.3 for plain retrieval. On the 50 reasoning problems, Burrow left the vault out of every one and the model solved 48, whereas plain retrieval, which pasted excerpts in front of every question, cut it from 47 to 7. Decisions were harder to find than facts: when 20 tasks were worded unlike the payment decision, it reached the tool in 12 of them with the newest decisions attached first, in 18 with plain vector search, and in 19 once decisions were ranked by relevance (Figure 5.8, panel b).

!fig figures/v2/chart-accuracy-main.png | Figure 5.7: Answers right by set-up and task type, Gemma 4 12B and the cloud model | 6.2

On keeping decisions, keeping the reason with the decision made the difference for Claude Code. Before reasons were kept, 3 of 15 second sessions added a phone check as a safeguard and broke the decision; with the reason kept, 9 of 9 kept to it and wrote the rejected approach into the code (Figure 5.8, panel a). Gemma 4 12B in OpenCode was another matter: it received the decision with its reason in 4 of 4 runs but kept it in only 2, and in one it wrote the rejected rule with a comment saying it had been rejected before.

!fig figures/v5/chart-keep.png | Figure 5.8: Keeping, finding and carrying on, with Burrow against its baselines | 6.2

On carrying work on, Figure 5.9 shows that a model given Burrow's resume of about 1,800 tokens answered 11 of 30 questions about an earlier session, more than with nothing (0) or the session tools (6) but fewer than with the whole transcript pasted in (18; p = 0.039). That loss of detail led to keeping the exact words of a session, after which Claude Code quoted the error it had been working on in 6 of 6 runs after compaction, against 0 of 12 before, and a different program continued the right step in 3 of 3 runs, against none before (Figure 5.8, panels c and d).

!fig figures/v5/chart-resume.png | Figure 5.9: Questions about an earlier session answered right, by what the model was given | 6.2

On checking changes, every change that truly broke the payment decision was judged to break it, and none of the harmless changes was. Inside other programs, shown in Figure 5.10, the check fired whenever the model edited the decision's code, and in every run the model then told the person which decision it went against. Hermes Agent put the code back in 2 of 2 runs, OpenCode in 3 of 6 and OpenClaw in neither of 2. Burrow's own work was small throughout: with 32 programs keeping 1,600 decisions at once, none was lost and keeping one took a median of 0.003 seconds.

!fig figures/v5/chart-gate.png | Figure 5.10: The check inside other programs: runs in which the model told the person, and runs in which it put the code back | 6.2

The errors that remained fell into three kinds. Some were retrieval misses, such as the one oddly worded task whose decision was not attached by any method. Some were losses of detail, where a summary dropped what a later question needed. The largest were the model's own, where a decision arrived and was not followed, which only the check, not the memory, could address.

## 5.6 System Testing

Testing was carried out at the unit, integration and system levels, and covered normal use, wrong input, boundary cases and hostile input. All 553 automated tests passed on the final build, and every push to the repository ran them again on a hosted Apple silicon machine. Table 5.5 shows the main system test cases, written from the point of view of a person and the AI tools they use; the full record of 24 cases, each traced to its requirement, is in the repository (https://github.com/Satasdin/CAMR/blob/burrow/docs/evaluation/test-cases.md).

!tab Table 5.5: System test cases and results
!widths 0.55,1.0,1.55,1.15,1.35,0.95,0.55
| Test Case ID | Module | Description | Test Data | Expected Result | Actual Result | Pass/Fail |
| TC-01 | Vault and Index | Open a folder as a vault and search it | A folder of notes and a linked code folder | Files indexed; linked folder read only after the person allows it | As expected | Pass |
| TC-03 | Ledger | Keep a decision without a reason, then with one | A decision with and without a reason | First refused; second kept with reason, files and author | As expected | Pass |
| TC-04 | Connection | Connect a program and call its first tool | Claude Code and OpenClaw | Decisions in force handed over once | As expected | Pass |
| TC-06 | Sessions and Handover | Resume in a different program after a Claude Code session | A session stopped mid-task | The right step, its constraint and the last error given | As expected | Pass |
| TC-07 | Ledger | Edit a file a decision rests on, then confirm the decision | The matching code edited | Decision marked to check again; cleared by Still Right | As expected | Pass |
| TC-08 | Ledger | Keep a decision that contradicts one in force | A reversal of the payment rule | Asked which holds; the old one retired | As expected | Pass |
| TC-09 | Check | Commit a change that breaks a decision | The phone-and-amount fallback | Commit refused, decision shown | As expected | Pass |
| TC-10 | Sessions and Handover | Ask for the error line after a session is compacted | A long Claude Code session | The exact error line quoted | As expected | Pass |
| TC-11 | Team and Approval | An AI tool shares a decision with the team | A shared decision | Held until the person approves | As expected | Pass |
| TC-16 | Team and Approval | An AI tool asks to override a decision | An override run from Claude Code | Refused, with the reason shown | As expected | Pass |
| TC-23 | Vault and Index | Stop the local model service during a search | Ollama stopped | Search continues on words alone | As expected | Pass |

## 5.7 Results and Discussion

The results showed that Burrow met its aim of keeping decisions for the AI tools that a person uses. On private material, a local model with Burrow answered far more questions than it could alone or with a vector database, which indicates that a memory of the person's own files, prepared well, can make a small model useful where it would otherwise fail. Burrow also left its memory out of reasoning problems, avoiding the harm that plain retrieval did there.

The most important finding concerned the reason behind a decision. When Claude Code received a decision without its reason, it sometimes kept the letter of the decision but defeated its purpose with a well-meant safeguard; when the reason came with the decision, it kept to it in every run. This agrees with the long-held view in software engineering that rationale, not the decision alone, is what keeps later changes from undoing earlier work (Jansen & Bosch, 2005; Tang et al., 2006).

The results also marked the limits of memory. A small local model sometimes read a decision and broke it anyway, in line with reports that agents often fail to follow the instructions they are given (Voria et al., 2026). Memory therefore solved delivery but not obedience. The check narrowed that gap by holding a change whatever the model chose, and made every program name the decision it had broken, though whether the code was then put back depended on the program: Hermes Agent and Claude Code did so, while OpenClaw did not. Burrow's resume also lost detail against a pasted transcript, which led to keeping the exact words of a session and to a handover that brought the right next step to another program.

These results have limits. Each condition had between 3 and 30 runs, most evaluations used one fixture project and one decision, Burrow was not compared with a decisions file kept by hand in the repository, the later evaluations ran on the build of their day rather than one frozen build, and no person other than the developer used the system. Overall, the findings confirmed that the study achieved its objectives: Burrow was built as designed and verified by its tests, and with it AI tools found the right material, kept earlier decisions once their reasons were kept, carried earlier work on, and had changes that broke a decision held before the work was reported as done.

## 5.8 GitHub Documentation

The complete source code, tests, evaluation material and this report are kept on GitHub at https://github.com/Satasdin/CAMR, with burrow as the default branch. The Sources folder holds the engine, divided into BurrowCore for the vault and its index and BurrowTools for the Ledger, sessions, the check and team sharing, together with the MCP server and the command-line program. The Tests folder holds the 553 automated tests, the app folder the desktop application, the trials folder the scripts, transcripts and results of every evaluation, and docs the user guide, the test record and this report with the scripts that build it. Figure 5.11 shows the history of the repository.

!fig figures/screens2/console-git.png | Figure 5.11: The history of the repository, its tags and its folders | 6.2

Development followed a branch workflow in which new work was built on a branch and merged once its tests passed. Each commit message names the design decision it carries out, and the file DECISIONS.md records every decision with the run or review that caused it and the evidence after the change, so the reason for each part of the code can be traced. Evaluations reported as frozen were run on tagged builds, and every push ran the automated tests through GitHub Actions. [PENDING: push the final build and tag its release.]

## 5.9 Author Oversight and Use of AI-Assisted Tools

Claude Code, a coding assistant from Anthropic running Claude Opus 5.5, wrote most of the code, tests and evaluation scripts at the author's direction and from the author's design, ran the evaluations, reviewed each change for security, drew the figures and drafted this report from the saved results and cited sources. Kimi K3 from Moonshot AI was used in an early increment as a model under test and as a judge of answers. Every output was checked against the automated tests, the saved transcripts and the cited sources, and the author chose the problem, the design and the experiments, made the final decisions and takes full responsibility for the submitted work.
