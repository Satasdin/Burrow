# Test cases and results

> Paths under `trials/`, `docs/report/`, `docs/demo/` and `design/` are on the [docs/reports branch](https://github.com/Satasdin/CAMR/tree/docs/reports), which keeps the project report and every evaluation's scripts, transcripts and results.

The full test record behind Section 5.6 of the report. Each case names the requirement it verifies; [traceability.md](traceability.md) traces each requirement to its component.

The record below covers the November 2026 build (repository branch vault-app, 15 November). The automated tests named as evidence are in the Tests folder: 530 XCTest and 23 Swift Testing tests, all passing on 15 November 2026 (full log read). Section numbers refer to Chapter 5 of the report.


**Table T1: Test cases and results**

| Test ID | Requirement | Scenario and test data | Expected result | Actual result and evidence | Verdict |
|---|---|---|---|---|---|
| TC-01 | FR-01 | A vault indexed twice, then with one file changed and one removed | Nothing rebuilt the second time; old words gone the third time | As expected; CAMRCoreTests (testAnUnchangedProjectIsNotRebuilt, testAChangedAndARemovedFileAreCaughtAndLeaveNoOldWords) | Pass |
| TC-02 | FR-02 | A request whose words are absent from the right file | The file found by meaning, with file and lines | As expected; CAMRCoreTests (testMeaningFindsWhatWordsMiss); 102 of 120 knowledge questions, Section 5.5.3 | Pass |
| TC-03 | FR-03, DR-02 | A decision kept with no reason; then one with a reason, rejected options and two files | The first refused; the second stored with reason, files and hashes, signed by the program | As expected; GapFixTests, LedgerTests | Pass |
| TC-04 | FR-04 | A program connects in each protocol era and calls a tool | The decisions in force with the first result, once, each reason whole | As expected; FirstResultRulesTests, DualEraMCPTests | Pass |
| TC-05 | FR-05 | 20 oddly worded tasks with 40 unrelated decisions; three newer decisions on the same file | The payment decision attached | 19 of 20 in both conditions; LedgerRelevanceTests; Section 5.5.3 | Pass |
| TC-06 | FR-06 | A program resumes after a Claude Code session | Plan, where it stopped, what it was in the middle of, latest decisions | As expected; MidwayTests, FirstResultRulesTests; 3 of 3 handover runs, Section 5.5.5 | Pass |
| TC-07 | FR-07 | A file a decision cites is edited; the person says it still holds | Decision marked check again; Still Right clears it | As expected; GapFixTests, LedgerTests | Pass |
| TC-08 | FR-08 | A decision overlapping one in force, kept without saying which holds; then with supersedes | Refused once, then kept marked unresolved; with supersedes the old one is retired | As expected; ContradictionTests; 4 of 4 real runs retired the old rule | Pass |
| TC-09 | FR-09 | Gemma's breaking and harmless changes through camr check, the Stop hook, the pre-commit hook and the plugins | Breaks refused every time; harmless passes; a touched decision held once | As expected; VerdictTests, GateTests, ConnectTests; Figure 5.6 | Pass |
| TC-10 | FR-10 | A Claude Code session compacted, then asked for the error line | The exact line quoted | 6 of 6; FoldTests; Section 5.5.5 | Pass |
| TC-11 | FR-11 | An AI shares a decision with the team; two people commit at once | Held until the person approves; then reaches the teammate; no conflict | As expected; TeamTests, TeamSecurityTests, TeamFilesTests | Pass |
| TC-12 | FR-12 | The application opened on a vault with decisions and connected programs | Ledger, Watch panel and Programs page shown; a program connected | As in Figures 5.3 and 5.4 of the report and the screens in more-screens.md; LedgerScreenTests | Pass |
| TC-13 | NFR-01 | The source inspected for network calls; CAMR run with no network | Only the local model service at 127.0.0.1 by default, the local llama.cpp server, and the team remote when sharing | As expected; inspection of Sources (Ollama.swift, KVShelf.swift, Teams.swift) | Pass |
| TC-14 | NFR-02, NFR-03 | 32 programs keep 50 decisions each at once, with two indexing runs | 1,600 kept, none lost; times reported | 1,600 of 1,600; commit median 0.003 s; trials/stress/RESULTS.md | Pass |
| TC-15 | NFR-04 | A note written to steer an AI; a session holding a key, a token and a password | Note flagged and never handed over as a rule; secrets removed from folds and handoffs | As expected; GapFixTests, FoldPrivacyTests, SecretsSpeedTests | Pass |
| TC-16 | NFR-05 | An AI program asks to approve a folder, approve a share and override a decision | All refused, naming the reason; an override needs a code from a notification | As expected; PersonPresenceTests, LinkApprovalTests, LinkApprovalHardeningTests | Pass |
| TC-17 | NFR-06 | swift test on the final source; Package.swift inspected; tests run on push | All tests pass; no third-party package | 553 passed; .github/workflows/tests.yml | Pass on one machine and the hosted runner |
| TC-18 | DR-01 | A linked folder read and searched | Its files read, never changed | As expected; VaultOfEverythingTests (testALinkedFolderCanBeReadButNotChanged) | Pass |
| TC-19 | DR-03 | The evaluation folders inspected | Tasks, answer keys and hidden tests outside the vault; every transcript read for stray reads | As expected; one confounded run set aside (trials/stress/results/relay-run1-confounded) | Pass |
| TC-20 | DR-04 | The index deleted, or built by an older version | Rebuilt from the vault with nothing lost | As expected; SearchStandingTests (testAnIndexBuiltByAnOlderVersionRebuildsItself) | Pass |
| TC-21 | IR-01 | A client in the initialise-first era and one in the 2026 stateless era | Both served; tools offered only after initialising in the first era | As expected; DualEraMCPTests, MCPTests | Pass |
| TC-22 | IR-02 | camr connect for each program, on settings files with other servers, comments and hostile paths | CAMR added, every other setting kept, a backup made; unsafe files refused | As expected; ConnectTests (17 tests) | Pass |
| TC-23 | IR-03 | The embedding service unreachable during a search | Search continues on words | As expected; ToolsTests, LedgerRelevanceTests (BrokenEmbedder) | Pass |
| TC-24 | IR-04 | The vault opened in Obsidian; links between notes followed | Notes and links work in both | As expected; NoteLinkTests, TUITests (wiki links), VaultOfEverythingTests (Obsidian settings left out) | Pass |
