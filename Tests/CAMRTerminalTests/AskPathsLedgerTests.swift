@testable import CAMRCore
@testable import CAMRTools
import XCTest

/// `camr ask` (both its paths) and the MCP `vault_ask` hear the Ledger from AskLedger, as `camr chat` and the app's
/// Ask do, and their answers go through the same citation check; the engine's own words are not changed (D-96).
final class AskPathsLedgerTests: XCTestCase {
    private var fixture: VaultFixture!
    private var vault: Vault!
    private var answerer: FakeAnswerer!
    private var tools: VaultTools!

    private let question = "How many times is a failed charge retried from December?"

    override func setUp() async throws {
        fixture = try VaultFixture()
        vault = try await fixture.opened()
        answerer = FakeAnswerer()
        let answerer = answerer!
        tools = VaultTools(vault: vault, embedder: nil) { _ in answerer }
    }

    private func keep() throws -> LedgerCommit {
        try tools.ledger.commit(.decision, "From December the retry limit for a failed charge is five, and I check it each Monday",
                                body: "Because: the bank asked for more tries.", author: "claude-opus", client: "claude-code")
    }

    /// The engine's words for a brief with the Ledger added beside them, as `Asking.adding` puts them.
    private func expected(_ brief: Brief, notes: String) -> (system: String, user: String) {
        let rules = brief.route.mode == .none ? Asking.system(for: question, memory: true, skill: brief.skill) : brief.system
        return (rules + "\n\n" + AskLedger.rule, notes + "\n\n" + brief.user)
    }

    // MARK: vault_ask

    func testVaultAskHearsTheLedgerAndChecksItsCitations() async throws {
        let kept = try keep()
        answerer.reply = "Five tries (Ledger \(kept.id)), because the bank asked. (notes/plan.md:12)"
        let result = try await tools.call("vault_ask", arguments: ["question": question])
        let brief = try await tools.prepared(question, folder: nil)
        let context = AskLedger.context(vault: vault, question: question, shown: Set(brief.retrieved.paths))
        XCTAssertEqual(context.notes.map(\.id), [kept.id])
        let sent = try XCTUnwrap(answerer.prompts.first)
        let wanted = expected(brief, notes: context.text)
        XCTAssertEqual(sent.system, wanted.system)
        XCTAssertEqual(sent.user, wanted.user)
        XCTAssertTrue(sent.user.contains("- \(AskLedger.label(kept.id)) [decision]: From December"), sent.user)
        XCTAssertTrue(sent.user.contains("Because: the bank asked for more tries."), sent.user)

        XCTAssertTrue(result.text.contains("\nFive tries (Ledger \(kept.id)), because the bank asked.\n"), result.text)
        XCTAssertFalse(result.text.contains("asked. (notes/plan.md:12)"), result.text)
        XCTAssertTrue(result.text.contains("Not among what it read, so not a source: notes/plan.md:12"), result.text)
        XCTAssertTrue(result.text.contains("Ledger notes it was given, each with its reason (cited in the answer: \(AskLedger.label(kept.id))):\n<ledger>"), result.text)
        XCTAssertEqual(result.ledger, [kept.id])
    }

    func testVaultAskWithNothingInTheLedgerSendsTheEnginesOwnWords() async throws {
        _ = try await tools.call("vault_ask", arguments: ["question": question])
        let brief = try await tools.prepared(question, folder: nil)
        let sent = try XCTUnwrap(answerer.prompts.first)
        XCTAssertEqual(sent.system, brief.system)
        XCTAssertEqual(sent.user, brief.user)
    }

    func testVaultAskLeavesTheLedgerOutForABaseline() async throws {
        _ = try keep()
        tools.ledgerNotesOn = false
        let result = try await tools.call("vault_ask", arguments: ["question": question])
        let brief = try await tools.prepared(question, folder: nil)
        XCTAssertEqual(answerer.prompts.first?.system, brief.system)
        XCTAssertEqual(answerer.prompts.first?.user, brief.user)
        XCTAssertFalse(result.text.contains("<ledger>"), result.text)
        XCTAssertTrue(result.ledger.isEmpty)
    }

    // MARK: camr ask --mode engine

    func testTheEngineHearsTheLedgerBesideItsBrief() async throws {
        let kept = try keep()
        answerer.reply = "Five tries (Ledger \(kept.id)), because the bank asked. (notes/plan.md:12)"
        let profile = ModelProfile.unmeasured("test")
        let reply = try await vault.engage(question, profile: profile, answerer: answerer, notes: AskLedger.source(vault: vault))
        let brief = try await vault.brief(question, budget: profile.budget)
        let context = AskLedger.context(vault: vault, question: question, shown: Set(brief.retrieved.paths))
        XCTAssertEqual(reply.handed?.ids, [kept.id])
        let wanted = expected(brief, notes: context.text)
        XCTAssertEqual(answerer.prompts.first?.system, wanted.system)
        XCTAssertEqual(answerer.prompts.first?.user, wanted.user)
        // The engine's own retry on a wrong citation keeps the Ledger in the second ask too.
        if reply.retried { XCTAssertTrue(answerer.prompts[1].user.hasPrefix(wanted.user)) }
        XCTAssertEqual(reply.checked.ledgerCited, [kept.id])
        XCTAssertEqual(reply.checked.unverified, ["notes/plan.md:12"])
        XCTAssertEqual(reply.checked.text, "Five tries (Ledger \(kept.id)), because the bank asked.")
    }

    func testTheEngineWithoutNotesIsUnchanged() async throws {
        _ = try keep()
        let profile = ModelProfile.unmeasured("test")
        let reply = try await vault.engage(question, profile: profile, answerer: answerer)
        let brief = try await vault.brief(question, budget: profile.budget)
        XCTAssertNil(reply.handed)
        XCTAssertEqual(answerer.prompts.first?.system, brief.system)
        XCTAssertEqual(answerer.prompts.first?.user, brief.user)
    }

    // MARK: camr ask (walk, search, none)

    func testThePlainAskHearsTheLedgerInEveryMode() async throws {
        let kept = try keep()
        answerer.reply = "Five tries (Ledger \(kept.id)), because the bank asked."
        for mode in [Mode.walk, .search, .none] {
            answerer.prompts = []
            let answer = try await vault.ask(question, mode: mode, answerer: answerer, notes: AskLedger.source(vault: vault))
            let context = AskLedger.context(vault: vault, question: question, shown: Set(answer.retrieved.paths))
            XCTAssertEqual(answer.handed?.ids, [kept.id], "\(mode)")
            // A question asked without the vault still has the person's decision, so it gets the rules for answering
            // from material rather than "answer from what you know".
            XCTAssertEqual(answerer.prompts.first?.system, Asking.rules(for: question) + "\n\n" + AskLedger.rule, "\(mode)")
            XCTAssertEqual(answerer.prompts.first?.user, context.text + "\n\n" + Asking.prompt(question: question, excerpts: answer.retrieved.excerpts), "\(mode)")
            XCTAssertEqual(answer.checked.ledgerCited, [kept.id], "\(mode)")
        }
    }

    func testThePlainAskWithoutNotesIsUnchanged() async throws {
        _ = try keep()
        _ = try await vault.ask(question, mode: .none, answerer: answerer)
        XCTAssertEqual(answerer.prompts.first?.system, Asking.withoutMemory)
        XCTAssertEqual(answerer.prompts.first?.user, question)
    }

    func testAnIdTheLedgerDidNotHandOverIsNotASource() async throws {
        _ = try keep()
        answerer.reply = "Five tries (Ledger 20260101-120000-0a1b)."
        let answer = try await vault.ask(question, mode: .walk, answerer: answerer, notes: AskLedger.source(vault: vault))
        XCTAssertEqual(answer.checked.text, "Five tries.")
        XCTAssertEqual(answer.checked.unverified, ["Ledger 20260101-120000-0a1b"])
    }

    // MARK: The stream `camr ask` prints through

    func testTheStreamPrintsEachLineChecked() {
        var printed = ""
        let stream = CheckedStream { printed += $0 }
        stream.shown = [ShownLines(path: "Decisions/Retry.md", startLine: 1, endLine: 3)]
        stream.ledger = ["20261114-065345-a355"]
        for piece in ["Three tries (Decisions/Retry.md:3", ").\nYou pay 40% (Ledger 20261114-065345-a355) (notes/", "plan.md:12)"] { stream.add(piece) }
        XCTAssertEqual(printed, "Three tries (Decisions/Retry.md:3).\n")
        stream.finish()
        XCTAssertEqual(printed, "Three tries (Decisions/Retry.md:3).\nYou pay 40% (Ledger 20261114-065345-a355)")
    }
}
