# Requirements traceability

> Paths under `trials/`, `docs/report/`, `docs/demo/` and `design/` are on the [docs/reports branch](https://github.com/Satasdin/Burrow/tree/docs/reports), which keeps the project report and every evaluation's scripts, transcripts and results.

Each requirement of Chapter 4 traced to the component that implements it and the test that verifies it.

Each requirement of Chapter 4 (November 2026 report) traced back to its specific objective and forward to the component that implements it, the test case that verifies it, and where its result is reported.


**Table R1: Traceability from requirement to component and test**

| Requirement | Objective | Component (source) | Test case | Result |
|---|---|---|---|---|
| FR-01 | iv | BurrowCore: Vault.swift, Index.swift, Scanner.swift | TC-01 | Section 5.4.1 |
| FR-02 | iv, v | BurrowCore: Retrieval.swift; BurrowTools: VaultTools.swift | TC-02 | Section 5.5.3 |
| FR-03 | iv | BurrowTools: Ledger.swift, LedgerTools.swift | TC-03 | Section 5.4.2 |
| FR-04 | iv, v | BurrowMCP: MCPServer.swift; BurrowTools: LedgerTools.swift | TC-04 | Section 5.4.4 |
| FR-05 | iv, v | BurrowTools: LedgerRelevance.swift | TC-05 | Section 5.5.3 |
| FR-06 | iv, v | BurrowTools: Ledger.swift (resume), Midway.swift, Sessions.swift | TC-06 | Section 5.5.5 |
| FR-07 | iv | BurrowTools: Ledger.swift (staleness, confirm, revert) | TC-07 | Section 5.4.2 |
| FR-08 | iv | BurrowTools: Ledger.swift (overlapping), LedgerTools.swift | TC-08 | Section 5.5.4 |
| FR-09 | iv, v | BurrowTools: Verdict.swift, DecisionChecks.swift, Gate.swift, Hooks.swift, ConnectPlugins.swift | TC-09 | Section 5.5.6 |
| FR-10 | iv, v | BurrowTools: Fold.swift, Hooks.swift | TC-10 | Section 5.5.5 |
| FR-11 | iv | BurrowCore: Teams.swift; BurrowTools: TeamLedger.swift, TeamPending.swift, TeamTools.swift | TC-11 | Section 5.4.7 |
| FR-12 | iv | app: the Ledger page, Watch panel and Programs page | TC-12 | Section 5.4 |
| NFR-01 | iv | BurrowCore: Ollama.swift (127.0.0.1 by default) | TC-13 | Section 5.2.1 |
| NFR-02 | iv | BurrowTools: Ledger.swift (commit named with link(2)) | TC-14 | Section 5.4.2 |
| NFR-03 | v | trials/stress/concurrent.py | TC-14 | Section 5.5.7 |
| NFR-04 | iv | BurrowTools: Steering.swift, Secrets.swift | TC-15 | Section 5.4.6 |
| NFR-05 | iv | BurrowCore: LinkApprovals.swift; BurrowTools: PersonPresence.swift | TC-16 | Section 5.4.7 |
| NFR-06 | iv | Package.swift; .github/workflows/tests.yml | TC-17 | Section 5.6.1 |
| DR-01 | iv | BurrowCore: SafeRead.swift, Vault.swift | TC-18 | Section 5.4.1 |
| DR-02 | iv | BurrowTools: Ledger.swift (LedgerCommit) | TC-03 | Section 5.4.2 |
| DR-03 | v | trials/ (tasks and hidden tests outside the vault) | TC-19 | Section 5.3.2 |
| DR-04 | iv | BurrowCore: Index.swift | TC-20 | Section 5.4.1 |
| IR-01 | iv | BurrowMCP: MCPServer.swift | TC-21 | Section 5.4.3 |
| IR-02 | iv | BurrowTools: Connect.swift, ConnectPlugins.swift; burrow: ConnectCommand.swift | TC-22 | Section 5.4.3 |
| IR-03 | iv | BurrowCore: Retrieval.swift (words alone) | TC-23 | Section 5.6.2 |
| IR-04 | iv | The vault format: plain Markdown with [[links]] | TC-24 | Section 5.4.1 |
