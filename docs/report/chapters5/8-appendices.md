# Appendices

## Appendix A: Project Schedule and Gantt Chart

Figure A.1 shows the work carried out from March to November 2026, by workstream, with the course milestones, and Table A.1 gives the milestones with their status. CAMR and Engram are earlier working names of the engine.

!fig figures/gantt-plan.png | Figure A.1: Project work plan, March to November 2026 | 6.0

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

## Appendix C: Selected Code and Implementation Details

This appendix gives three short extracts from the submitted source, release burrow-v1.2.3 (https://github.com/Satasdin/Burrow/releases/tag/burrow-v1.2.3), each behind one technical decision discussed in Section 5.3.1. The extracts are Swift, with long lines wrapped, comments shortened and, where marked with an ellipsis, part of a message left out; the full code base is in the repository (https://github.com/Satasdin/Burrow), and DECISIONS.md there records each decision named in the comments. They contain no credentials or private data.

Table C.1 shows how the Ledger module refuses a decision without its reason (FR-03). The reason was made required after Claude Code kept the letter of a payment decision but defeated its purpose in 3 of 15 sessions when no reason was kept (Section 5.4.4.1).

!code Table C.1: The Ledger refusing a decision without a reason (Sources/BurrowTools/LedgerTools.swift)
case "burrow_commit":
    guard let kind = LedgerCommit.Kind(rawValue: given.text("kind")!) else {
        return .failure("Unknown kind.")
    }
    // One line each: a reason is read back by its "Because: " line,
    // so a line break would lose the rest of it.
    let because = oneLine("because"), rejected = oneLine("rejected")
    // A decision without its reason is how a later model re-derives
    // what was turned down (D-74).
    if kind == .decision, because.isEmpty {
        return .failure("A decision needs because: why it was decided, "
            + "with the facts behind it as the person gave them ... "
            + "Add because, and rejected for the options turned down, "
            + "then commit again.")
    }
!endcode

Table C.2 shows the four verdicts of the Check module (FR-09) and the two rules that turn them into action: a change whose check fails is held until the person lets it through, and a change that touches what a decision rests on, or cannot be judged, must be shown once before the work is reported as done.

!code Table C.2: The verdicts of the check and when a change is held (Sources/BurrowTools/Verdict.swift)
public enum Kind: String, Sendable {
    /// The check the person set for the decision failed, or could not
    /// run: Burrow can't say the change keeps to it.
    case breaks
    /// The change touched the functions, classes or blocks the decision rests on.
    case affected
    /// It changed the decision's files, but not the parts the decision rests on.
    case unaffected
    /// Burrow can't tell: no parts are known for the decision, or a file did not parse.
    case unprovable
}

/// True when this verdict holds the change: a failed check the person
/// has not overridden.
public var breaks: Bool { kind == .breaks && !overridden }
/// True when the change should be looked at once (exit 2 until shown).
public var needsLook: Bool {
    kind == .affected || kind == .unprovable || (kind == .breaks && overridden)
}
!endcode

Table C.3 shows the single rule behind NFR-05: every step only the person may take, such as approving a folder, overriding a decision or writing a program's settings, calls requireThePerson, which refuses when Burrow is not running in the person's own terminal or when an AI program is among the processes that started it.

!code Table C.3: The one rule for steps only the person may take (Sources/burrow/Terminal.swift)
/// Why burrow won't take this as the person in their own terminal, or nil
/// when nothing says otherwise (D-104, D-113): stdin and stderr must be
/// terminals, no agent's variables may be set, and no agent may be among
/// burrow's parents or own the session its terminal belongs to.
func whyNotThePerson() -> String? {
    guard isatty(STDIN_FILENO) == 1, isatty(STDERR_FILENO) == 1 else {
        return "it isn't running in a terminal"
    }
    return PersonPresence.refusal()?.reason
}

/// The one call for every step only the person may take (D-113): throws
/// refusal, with the reason, unless burrow is in the person's own terminal
/// and nothing says an agent is running it.
func requireThePerson(_ refusal: String = needsThePerson) throws {
    if let why = whyNotThePerson() {
        throw Failure("\(refusal) Refused because \(why).")
    }
}
!endcode

## Appendix D: Supporting Instruments and Evaluation Evidence

This appendix gives the instruments behind the usability test of Section 5.4.4.6 and points to the full test record of Section 5.4.2. Each volunteer received the same written instructions, which they gave to Claude Code on their own Mac; Claude Code ran the commands and kept notes in a results file, and the volunteer took the steps only a person may take and gave their own opinions. The instructions asked Claude Code to leave the volunteer's name, computer name, serial number and email out of every note, and the reports were sent by the volunteers themselves. Table D.1 gives the protocol and Table D.2 the questions.

!tab Table D.1: The usability test protocol given to each volunteer
!widths 0.6,1.5,4.2
| Step | Task | What was done and recorded |
| 0 | The Mac | The chip, memory, macOS version, free disk space, whether Ollama was installed and which AI programs were present |
| 1 | Install | The volunteer downloaded the app from the project website; whether macOS blocked it and whether Open Anyway was found; then the terminal program was installed with the one-line installer and checked with burrow --version |
| 2 | Models | The embedding model was pulled, then one chat model chosen by the Mac's memory (under 16 GB, 16 to 23 GB, 24 GB or more), with the download time |
| 3 | A vault | A fresh folder with three short notes about something real in the volunteer's life, made a vault with burrow vault new and searched with burrow find; whether the right note came back |
| 4 | Connect | burrow connect previewed the change; the volunteer ran it with --write in their own terminal, or used the app's Programs page |
| 5 | Keep a decision | In a new session: an answer from the notes with burrow_find, then a small decision with its reason in the volunteer's own words, kept with burrow_commit and looked for on the Ledger page |
| 6 | Pick it up | In another new session the volunteer asked, in their own words, what was decided and why, answered only from Burrow |
| 7 | A local model | The same question asked of the local chat model with burrow ask, with whether it gave the decision and its reason and how long it took |
| 8 | Opinions | The questions of Table D.2, answered by the volunteer and written down word for word |
| 9 | The report | A plain-text report of the Mac, each task (done alone, with help or not done, minutes, problems, exact errors) and the answers, sent by the volunteer |

!tab Table D.2: The opinion questions asked of each volunteer
!widths 0.6,5.7
| No. | Question |
| 1 | From 1 (very hard, or not at all) to 5 (very easy, or completely): how easy was installing? |
| 2 | How easy was connecting? |
| 3 | Did the new session remember the decision and the reason? |
| 4 | How clear was the app? |
| 5 | How likely are you to keep using it? |
| 6 | What was the most confusing moment, and what did you expect? |
| 7 | What did Burrow do that was useful to you? |
| 8 | What would you change first? |

The 24 system test cases of Section 5.4.2, each with its steps, expected and actual result and the requirement it verifies, are kept in the repository (https://github.com/Satasdin/Burrow/blob/burrow/docs/evaluation/test-cases.md). The scripts, transcripts and results of every evaluation in Section 5.4.4 are on the docs/reports branch of the same repository, in the trials folder.

## Appendix E: AI-Use Log

Table E.1 records the material use of AI in this project, by period. Full prompts and replies are kept in the Claude Code session records and transcripts. Recorded usage for that increment was US$464.29 for the main Claude Code session, US$10.64 for five helper sessions, and US$33.36 for Kimi.

!tab Table E.1: AI-use log
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
| 17 to 18 Nov | Claude Code (Claude Opus 5.5) | Keeping a long session small, archiving sessions and resuming them in other programs, the session evaluation, the new look of the application, and release burrow-v1.3.0 | Engine, application, evidence, release, report | 589 automated tests locally and on the hosted machine; real Claude Code, Codex and llama.cpp sessions with their raw transcripts kept |
| Ongoing, before final submission | None | The student's own review and edits of this report | The report | Read against the course guide and the saved results |

## Appendix F: Similarity Report

Figure F.1 shows the Turnitin integrity overview of the proposal approved in June 2026: 12% overall similarity, with the bibliography filtered out.

!fig figures/similarity-proposal.png | Figure F.1: Turnitin integrity overview of the approved proposal, June 2026 | 6.2
