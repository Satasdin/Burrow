# Chapter 5:  System Implementation, Testing and Evaluation

## 5.1 Introduction

This chapter presents how the design of Chapter 4 was built, tested and evaluated, and addresses the fourth and fifth specific objectives. Section 5.2 states the implementation environment and Section 5.3 the data. Section 5.4 presents each part of Burrow in the order of the architecture, with the real runs that shaped it. Section 5.5 reports the evaluation: whether AI tools found the right material, kept earlier decisions, carried earlier work on, and had changes judged correctly, and at what cost. Section 5.6 reports the system tests, and Sections 5.7 and 5.8 give the version control evidence and the declaration of AI-assisted tools. Section 5.9 discusses the results against each objective and states their limitations. The full test record, further results and a user guide are in the repository.

## 5.2 Implementation Environment

Burrow runs on the person's own Mac. It was developed and tested on one such computer, with the local models in Ollama on the same machine; cloud models were reached only by the AI tools that use them.

### 5.2.1 Hardware and Deployment Environment

Table 5.1 states the computer on which Burrow was built and evaluated. Other computers were not tested, so no claim is made for them.

!tab Table 5.1: Hardware and deployment environment
!widths 1.0,2.0,2.2,1.1
| Item | Tested specification | Purpose and justification | Evidence |
| Computer | Apple MacBook Pro, M5 Pro chip, 24 GB of shared memory | Runs Burrow, its index, the AI tools and the local models together, as a person would | System report |
| Storage | Internal SSD | The vault, the Ledger and the index are files on the person's disk | NFR-01 |
| Graphics | The chip's own graphics processor | Used by Ollama to run local models | Ollama (2026) |
| Network | Needed to download models and releases, and by cloud AI tools to reach their own provider | Burrow itself works offline | NFR-01 |

### 5.2.2 Software, Services and Configuration

Table 5.2 lists the software, the AI tools and the models with the versions that were tested.

!tab Table 5.2: Software, AI tools and models
!widths 1.7,1.8,2.8
| Software | Tested version | Role and reason |
| macOS | 27.2 | Operating system; the program needs macOS 14 or later and the app macOS 26 |
| Swift | 6.4.2 | The engine, the command line, the app and the tests |
| SQLite with FTS5 | 3.54.0 | The index: word search, vectors and links |
| Ollama | 0.40.16 | Runs the local chat and embedding models |
| Gemma 4 12B, Qwen3 4B | gemma4:12b, qwen3:4b-instruct | Local models used by OpenCode, OpenClaw, Hermes, n8n and the evaluations |
| Qwen3 Embedding 0.6B | qwen3-embedding:0.6b | Turns text into vectors for search by meaning |
| Claude Code | 2.1.321 to 2.1.322, with Claude Opus 5.5 and Haiku 5.5 | Cloud coding tool connected through MCP and hooks |
| OpenCode, OpenClaw, Hermes Agent | 1.19.5, 2026.11.3, 0.23.1 | Other AI programs connected through MCP and plugins |
| n8n | 2.47.7 | Workflow platform; a support agent used Burrow through an MCP bridge |
| Chroma | 1.5.9 | Vector database baseline of the knowledge evaluation |

No secret appears in the repository. The cloud tools used their own accounts, and Burrow holds no key.

### 5.2.3 Deployment and Reproducibility

Burrow is installed with one command from the project's releases, which places the burrow program and, if asked, the desktop application; it can also be built from source with swift build -c release and app/build.sh. A vault is set up with burrow index, and an AI tool is connected with burrow connect followed by the program's name, which writes Burrow into that program's own settings while keeping every other setting. A first burrow find on the vault verifies the installation. Each evaluation in Section 5.5 has a script and a README in the trials folder of the repository, and its raw transcripts are kept beside it. The local evaluations need no paid service; the runs with Claude Code need a Claude subscription. [PENDING: tag and publish the evaluated build as a release, and give its name here.]

## 5.3 Dataset Description

### 5.3.1 Description of the Dataset

Two sets of data were used, as Section 3.2.1 described. Table 5.3 summarises them.

!tab Table 5.3: Data used in the evaluation
!widths 1.2,2.6,1.1,1.4
| Data | What it holds | Size | Used for |
| Knowledge vault | Kenya's Data Protection Act and its regulations, documentation of software released in 2026, and a private project's notes | 87 files; 120 questions with answer keys | Finding material (Section 5.5.3) |
| Reasoning problems | Problems from the GSM8K test split (Cobbe et al., 2021) | 50 problems | Checking that memory is left out when not needed |
| Matatu fixture | A Python fare-payment service with a recorded decision, written tasks and hidden tests | About 1,500 lines; 4 tasks; 2 hidden decision tests | Keeping, carrying on and checking (Sections 5.5.4 to 5.5.6) |

The decision at the heart of the Matatu fixture is real in form though invented in detail: payments are matched to tickets by account reference only, because conductors pay for a whole group from one phone, and on one Easter Monday a fallback that matched by phone and amount marked 31 tickets paid against the wrong passengers. The later task asks for unmatched payments to be handled, which tempts a tool to bring the rejected fallback back.

### 5.3.2 Data Preparation and Partitioning

Each evaluation started from a fixed base built by a script: the vault, the Matatu code linked into it, and a first session by Claude Code that kept the decision in the Ledger. The task brief of that first session was removed before later sessions, so the decision could reach them only through Burrow. Questions, answer keys and hidden tests were kept outside the vault, and every transcript was read to confirm that no tool found the answer elsewhere; one run that read the brief directly was set aside and is reported as such in the repository. Burrow's settings, such as how decisions are ranked for a request, were tuned on cases written for that purpose and not on the scored tasks.

## 5.4 System Implementation

This section presents the parts of Burrow in the order of the architecture in Figure 4.5. Each part names the requirement it meets, and the screens shown are real captures of the system.

### 5.4.1 The Vault and Its Index

The vault is an ordinary folder of Markdown notes and documents, with code folders linked in read-only (FR-01, DR-01). Burrow cuts each file at its headings or code boundaries, indexes the pieces by word and by meaning, and keeps the links between files, so a search returns excerpts with their file and line (FR-02). Figure 5.1 shows a vault in the desktop application.

!fig figures/screens4/app-graph.png | Figure 5.1: The map of a vault in the desktop application, coloured by folder | 6.2

A linked folder named in a vault is read only once the person allows it on this Mac (NFR-05). The guard was added after a review showed that a vault received from someone else could name any folder on the computer. Figure 5.2 shows the request that appears when a vault with an unapproved folder is opened.

!fig figures/v5/approve-folder.png | Figure 5.2: The application asking the person before it reads a folder that a vault links | 4.8

### 5.4.2 The Ledger

The Ledger keeps what AI sessions decided, one Markdown file per commit, on branches like git (FR-03, DR-02). A decision is refused without a reason, and it is kept with the options rejected and the files it rests on, each with a hash of its content; it is signed with the program that connected, while the name a model gives for itself is kept only as its claim. No commit is ever changed: a later commit retires it, as a replacement or a correction (FR-07, FR-08). The first stress run showed that two programs keeping decisions in the same second could overwrite each other, so a commit is now written whole and given its name by an operation that refuses a name already taken (NFR-02). Figure 5.3 shows the Ledger page from a team run, with decisions kept by two simulated teammates and by Claude Code.

!fig figures/v5/app-ledger-team.png | Figure 5.3: The Ledger page, with each decision's reason, the person or program that kept it, and its branch | 6.2

### 5.4.3 Connecting AI Tools

Every AI program reaches Burrow through its MCP server, burrow mcp, which offers five tools by default: burrow_resume, burrow_find, burrow_read, burrow_commit and burrow_check (IR-01). One command, burrow connect, sets Burrow up in Claude Code, OpenCode, OpenClaw, Hermes Agent or n8n (IR-02). Runs showed that two programs hid Burrow's tools behind their own tool search by default, so the command also keeps the tools in view; with it, the tools were shown to the model by name in 12 of 12 runs. Figure 5.4 shows an n8n workflow in which a support agent on a local model uses Burrow as a tool.

!fig figures/v5/n8n-canvas.png | Figure 5.4: An n8n support workflow whose agent, on a local model through Ollama, uses Burrow as an MCP tool | 6.2

### 5.4.4 Handing Decisions Over

Decisions reach a program three ways (FR-04 to FR-06). The decisions in force are handed over when it connects, and again with its first tool result, because OpenClaw and Hermes Agent were found to pass none of Burrow's connection instructions to their model: 0 of 458 requests they sent to Ollama held them. burrow_resume gives the plan, where the last session stopped and the latest decisions. A search or read carries the decisions that fit the request, ranked by meaning and by the files returned. Figure 5.5 shows the n8n agent calling burrow_resume and receiving the decisions that Claude Code had kept earlier in another program.

!fig figures/v5/n8n-resume.png | Figure 5.5: The n8n agent's burrow_resume call returning decisions kept earlier by Claude Code | 6.2

### 5.4.5 The Check of New Work

burrow_check compares the linked code with its last git commit and judges each decision the change touches (FR-09). A decision rests on parts of the code, such as a function, and may carry a check that the person confirmed: a test to run, or a pattern that no added line may match. The verdict is breaks when that check fails, affected when the change touches the parts the decision rests on, unaffected when it does not, and unprovable when Burrow cannot tell. A model need not call the tool for the check to run: Claude Code's end-of-turn hook, a git pre-commit hook and plugins for OpenCode, OpenClaw and Hermes Agent run the same check and hold a change that touches a decision until it has been shown, and a change that breaks a decision until it is undone or the person overrides it. Figure 5.6 shows the pre-commit hook letting a harmless change through and refusing the phone-and-amount fallback that Gemma 4 12B had written.

!fig figures/v5/console-gate.png | Figure 5.6: The git pre-commit hook passing a harmless change and refusing one that breaks a decision (real output, shortened) | 6.2

### 5.4.6 Sessions, Folds and Handover

Each connection is kept as a conversation with a trail of what it looked up and kept, and the application shows it (FR-12). For Claude Code, Burrow also folds each stretch of a session when it is compacted or ends, keeping the person's requests, reasons, error lines and files word for word, and hands the folds back after compaction (FR-10). The idea follows the billion-context project, which compresses only what is new and never summarises a summary again. A different program that resumes is told what the last session was in the middle of: the step, the constraint and the last error exactly as printed. Folds keep no secrets: keys, tokens and passwords are removed before anything is written (NFR-04).

### 5.4.7 Teams and the Person's Control

A small team shares decisions through a folder they all have, either a git repository or a synced folder (FR-11). Each person keeps their own vault and joins the team folder from it; a decision shared by one reaches the others' programs, signed with the person and the program. Anything an AI wants to share waits until the person reads and approves it. In the first real run this caught a decision in which Claude had written "Finance and product agreed" where the person had said "Finance and I". Approving a share or a linked folder, and overriding a broken decision, are refused when asked from inside an AI program, and an override also needs a one-time code shown only in a macOS notification (NFR-05).

### 5.4.8 Design Decisions Made During the Build

The build recorded 44 design decisions between 12 and 15 November 2026 alone (D-70 to D-113 in the repository's DECISIONS.md), each with the run or review that caused it and the evidence after the change. Most came from real runs: reasons that were cut off when a decision was handed over, decisions that never reached a model, sessions of two programs merged into one, and a check that only listed decisions until it learned to judge them. Twelve came from independent security reviews of each change, among them the guards on linked folders, team shares and overrides described above. Section 5.6 reports the defects found this way.

## 5.5 Evaluation

### 5.5.1 Set-ups and Baselines

No model was trained. Each evaluation compared an AI tool given Burrow with the same tool given a baseline, under the same task, as Table 5.4 lists. Where a change to Burrow was measured, the baseline was Burrow before the change, run from the same base.

!tab Table 5.4: Evaluations, their set-ups and baselines
!widths 1.3,2.0,1.6,1.6
| Evaluation | Task | Burrow set-up | Baselines |
| Finding material | 120 knowledge questions on the vault | Gemma 4 12B with Burrow's engine | Model alone; plain retrieval; Chroma vector database; cloud model alone and with Burrow |
| Decision found despite wording | 20 oddly worded Matatu tasks, 40 unrelated decisions in the Ledger | Decisions ranked by relevance | Newest decisions first; plain vector search, top 8 |
| Keeping the decision | Session 2 of Matatu, scored by hidden decision tests | Claude Code and Gemma 4 12B with Burrow | Burrow before reasons were kept |
| Carrying work on | A resumed session asked what the earlier one did, or told to carry on | Burrow's resume, folds and handover | Nothing; the session tools; the whole transcript pasted; the old handoff |
| Checking changes | Changes that keep or break the decision | Verdicts; hooks and plugins | The same programs without the check |

### 5.5.2 Evaluation Metrics

Each result is the number of runs or questions that met the scoring rule, out of those run, as Equation 5.1 states. A knowledge answer was right when it contained every required part of its key. A decision was kept when both hidden decision tests passed. Carrying on was right when the next session continued the right step with its constraint. Where two set-ups were run on the same items, they were compared with the exact two-sided sign test of Equation 5.2, where b and c are the items that only one of the two got right. Time was measured in seconds on the tested computer.

!eq accuracy | Equation 5.1: Share of runs or questions that met the scoring rule

!eq sign | Equation 5.2: Exact two-sided sign test on paired results

### 5.5.3 Finding the Right Material

Figure 5.7 shows how many of the 120 knowledge questions Gemma 4 12B answered, by set-up. Alone it answered 9; with Burrow it answered 102, more than with plain retrieval (94) or a Chroma vector database (75). The cloud model, Claude, answered 40 alone and 109 when given the same vault through Burrow. On the 50 reasoning problems, which need no memory, Burrow left the vault out of every one and the model solved 48, while plain retrieval with its answer-only-from-excerpts rule cut it from 47 to 7.

!fig figures/v2/chart-accuracy-main.png | Figure 5.7: Answers right by set-up and task type, Gemma 4 12B and the cloud model | 6.2

A decision is harder to find than a fact, because a request seldom uses its words. In a pre-registered test, 20 Matatu tasks were worded unlike the payment decision and 40 unrelated decisions were added to the Ledger. Panel b of Figure 5.8 shows the result. When decisions were attached newest first, the payment decision reached the tool in 12 of 20 tasks, and in none once three newer decisions cited the same file. Ranked by relevance it reached the tool in 19 of 20, and 19 with the three newer decisions, against 18 of 20 for plain vector search over the decisions. The one miss was missed by vector search too.

### 5.5.4 Keeping Earlier Decisions

Panel a of Figure 5.8 shows whether Claude Code, in a second session, kept the decision that the first session had made. Before Burrow kept reasons, the decision arrived without the reason that phone matching fails for group payments, and 3 of 15 runs added a phone check as a safeguard and failed a hidden decision test. With the reason kept, 9 of 9 runs kept to the decision, and every one wrote the rejected approach and the Ledger reference into the code. At the earlier rate, nine clean runs in a row would occur by chance about 13% of the time, so this is a strong sign, not proof. A further 14 of 14 runs on later builds also kept to it.

!fig figures/v5/chart-keep.png | Figure 5.8: Keeping, finding and carrying on, with Burrow against its baselines | 6.2

A small local model was another matter. Gemma 4 12B in OpenCode kept the decision in 2 of 4 runs before the change and 2 of 4 after, with one partial. After the change it received the decision with its reason in 4 of 4 runs, and in one it wrote the rejected fallback anyway, with a comment saying it had been rejected before. Burrow delivered the decision; the model did not obey it. That gap is what the check of Section 5.5.6 addresses.

When a session kept a new decision that reversed an old one, the old one had to be retired, or both would be handed over as in force. In 4 of 4 runs, three by Claude Code and one by Gemma 4 12B, the program named the decision it replaced, and the next session was handed only the new one.

### 5.5.5 Carrying Work On

Figure 5.9 compares four ways of telling a model what an earlier session did, on 30 questions about it, asked in both directions between Qwen3 4B and Gemma 4 12B. Given nothing, the model answered none. Given the whole transcript pasted in, it answered 18. Given Burrow's resume, about 1,800 tokens, it answered 11; the pasted transcript was significantly better (p = 0.039). A resume is a summary, and a summary loses detail.

!fig figures/v5/chart-resume.png | Figure 5.9: Questions about an earlier session answered right, by what the model was given | 6.2

That loss led to the folds of Section 5.4.6, measured in panel c of Figure 5.8. After Claude Code compacted a long session, its own summary kept the constraints and the reason in 12 of 12 answers, but none could quote the error being worked on. With Burrow's folds handed back, 6 of 6 quoted it exactly. Given only what Burrow hands over, a 4B local model answered 5 of 5 questions about the session in each of three runs, the error line word for word, against 0 of 5 from the handoff before folds. Panel d shows the handover to a different program: told to carry on, Gemma 4 12B in OpenCode continued the right step in none of 4 runs with the old handoff, and in 3 of 3 with the new one, keeping its constraint.

Across programs, one relay ran the Matatu work through three models and three programs that shared only Burrow: Gemma 4 12B in OpenCode kept the decision, Claude Code received it through burrow_resume alone and passed all its tests, and Qwen3 4B in the llama.cpp server page named both decisions, both models and the file last changed, reading 1,599 tokens in 0.9 seconds. It also made two errors, describing one rule wrongly and mislabelling one decision. In the n8n workflow, the support agent on qwen3:4b, given a decision Claude Code had kept, refused to match a passenger's payment by phone and amount and gave the Easter Monday reason, while the same workflow with Burrow removed invented a decision and told the passenger her ticket was paid. That comparison removed memory altogether, and a comment in the fixture's code also stated the rule, so it shows delivery across programs, not that Burrow beats another memory.

### 5.5.6 Checking Changes

The verdicts were tested on real changes. With the person's check set for the payment decision, every change that truly broke it was judged breaks, and none of the harmless changes was; the harmless changes that touched the decision's code were judged affected and held once. In Claude Code with only the end-of-turn hook, told to build the fallback without stopping, Claude built it with a passing test, was held with the failing check and the decision, and then undid it, deleted its test and told the person. Its reply began: "I undid the phone-and-amount fallback. It goes against a decision recorded in the Ledger, which I could only read once Burrow's check showed it to me."

Figure 5.10 shows the same check inside three other programs on Gemma 4 12B. Whenever the model edited the decision's code, the check fired, and in every run the model then told the person which decision it went against and why. What happened next depended on the program. Hermes Agent put the code back in 2 of 2 runs, where in 9 earlier runs without the check it had left the fallback and told no one. OpenCode put it back in 3 of 6. OpenClaw put it back in neither of 2; one run said it had reverted when it had not.

!fig figures/v5/chart-gate.png | Figure 5.10: The check inside other programs: runs in which the model told the person, and runs in which it put the code back | 6.2

### 5.5.7 Cost and Speed

Burrow's own work was small beside the model's. With 32 programs keeping 50 decisions each at once while two indexing runs went on, all 1,600 decisions were kept with no loss and no error, and keeping one took a median of 0.003 seconds (95th percentile 0.007), down from 0.168 seconds before commits stopped reading the whole Ledger. Under that load a search took a median of about 1.2 seconds. On the knowledge questions, Burrow's engine took 0.06 seconds before the model started, and an answer took 9.2 seconds in all, against 8.3 for plain retrieval, because it showed the model more of the vault.

### 5.5.8 Error Analysis

Table 5.5 shows one result of each kind, taken from the saved transcripts.

!tab Table 5.5: Examples of results, right and wrong
!widths 1.0,2.0,2.0,1.4
| Outcome | Situation | What the tool did | Why |
| Kept | Claude Code, session 2, asked to handle unmatched payments | Sent them to suspense and wrote "never phone or amount (see Ledger)" in the code | The decision arrived with its reason |
| Delivered, not obeyed | Gemma 4 12B in OpenCode, same task | Wrote the phone fallback with a comment that it had been rejected before | The model overrode a decision it had read |
| Held, then undone | Claude Code told to build the fallback | Built it, was held by the check, undid it and told the person | The end-of-turn hook ran the check |
| Held, not undone | OpenClaw on Gemma 4 12B | Named the decision, said it had reverted, left the code broken | The program let the model stop |
| Missed | One oddly worded task describing the Easter Monday case itself | The decision was not attached | Neither relevance ranking nor vector search placed it |
| Lost detail | Resume between Qwen3 4B and Gemma 4 12B | Answered 11 of 30 questions about the earlier session | A resume summarises; the transcript held more |

The errors fall into three groups. Some were retrieval misses, where the decision never reached the tool. Some were losses of detail, where a summary dropped what a later question needed. The largest were the model's own, where a decision arrived and was not followed; only the check, and not the memory, changed those.

## 5.6 System Testing

### 5.6.1 Test Strategy and Acceptance Criteria

Testing ran at three levels. Unit tests checked each type alone, integration tests drove the server, the hooks and the command line with scripted clients and the real program, and system test cases verified each requirement of Chapter 4 by automated test, by running the program, or by using the application. Normal, wrong, boundary and hostile inputs were included, the last written by an independent automated security review of each change. The acceptance criterion was that every automated test passed and every requirement had a test case whose result matched what was expected. No person other than the developer used the application, so no user acceptance test is claimed.

The final build has 553 automated tests (530 in XCTest and 23 in Swift Testing), and all passed; the logs were read in full. Every push to the repository also runs the tests on a hosted Apple silicon machine.

### 5.6.2 Test Cases, Defects and Retesting

Twenty-four test cases were run, one or more for every requirement, and all passed. Table 5.6 gives the twelve that cover the core workflow and its failure conditions; the full record is in the repository (https://github.com/Satasdin/CAMR/blob/burrow/docs/evaluation/test-cases.md).

!tab Table 5.6: Key test cases and results (all 24 are in the repository)
!widths 0.6,0.95,1.55,1.2,1.35,0.6
| Test ID | Requirement | Scenario and test data | Expected result | Actual result and evidence | Verdict |
| TC-03 | FR-03, DR-02 | A decision kept with no reason; then one with a reason and two files | The first refused; the second stored with reason, files and hashes | As expected; GapFixTests, LedgerTests | Pass |
| TC-04 | FR-04 | A program connects in each protocol era and calls a tool | Decisions in force with the first result, once | As expected; FirstResultRulesTests, DualEraMCPTests | Pass |
| TC-05 | FR-05 | 20 oddly worded tasks, 40 unrelated decisions | The payment decision attached | 19 of 20; Section 5.5.3 | Pass |
| TC-07 | FR-07 | A file a decision cites is edited | Decision marked check again; Still Right clears it | As expected; GapFixTests | Pass |
| TC-08 | FR-08 | A decision overlapping one in force, kept without saying which holds | Refused once; then kept marked unresolved | As expected; ContradictionTests | Pass |
| TC-09 | FR-09 | Gemma's breaking and harmless changes through burrow check and the pre-commit hook | Breaks refused every time; harmless passes | As in Figure 5.6; VerdictTests, GateTests | Pass |
| TC-10 | FR-10 | A Claude Code session compacted, then asked for the error line | The exact line quoted | 6 of 6; FoldTests | Pass |
| TC-11 | FR-11 | An AI shares a decision with the team | Held until the person approves; then reaches a teammate | As expected; TeamSecurityTests | Pass |
| TC-14 | NFR-02, NFR-03 | 32 programs keep 50 decisions each at once | 1,600 kept, none lost; times reported | As expected; Section 5.5.7 | Pass |
| TC-15 | NFR-04 | A note written to steer an AI; a session holding a key and a password | Note flagged, never a rule; secrets removed | As expected; GapFixTests, FoldPrivacyTests | Pass |
| TC-16 | NFR-05 | An AI program asks to approve a folder and to override a decision | Both refused, with the reason named | As expected; PersonPresenceTests | Pass |
| TC-23 | IR-03 | Ollama stopped during a search | Search continues on words | As expected; ToolsTests | Pass |

Defects were found mostly by real runs and by the security reviews, recorded with a numbered decision, fixed and retested. Real runs found, among others, decisions handed over without their reasons, commits that could overwrite each other within a second, two programs' sessions merged into one, and programs that never showed Burrow's instructions to their model. The security reviews found, among others, that a vault from someone else could name any folder on the computer, that secrets could reach a session's fold, and that a code meant for the person was saved in a form an AI could work out. Each was fixed and retested before the next change. One earlier claim that the full suite passed was found to be wrong because its log had been cut short; since then every log is read in full.

## 5.7 Version Control and Implementation Evidence

Project repository: https://github.com/Satasdin/CAMR, with burrow as its default branch. The engine is in Sources, its tests in Tests, the desktop application in app, the evaluations in trials, and this report with its scripts in docs/report. Figure 5.11 shows the history of the repository.

!fig figures/screens2/console-git.png | Figure 5.11: The history of the repository, its tags and its folders | 6.2

Every change was committed with a message that names its design decision, so the reason for each line can be traced through DECISIONS.md to the run that caused it. The knowledge evaluation was run on a tagged, frozen build, evaluation-2, whose hash is saved with its results. The later evaluations were run on the build of their day, and each result is tied to the commit and the run folder that produced it. Every push runs the automated tests through GitHub Actions, and the log of each run is kept with its commit. [PENDING: push the final build and tag its release.]

## 5.8 Author Oversight and Use of AI-Assisted Tools

Claude Code, a coding assistant from Anthropic running Claude Opus 5.5, wrote most of the code, tests and evaluation scripts at the author's direction and from the author's design, ran the evaluations, reviewed each change for security, drew the figures, and drafted this report from the saved results and the cited sources. Kimi K3 from Moonshot AI was used in an early increment as a model under test and as a judge of answers, and the AI tools of Section 5.2.2 were the subjects of the evaluation. Every output was checked against the automated tests, the saved transcripts and the cited sources. The author chose the problem, the design and the experiments, made the final decisions, and takes full responsibility for the submitted work. The user guide is in the repository (https://github.com/Satasdin/CAMR/blob/burrow/docs/evaluation/user-guide.md).

## 5.9 Evaluation Results, Discussion and Limitations

This section discusses the results against each specific objective and research question.

### 5.9.1 Objectives i to iii: The Problem, Existing Systems and Their Gaps

Chapter 2 answered the first three research questions. Decisions and their reasons are lost because they are recorded by people after the fact, if at all, and AI tools start each session from what their program supplies (Section 2.2). Existing memory systems keep facts, instructions or passages, delivered always or by similarity, and none checks new work against what was decided (Section 2.3). The gap, stated in Section 2.4, is a private memory in which tools record decisions with reasons as they make them, which hands them to every later tool, knows when they are stale, and checks work against them.

### 5.9.2 Objective iv: The Design and Development of the Engine

Burrow was built as designed in Chapter 4 and meets every requirement, as the 24 test cases and 553 automated tests show. It runs on the person's Mac, calls no cloud model, and is used by six real AI programs without changes to them. The design changed during the build where real runs showed a need, and each change is recorded with its reason.

### 5.9.3 Objective v: Finding, Keeping, Carrying On and Checking

On finding, Burrow beat plain retrieval and a vector database on knowledge questions (102 against 94 and 75 of 120) and matched vector search on oddly worded decisions (19 against 18 of 20), while leaving memory out where it would have harmed reasoning. On keeping, the decisive change was keeping the reason with the decision: Claude Code then kept to it in every run. On carrying on, Burrow's resume beat having nothing and the session tools but lost to a pasted transcript, which led to folds and a handover that brought the exact error and the right next step to another program. On checking, the verdicts were right on every real change tested, and the check made each program name the decision it broke.

The results also mark the limits of memory. A strong model such as Claude kept to a decision once it had the reason; a small local model sometimes read the decision and broke it. Memory solved delivery, not obedience. The check narrows that gap by holding a change whatever the model chooses, but whether the code is then put back depends on the program around the model: Hermes Agent and Claude did so, OpenClaw did not.

Table 5.7 summarises how each specific objective was met.

!tab Table 5.7: How each specific objective was met
!widths 0.85,1.6,2.0,1.0
| Objective | Output | Evidence | Status |
| i | Analysis of how decisions are lost | Section 2.2 | Met |
| ii | Review of six related systems | Section 2.3, Table 2.1 | Met |
| iii | Gaps and conceptual framework | Section 2.4, Figure 2.7 | Met |
| iv | Burrow: engine, Ledger, MCP server, check, hooks, app | Sections 5.4 and 5.6; 24 test cases, 553 automated tests | Met |
| v | Evaluation against baselines | Section 5.5; Figures 5.7 to 5.10 | Met, with the limits below |

### 5.9.4 Limitations

The results have six limits. First, the samples are small, from 3 to 30 runs per condition, because each run is a real tool session of several minutes; differences of one or two runs are not evidence, and the main results are stated with their counts. Second, most evaluations used one fixture project and one decision; other kinds of decisions and projects may behave differently. Third, Burrow was compared with no memory, a pasted transcript, vector search and its own earlier builds, but not with a context file kept by hand in the repository, which is the simplest alternative a developer would try. Fourth, the evaluations after the frozen knowledge evaluation ran on the build of their day rather than one frozen build. Fifth, no person other than the developer used the system, so its usability is untested. Sixth, Burrow runs only on a Mac, and team members' names are not cryptographically signed. Chapter 6 draws the conclusions and recommends how these limits can be addressed.
