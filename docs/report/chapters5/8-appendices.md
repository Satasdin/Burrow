# Appendices

## Appendix A: Project Schedule and Gantt Chart

Figure A.1 shows the work carried out from March to November 2026, by workstream, with the course milestones, and Table A.1 gives the milestones with their status. CAMR and Engram are earlier working names of the engine.

!fig figures/gantt.png | Figure A.1: Project work plan, March to November 2026 | 5.0

!tab Table A.1: Course milestones and their status
!widths 0.5,3.0,1.7,1
| No. | Task | Due date | Status |
| 1 | Supervisor selection and allocation | 7 May 2026 | Done |
| 2 | Document formatting and template creation | 8 May 2026 | Done |
| 3 | Topic creation and selection | - | Done |
| 4 | Abstract and Chapters 1 to 3 | - | Done |
| 5 | Chapters 1 to 3 submitted | 12 June 2026 | Done |
| 6 | Semester I oral defence | 13 to 16 July 2026 | Done |
| 7 | Marking and revision of Chapters 1 to 3 | 31 July 2026 | Done |
| 8 | Chapter 4: System Analysis and Design | 17 August 2026 | Done |
| 9 | Sprint II review | 5 November 2026 | Done |
| 10 | Documentation | November 2026 | Done |

## Appendix B: Feedback-Resolution Matrix

Table B.1 records the feedback received and how each item was resolved.

!tab Table B.1: Feedback received and its resolution
!widths 1.8,0.9,1,2,0.6
| Issue | Source | Affected section | Action | Status |
| "Very hard to understand" | Sprint II review, 5 Nov 2026 | 2.5, 4.4 | The engine was rebuilt around plain files and five named steps, and the report describes it in standard terms | Done |
| "Just a report of benchmarks" | Sprint II review | 1.6, 5.3.1 | A usable app, a terminal chat and an MCP server were built around the engine; the scope now includes them | Done |
| Show it working with native Ollama models | Sprint II review | 5.2, 5.3.2.3 | Ollama is the only model runner; every local result was produced through it | Done |
| The person cannot create or remove their own collections | Sprint II review | 4.4 | The memory is the person's own folder of files; nothing is seeded | Done |
| Model activity should be visible | Sprint II review | 5.3.1.3 | The app shows every program that uses the vault, each conversation's lookups and the files read; the command line states what the engine decided | Done |
| Can it generate reports natively? | Sprint II review | 5.3.1.5 | A conversation, or a decision from it, can be kept in the Ledger and handed to the next model; no report format was built | Partly |
| If it codes, let it code, with live previews | Sprint II review | 1.6 | Coding is left to the programs that connect to the vault, such as OpenCode and Claude Code, which read the code and its decisions through Burrow; live previews were not built | Partly |
| Keep each chapter to its own part, and follow the lecturer's guide for the structure of Chapters 1 to 6 and the references | Supervisor, November 2026 | Chapters 3 to 6 | Chapter 3 names the methods and points to Chapter 4; build detail moved to Chapter 5; side trials moved to the repository's further results; Chapter 6 added | Done |
| Abstract scored 2 of 3 (at most 200 words) | Written assessment, Ms. Eunice Manyasi, 30 June 2026 (37 of 40; "The document is well written") | Abstract | Rewritten last, from the final results, within 200 words | Done |
| Problem statement scored 3 of 4 (background, clarity, gap, citations) | Written assessment, 30 June 2026 | 1.2 | The ideal, the reality and the gap stated with cited evidence, and the consequence quantified | Done |
| Objectives scored 3 of 4 (SMART and linked to the problem) | Written assessment, 30 June 2026 | 1.3, 6.1 | Each objective now has a measured result and a verdict in Section 5.5 and Chapter 6 | Done |
| The appendices and Chapter 5 are too long; some of it belongs on GitHub; show how the system works with a model | Review of the draft, 12 November 2026 | Chapter 5, appendices | The full test record, further results, traceability, user guide and extra screens moved to the repository and linked, leaving four appendices; Section 5.3.1.7 shows the workflows with a model from real runs | Done |

## Appendix C: AI-Use Log

Table C.1 records the material use of AI in this project, by period. Full prompts and replies are kept in the Claude Code session records and transcripts. Recorded usage for that increment was US$464.29 for the main Claude Code session, US$10.64 for five helper sessions, and US$33.36 for Kimi.

!tab Table C.1: AI-use log
!widths 0.85,1.0,1.75,1.2,1.4
| Period (2026) | Tool and model | Used for | Retained output | Verification |
| 29 Sep to 16 Oct | Claude Code (Claude Opus 5.5), one main and five helper sessions | First increment (CAMR): the engine, evaluation harness and app 0.2 to 0.4 written from the student's design; experiments run on cloud machines; figures; Chapter 5 and 6 drafts for that increment | Code, results files, releases v0.2.0 to v0.4.0 | 204 automated tests; a one-command replay recomputed 16 of 16 key results; 40 logged defects fixed and retested or reported open |
| 29 Sep to 16 Oct | Kimi K3 and K2.6 (Moonshot AI) through the API | A cloud model under test; a judge of 2,910 answers that exact matching marked wrong; the writer of 50 news questions | Cached verdicts; cost record | Judge verdicts reported apart from exact-match scores |
| 9 to 11 Nov | Claude Code (Claude Opus 5.5) | Second increment (Burrow): plan, engine, app, terminal, MCP server and Ledger; curated documents and questions, harness and baselines; three evaluations | Source, tests, trials, DECISIONS.md | 212 tests on the frozen source; evaluation plans written before scoring; results saved once |
| 10 Nov | Claude (claude-sonnet-5-5) through the API | The cloud model in the experiments | Saved answers | Scored by fixed answer keys |
| 10 to 12 Nov | Claude Code (Claude Opus 5.5) | This report: chapters drafted from saved results on the layout of earlier graduates' reports, a verified source pack, Word layout with Mendeley Cite, reviews against the course guide | Report and its generators | Each source checked at its published page; every number in Chapter 6 traced to Chapter 5 |
| 12 Nov | Claude Code (Claude Opus 5.5) | The Programs page redesign, the GitHub test workflow and release, and the demonstration clips | Source, tests.yml, release burrow-v1.1.0, clips | The workflow's own runs; captures from real runs only |
| 13 to 16 Nov | Claude Code (Claude Opus 5.5) | The project website, the skill pack and documentation for AI agents, releases burrow-v1.2.0 and burrow-v1.2.1, Chapters 4 to 6 brought to the revised guide, new figures and screenshots, and the usability-test instructions | Website, skills, BURROW.md, releases, report | 553 automated tests locally and on the hosted machine; the installer run against the published release and refused on an altered download; screenshots captured from the released app |
| 16 to 17 Nov | Claude Code (Claude Opus 5.5) | Fixes for the problems the three volunteers met, the disk image and the download page, and releases burrow-v1.2.2 and burrow-v1.2.3 | Engine, application, installer, website, release | 567 automated tests locally and on the hosted machine; a fresh install from the published release; the application installed by the one-line command opened without a macOS block; the disk image checked against its checksum |
| Ongoing, before final submission | None | The student's own review and edits of this report | The report | Read against the course guide and the saved results |

## Appendix D: Similarity Report

Figure D.1 shows the Turnitin integrity overview of the proposal approved in June 2026: 12% overall similarity, with the bibliography filtered out.

!fig figures/similarity-proposal.png | Figure D.1: Turnitin integrity overview of the approved proposal, June 2026 | 6.2
