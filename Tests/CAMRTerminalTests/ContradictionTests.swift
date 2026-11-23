@testable import CAMRCore
@testable import CAMRMCP
@testable import CAMRTools
import XCTest

/// A decision that contradicts an older one is caught when it is kept (D-94): supersedes retires the older one and shows
/// it as replaced, alongside keeps both, and a decision kept over the one refusal is handed over marked UNRESOLVED.
final class ContradictionTests: XCTestCase {
    private var fixture: VaultFixture!
    private var tools: VaultTools!
    private var server: MCPServer!

    private let monday = #"{"kind":"decision","message":"A statement line whose reference matches no ticket goes to suspense; never match on phone number and amount","because":"Finance, 3 June: conductors pay for whole groups from one phone, so phone and amount repeat","files":"Decisions/Retry.md"}"#
    private let wednesday = #"{"kind":"decision","message":"A statement line whose reference matches no ticket goes on the one open ticket with the same phone number and amount from the last ten minutes","because":"Finance, 10 November: the 3 June rule is reversed","files":"Decisions/Retry.md"}"#

    override func setUp() async throws {
        fixture = try VaultFixture()
        let vault = try await fixture.opened()
        let answerer = FakeAnswerer()
        tools = VaultTools(vault: vault, embedder: nil) { _ in answerer }
        server = MCPServer(tools: tools, keepsSessions: true)
        server.toolSet = .door
        _ = await server.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"claude-code","version":"1"}}}"#)
    }

    private func call(_ name: String, _ arguments: String) async throws -> (text: String, isError: Bool) {
        let line = await server.handle(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#)
        let reply = try JSONSerialization.jsonObject(with: XCTUnwrap(line).data(using: .utf8)!) as! [String: Any]
        let result = reply["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        return (try XCTUnwrap(content?.first?["text"] as? String, "\(reply)"), result?["isError"] as? Bool ?? false)
    }

    private func keptID(_ text: String) -> String {
        String(text.dropFirst("Kept as decision ".count).prefix { $0 != " " })
    }

    func testAnOverlappingDecisionIsRefusedOnceWithTheOldOneAndTheThreeWaysOut() async throws {
        let first = try await call("camr_commit", monday)
        XCTAssertTrue(first.text.hasPrefix("Kept as decision "), first.text)
        let old = keptID(first.text)
        let refused = try await call("camr_commit", wednesday)
        XCTAssertTrue(refused.isError, refused.text)
        XCTAssertTrue(refused.text.hasPrefix("Not kept yet"), refused.text)
        XCTAssertTrue(refused.text.contains(old), refused.text)
        XCTAssertTrue(refused.text.contains("Because: Finance, 3 June"), "the old decision's reason comes with it: \(refused.text)")
        XCTAssertTrue(refused.text.contains("supersedes: \(old)"), refused.text)
        XCTAssertTrue(refused.text.contains("alongside: yes"), refused.text)
        XCTAssertTrue(refused.text.contains("ask the person"), refused.text)
        XCTAssertEqual(tools.ledger.log().count, 1, "nothing was kept on the refusal")
    }

    func testSupersedesRetiresTheOldDecisionAndShowsItAsReplaced() async throws {
        let old = keptID(try await call("camr_commit", monday).text)
        let args = wednesday.dropLast() + #","supersedes":"\#(old)"}"#
        let kept = try await call("camr_commit", String(args))
        XCTAssertFalse(kept.isError, kept.text)
        XCTAssertTrue(kept.text.contains("It replaces \(old)"), kept.text)
        let new = keptID(kept.text)
        // Stored as reverts, so every place that leaves out retired commits already does: no format change.
        XCTAssertEqual(tools.ledger.find(new)?.reverts, old)
        XCTAssertEqual(VaultTools.inForce(tools.ledger).map(\.id), [new])
        let rules = tools.rulesInForce()
        XCTAssertFalse(rules.contains("never match on phone"), rules)
        let resume = try await call("camr_resume", "{}").text
        XCTAssertTrue(resume.contains("REPLACED by \(new) (written by claude-code)"), resume)
        XCTAssertFalse(resume.contains("MARKED WRONG"), resume)
        XCTAssertFalse(resume.contains("UNRESOLVED"), resume)
    }

    func testAlongsideKeepsBothWithoutAQuestion() async throws {
        _ = try await call("camr_commit", monday)
        let kept = try await call("camr_commit", String(wednesday.dropLast() + #","alongside":true}"#))
        XCTAssertFalse(kept.isError, kept.text)
        XCTAssertEqual(VaultTools.inForce(tools.ledger).count, 2)
        XCTAssertTrue(tools.ledger.unresolved().isEmpty)
        XCTAssertFalse(tools.rulesInForce().contains("UNRESOLVED"))
    }

    func testASecondAttemptGoesThroughMarkedUnresolvedWhereverRulesAreHandedOver() async throws {
        let old = keptID(try await call("camr_commit", monday).text)
        _ = try await call("camr_commit", wednesday)
        let second = try await call("camr_commit", wednesday)
        XCTAssertFalse(second.isError, second.text)
        XCTAssertTrue(second.text.contains("UNRESOLVED"), second.text)
        let new = keptID(second.text)
        XCTAssertEqual(tools.ledger.find(new)?.overlaps, [old])
        XCTAssertEqual(tools.ledger.unresolved(), [new: [old]])
        let note = "UNRESOLVED: may contradict \(old); ask the person which holds."
        XCTAssertTrue(tools.rulesInForce().contains(note), tools.rulesInForce())
        let resume = try await call("camr_resume", "{}").text
        XCTAssertTrue(resume.contains(note), resume)
        // The field survives the file format.
        let file = tools.ledger.folder.appendingPathComponent("main/\(new).md")
        XCTAssertTrue(try String(contentsOf: file, encoding: .utf8).contains("overlaps: [\"\(old)\"]"))
    }

    func testThePersonSettlesItEitherWay() async throws {
        let old = keptID(try await call("camr_commit", monday).text)
        _ = try await call("camr_commit", wednesday)
        let new = keptID(try await call("camr_commit", wednesday).text)
        // Keep both: a confirmation naming what it settles; both stay in force.
        let both = try tools.ledger.bothHold(new, author: "person", client: "CAMR app")
        XCTAssertEqual(both.kind, .confirmation)
        XCTAssertEqual(both.overlaps, [old])
        XCTAssertTrue(tools.ledger.unresolved().isEmpty)
        XCTAssertEqual(VaultTools.inForce(tools.ledger).count, 2)
        XCTAssertThrowsError(try tools.ledger.bothHold(new, author: "person"))
    }

    func testKeepNewerByMarkingTheOldOneWrongSettlesIt() async throws {
        let old = keptID(try await call("camr_commit", monday).text)
        _ = try await call("camr_commit", wednesday)
        let new = keptID(try await call("camr_commit", wednesday).text)
        try tools.ledger.revert(old, why: "Replaced by the newer decision \(new)", author: "person", client: "CAMR app")
        XCTAssertTrue(tools.ledger.unresolved().isEmpty)
        XCTAssertFalse(VaultTools.inForce(tools.ledger).map(\.id).contains(old))
        XCTAssertTrue(VaultTools.inForce(tools.ledger).map(\.id).contains(new))
        // Retired by a correction, not a decision: still "MARKED WRONG".
        let resume = try await call("camr_resume", "{}").text
        XCTAssertTrue(resume.contains("MARKED WRONG"), resume)
    }

    func testUnrelatedDecisionsOnTheSameFileAndFactsAreNotQuestioned() async throws {
        _ = try await call("camr_commit", monday)
        let other = try await call("camr_commit", #"{"kind":"decision","message":"Receipts are printed in Swahili and English","because":"Riders asked at the depot","files":"Decisions/Retry.md"}"#)
        XCTAssertFalse(other.isError, other.text)
        let fact = try await call("camr_commit", #"{"kind":"fact","message":"A statement line whose reference matches no ticket goes on the open ticket with the same phone number","files":"Decisions/Retry.md"}"#)
        XCTAssertFalse(fact.isError, fact.text)
        let elsewhere = try await call("camr_commit", String(wednesday.replacingOccurrences(of: "Decisions/Retry.md", with: "Trips/Lamu.md")))
        XCTAssertFalse(elsewhere.isError, "different files: \(elsewhere.text)")
    }

    func testOneImportStepAwayCounts() async throws {
        // As in Matatu: the Monday decision cites reconcile.py; the Wednesday one cites matcher.py, which it imports.
        let top = FileManager.default.temporaryDirectory.appendingPathComponent("overlap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: top) }
        for (path, text) in [
            "vault/Home.md": "# Home\n",
            "shop/payments/__init__.py": "",
            "shop/payments/matcher.py": "def ticket_for_line(store, line):\n    return store.tickets.get(line.account_ref)\n",
            "shop/payments/reconcile.py": "from .matcher import ticket_for_line\n\n\ndef reconcile(store, lines):\n    return [ticket_for_line(store, line) for line in lines]\n",
        ] {
            let url = top.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let vault = try Vault(project: top.appendingPathComponent("vault"), everything: true)
        // Approvals go to this test's own folder, never the person's (D-101).
        vault.stateFolder = top.appendingPathComponent("state")
        try vault.linkFolder(top.appendingPathComponent("shop"))
        try await vault.refresh(embedder: nil)
        let ledger = Ledger(vault: vault)
        try ledger.commit(.decision, "A statement line whose reference matches no ticket goes to suspense; never match on phone number and amount",
                          body: "Because: conductors pay for whole groups from one phone", files: ["shop/payments/reconcile.py"], author: "claude-code")
        let wednesday = "A statement line whose reference matches no ticket goes on the open ticket with the same phone number and amount"
        XCTAssertEqual(VaultTools.overlapping(vault: vault, ledger: ledger, text: wednesday, files: ["shop/payments/matcher.py"]).count, 1)
        XCTAssertEqual(ledger.overlapping(wednesday, files: ["shop/payments/matcher.py"]).count, 0, "without the import step it is not found")
    }

    func testABadSupersedesIsRefusedAndNothingKept() async throws {
        let bad = try await call("camr_commit", String(wednesday.dropLast() + #","supersedes":"20990101-000000-zzzz"}"#))
        XCTAssertTrue(bad.isError, bad.text)
        XCTAssertTrue(tools.ledger.log().isEmpty)
    }

    func testTheCommitToolOffersBothWays() {
        let commit = VaultTools.ledgerDefinitions.first { $0.name == "camr_commit" }!
        XCTAssertTrue(commit.parameters.contains { $0.name == "supersedes" })
        XCTAssertTrue(commit.parameters.contains { $0.name == "alongside" })
    }

    func testOldLedgerFilesWithoutTheFieldStillParse() throws {
        let text = "---\nid: \"20261112-214056-002e\"\nbranch: \"main\"\nkind: \"decision\"\nauthor: \"x\"\nat: \"2026-11-12T21:40:56Z\"\n---\n\nHello\n"
        let commit = try XCTUnwrap(Ledger.parse(text))
        XCTAssertNil(commit.overlaps)
        XCTAssertFalse(Ledger.markdown(commit).contains("overlaps"))
    }
}
