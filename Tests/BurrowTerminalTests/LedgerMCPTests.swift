@testable import BurrowCore
@testable import BurrowMCP
@testable import BurrowTools
import XCTest

/// The Ledger through MCP: the four-tool door, the old names still answering, the trust line, and a handoff when a connection closes.
final class LedgerMCPTests: XCTestCase {
    private var fixture: VaultFixture!
    private var tools: VaultTools!
    private var server: MCPServer!

    override func setUp() async throws {
        fixture = try VaultFixture()
        let vault = try await fixture.opened()
        let answerer = FakeAnswerer()
        tools = VaultTools(vault: vault, embedder: nil) { _ in answerer }
        server = MCPServer(tools: tools, keepsSessions: true)
        server.toolSet = .door
        _ = await server.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"opencode","version":"1"}}}"#)
    }

    private func call(_ name: String, _ arguments: String) async throws -> String {
        let line = await server.handle(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#)
        let reply = try JSONSerialization.jsonObject(with: XCTUnwrap(line).data(using: .utf8)!) as! [String: Any]
        let content = (reply["result"] as? [String: Any])?["content"] as? [[String: Any]]
        return try XCTUnwrap(content?.first?["text"] as? String, "\(reply)")
    }

    func testTheDoorListsFourToolsAndOldNamesStillAnswer() async throws {
        let line = await server.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let reply = try JSONSerialization.jsonObject(with: XCTUnwrap(line).data(using: .utf8)!) as! [String: Any]
        let names = ((reply["result"] as! [String: Any])["tools"] as! [[String: Any]]).compactMap { $0["name"] as? String }
        XCTAssertEqual(Set(names), ["burrow_find", "burrow_read", "burrow_resume", "burrow_commit", "burrow_check"])  // burrow_check joined the door in D-79
        let old = try await call("vault_search", #"{"query":"retry a failed charge"}"#)
        XCTAssertTrue(old.contains("\nTrust: "), old)
        XCTAssertTrue(old.contains("Retry"))
    }

    func testFindSaysWhenTheVaultDoesNotHoldIt() async throws {
        let text = try await call("burrow_find", #"{"query":"zzqx unheard of words"}"#)
        XCTAssertTrue(text.contains("the vault does not hold this"), text)
    }

    func testCommitResumeAndACorrectionOnTheTrustLine() async throws {
        let kept = try await call("burrow_commit", #"{"kind":"fact","message":"Charges retry five times","files":"Decisions/Retry.md","model":"qwen3:4b"}"#)
        XCTAssertTrue(kept.hasPrefix("Kept as fact "), kept)
        let id = String(kept.dropFirst("Kept as fact ".count).prefix { $0 != " " })
        _ = try await call("burrow_revert", #"{"commit":"\#(id)","right":"They retry three times, as Retry.md says.","model":"claude-opus"}"#)
        let head = try await call("burrow_resume", "{}")
        XCTAssertTrue(head.contains("MARKED WRONG"), head)
        // Signed by the program's own name from initialize; the model's name for itself is kept, labelled as its claim (D-83).
        XCTAssertTrue(head.contains("written by opencode; the model called itself \"qwen3:4b\""), head)
        let found = try await call("burrow_find", #"{"query":"retry a failed charge"}"#)
        XCTAssertTrue(found.contains("The Ledger holds a correction on these files"), found)
        // The correction's own words are model-written: they may come with the search only inside the Ledger's fenced block (D-69).
        let outsideLedger = found.components(separatedBy: "<ledger>").first ?? found
        XCTAssertFalse(outsideLedger.contains("They retry three times"), found)
        let blame = try await call("burrow_blame", #"{"path":"Decisions/Retry.md"}"#)
        XCTAssertTrue(blame.hasPrefix("<ledger>"), blame)
    }

    func testTheServingModelSignsACommitNotTheNameTheModelGives() async throws {
        // A small model in llama.cpp copied "claude-opus-5-5" from an earlier commit (12 November demo).
        tools.servingModel = "qwen3-4b-instruct"
        _ = try await call("burrow_commit", #"{"kind":"decision","because":"The test says so.","message":"Forms use regulation 38(1) as headings","model":"claude-opus-5-5"}"#)
        XCTAssertEqual(tools.ledger.log().first?.author, "qwen3-4b-instruct")
    }

    func testANoteComesWithTheFileItRestsOnHoweverTheSearchIsWorded() async throws {
        // In the 12 November rehearsal a fresh session searched "reconciliation suspense": one shared word, so the
        // decision on the file it was shown did not come with it (D-69).
        _ = try await call("burrow_commit", #"{"kind":"decision","because":"The test says so.","message":"Zebras are counted by stripe alone","files":"Decisions/Retry.md"}"#)
        let found = try await call("burrow_find", #"{"query":"retry a failed charge"}"#)
        XCTAssertTrue(found.contains("Decisions/Retry.md"), found)
        XCTAssertTrue(found.contains("Zebras are counted by stripe alone"), found)
    }

    func testMatchingLedgerNotesComeWithSearchAndCanBeTurnedOff() async throws {
        _ = try await call("burrow_commit", #"{"kind":"fact","message":"A failed charge is retried three times before the order is cancelled","files":"Decisions/Retry.md","model":"claude-opus"}"#)
        let found = try await call("burrow_find", #"{"query":"how many times is a failed charge retried"}"#)
        XCTAssertTrue(found.contains("Notes earlier sessions left in the Ledger"), found)
        XCTAssertTrue(found.contains("retried three times before the order is cancelled"), found)
        tools.ledgerNotesOn = false
        tools.trustLinesOn = false
        let plain = try await call("burrow_find", #"{"query":"how many times is a failed charge retried"}"#)
        XCTAssertFalse(plain.contains("Notes earlier sessions"), plain)
        XCTAssertFalse(plain.contains("Trust:"), plain)
    }

    func testWritesAreRefusedOutsideMCP() async throws {
        let chat = VaultTools(vault: tools.vault, embedder: nil) { _ in FakeAnswerer() }
        let result = try await chat.call("burrow_commit", arguments: ["kind": "fact", "message": "x"])
        XCTAssertTrue(result.isError)
        XCTAssertTrue(chat.ledger.log().isEmpty)
    }

    func testCitedPathsStayInsideTheVault() async throws {
        _ = try await call("burrow_commit", #"{"kind":"fact","message":"Paths","files":"/etc/passwd, ../outside.md, Decisions/Retry.md"}"#)
        XCTAssertEqual(tools.ledger.log().first?.cites.keys.sorted(), ["Decisions/Retry.md"])
    }

    func testEachRunOfAProgramIsItsOwnConversationWithItsOwnHandoff() async throws {
        // Stress workflow 4b, 12 November: every claude -p run after the first left no handoff (D-72). On 14 November six
        // n8n runs and two claude -p runs a minute apart merged into one conversation; each connection is now its own (D-86).
        _ = try await call("burrow_commit", #"{"kind":"decision","because":"The test says so.","message":"First run's decision","files":"Decisions/Retry.md"}"#)
        await server.serve(readLine: { nil }, write: { _ in })
        let again = MCPServer(tools: VaultTools(vault: tools.vault, embedder: nil) { _ in FakeAnswerer() }, keepsSessions: true)
        again.toolSet = .door
        _ = await again.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"opencode","version":"1"}}}"#)
        _ = await again.handle(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"burrow_commit","arguments":{"kind":"decision","because":"The test says so.","message":"Second run's decision","files":"Decisions/Retry.md"}}}"#)
        await again.serve(readLine: { nil }, write: { _ in })
        let handoffs = tools.ledger.log().filter { $0.kind == .handoff }
        XCTAssertEqual(handoffs.count, 2, handoffs.map(\.message).joined(separator: " | "))
        XCTAssertEqual(Set(handoffs.map(\.session)).count, 2)
        for handoff in handoffs { XCTAssertTrue(handoff.message.contains("keeping 1 commit"), handoff.message) }
    }

    func testAConnectionThatOnlyListsToolsLeavesNoConversation() async throws {
        // n8n opens a connection per model turn just to list the tools (14 November traffic log); those leave nothing.
        let lister = MCPServer(tools: VaultTools(vault: tools.vault, embedder: nil) { _ in FakeAnswerer() }, keepsSessions: true)
        _ = await lister.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"@n8n/n8n-nodes-langchain.mcpClientTool","version":"1.4"}}}"#)
        _ = await lister.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        await lister.serve(readLine: { nil }, write: { _ in })
        XCTAssertEqual(tools.sessions.list().count, 0)
        XCTAssertTrue(tools.ledger.log().isEmpty)
    }

    func testTheProgramSignsACommitAndTheModelsOwnNameIsOnlyItsClaim() async throws {
        // 14 November, n8n run 4: qwen3:8b passed model "claude-code", copied from the Ledger, and was recorded as the author.
        let made = try await call("burrow_commit", #"{"kind":"decision","because":"Easter Monday.","message":"Match by reference only","model":"claude-code"}"#)
        XCTAssertTrue(made.hasPrefix("Kept as decision"), made)
        let kept = try XCTUnwrap(tools.ledger.log().first)
        XCTAssertEqual(kept.author, "opencode")
        XCTAssertEqual(kept.client, "opencode")
        XCTAssertEqual(kept.modelSaid, "claude-code")
        XCTAssertEqual(kept.byline, "written by opencode; the model called itself \"claude-code\"")
        // It survives the round trip through the Markdown file.
        XCTAssertEqual(Ledger.parse(Ledger.markdown(kept))?.modelSaid, "claude-code")
    }

    func testLookupsAreSearchesAndReadsNotResumesChecksOrCommits() async throws {
        // 14 November walkthrough: session 2 showed "3 lookups" for a resume, a check and a commit.
        _ = try await call("burrow_resume", "{}")
        _ = try await call("burrow_find", #"{"query":"retry a failed charge"}"#)
        _ = try await call("burrow_check", "{}")
        _ = try await call("burrow_commit", #"{"kind":"decision","because":"The test says so.","message":"Retry three times","files":"Decisions/Retry.md"}"#)
        let record = try XCTUnwrap(tools.connection)
        XCTAssertEqual(record.trail?.count, 4)
        XCTAssertEqual(record.lookups.count, 1)
        await server.serve(readLine: { nil }, write: { _ in })
        let handoff = try XCTUnwrap(tools.ledger.log().first { $0.kind == .handoff })
        XCTAssertTrue(handoff.message.hasPrefix("opencode stopped after resuming, 1 lookup, checking its change and keeping 1 commit."), handoff.message)
    }

    func testTwoProgramsAtOnceKeepTheirOwnSessions() async throws {
        // Stress workflow 4b, 12 November: two claude -p agents at once joined one session, overwrote each other's trail,
        // and left one handoff that mixed both, carrying branch work onto main (D-73).
        let other = MCPServer(tools: VaultTools(vault: tools.vault, embedder: nil) { _ in FakeAnswerer() }, keepsSessions: true)
        other.toolSet = .door
        _ = await other.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"opencode","version":"1"}}}"#)
        _ = try await call("burrow_commit", #"{"kind":"decision","because":"The test says so.","message":"Agent A's decision","files":"Decisions/Retry.md"}"#)
        _ = await other.handle(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"burrow_commit","arguments":{"kind":"decision","because":"The test says so.","message":"Agent B's decision","files":"Decisions/Retry.md","branch":"luggage"}}}"#)
        await server.serve(readLine: { nil }, write: { _ in })
        await other.serve(readLine: { nil }, write: { _ in })
        let handoffs = tools.ledger.log().filter { $0.kind == .handoff }
        XCTAssertEqual(handoffs.count, 2, handoffs.map(\.message).joined(separator: " | "))
        XCTAssertEqual(Set(handoffs.map(\.session)).count, 2)
        for handoff in handoffs { XCTAssertTrue(handoff.message.contains("keeping 1 commit"), handoff.message) }
        let open = try FileManager.default.contentsOfDirectory(atPath: tools.sessions.folder.path).filter { $0.hasSuffix(".open") }
        XCTAssertEqual(open, [])
    }

    func testAHoldLeftByAProcessThatIsGoneIsCleared() throws {
        let store = tools.sessions
        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        try "999999 left-by-a-crash".write(to: store.folder.appendingPathComponent("s9.open"), atomically: true, encoding: .utf8)
        let token = try XCTUnwrap(store.hold("s9"))
        XCTAssertNil(store.hold("s9"))
        store.release("s9", token: token)
        XCTAssertNotNil(store.hold("s9"))
        // A session file from a synced or shared vault cannot steer a hold, a release or a save outside the sessions folder.
        XCTAssertNil(store.hold("../../outside"))
        var crafted = SessionRecord(id: "../escape")
        crafted.client = "opencode"
        XCTAssertThrowsError(try store.save(crafted))
        try #"{"id":"../../x","started":"2026-11-12T00:00:00Z","updated":"2099-01-01T00:00:00Z","turns":[]}"#
            .write(to: store.folder.appendingPathComponent("crafted.json"), atomically: true, encoding: .utf8)
        XCTAssertFalse(store.list().contains { $0.id.contains("/") })
    }

    func testAClosedConnectionLeavesAHandoff() async throws {
        _ = try await call("burrow_find", #"{"query":"retry a failed charge"}"#)
        await server.serve(readLine: { nil }, write: { _ in })
        let handoffs = tools.ledger.log().filter { $0.kind == .handoff }
        XCTAssertEqual(handoffs.count, 1)
        XCTAssertTrue(handoffs[0].message.hasPrefix("opencode stopped after 1 lookup"), handoffs[0].message)
    }
}
