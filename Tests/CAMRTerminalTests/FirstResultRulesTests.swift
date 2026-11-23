@testable import CAMRCore
@testable import CAMRMCP
@testable import CAMRTools
import XCTest

/// The first tool result each connection gets carries the decisions in force once, in either era and whether or not
/// the program was given the instructions (D-103): OpenClaw and Hermes Agent drop MCP server instructions, so on
/// 14 November a decision reached their model only through a tool that happened to show it.
final class FirstResultRulesTests: XCTestCase {
    private var fixture: VaultFixture!
    private var tools: VaultTools!
    private var server: MCPServer!

    static let decision = "Rent is split 60/40: I pay 40% and Wanjiru pays 60%."
    static let reason = "Wanjiru's room is the bigger one, with its own bathroom."

    override func setUp() async throws {
        fixture = try VaultFixture()
        let vault = try await fixture.opened()
        tools = VaultTools(vault: vault, embedder: nil) { _ in FakeAnswerer() }
        server = MCPServer(tools: tools, keepsSessions: true)
        server.toolSet = .door
    }

    @discardableResult
    private func keep(_ message: String = decision, because: String = reason, files: [String] = ["Decisions/Retry.md"], at: Date = Date()) throws -> LedgerCommit {
        try tools.ledger.commit(.decision, message, body: "Because: \(because)", files: files, author: "person", at: at)
    }

    private func json(_ line: String?) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: XCTUnwrap(line).data(using: .utf8)!) as! [String: Any]
    }

    private func text(_ line: String?) throws -> String {
        let content = (try json(line)["result"] as? [String: Any])?["content"] as? [[String: Any]]
        return try XCTUnwrap(content?.first?["text"] as? String, line ?? "no reply")
    }

    private func initialize(_ client: String = "openclaw-bundle-mcp") async {
        _ = await server.handle(#"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"\#(client)","version":"1"}}}"#)
    }

    private func call(_ id: Int, _ name: String, _ arguments: String = "{}") async throws -> String {
        try text(await server.handle(#"{"jsonrpc":"2.0","id":\#(id),"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#))
    }

    private func occurrences(of needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }

    // MARK: The initialize era, which got the instructions

    func testTheFirstResultCarriesTheDecisionsOnceEvenAfterInitialize() async throws {
        let kept = try keep()
        await initialize()
        let first = try await call(1, "camr_find", #"{"query":"a week by the sea"}"#)
        XCTAssertTrue(first.hasPrefix(MCPServer.rulesWithResult), first)
        XCTAssertTrue(first.contains(Self.decision + " Because: " + Self.reason), first)
        XCTAssertEqual(occurrences(of: kept.id, in: first), 1, first)
        XCTAssertTrue(first.contains("Lamu"), first)
        // Once per connection: later results don't say them again.
        for id in 2...4 {
            let later = try await call(id, "camr_find", #"{"query":"retry"}"#)
            XCTAssertFalse(later.contains(MCPServer.rulesWithResult), later)
        }
        // The result comes after the decisions, unchanged.
        let plain = MCPServer(tools: tools)
        plain.toolSet = .door
        _ = await plain.handle(#"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"x","version":"1"}}}"#)
        _ = await plain.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"camr_read","arguments":{"path":"Plan B.md"}}}"#)
        let read = try text(await plain.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"camr_read","arguments":{"path":"Plan B.md"}}}"#))
        let fresh = MCPServer(tools: tools)
        fresh.toolSet = .door
        _ = await fresh.handle(#"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"y","version":"1"}}}"#)
        let firstRead = try text(await fresh.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"camr_read","arguments":{"path":"Plan B.md"}}}"#))
        XCTAssertTrue(firstRead.hasSuffix("\n\n" + read), firstRead)
    }

    func testNothingIsAddedWhenNoDecisionIsInForce() async throws {
        await initialize()
        let first = try await call(1, "camr_find", #"{"query":"retry"}"#)
        XCTAssertFalse(first.contains(MCPServer.rulesWithResult), first)
        XCTAssertFalse(first.contains("Earlier sessions kept these decisions"), first)
    }

    func testAReasonIsNeverCut() async throws {
        let long = String(repeating: "The landlord measured both rooms and hers is nearly twice the size. ", count: 16)
        try keep(because: long)
        XCTAssertGreaterThan(long.count, 900)
        await initialize()
        let first = try await call(1, "camr_read", #"{"path":"Plan B.md"}"#)
        XCTAssertTrue(first.contains("Because: " + long.trimmingCharacters(in: .whitespaces)), first)
    }

    // MARK: Not twice in one result

    func testResumeFirstDoesNotRepeatWhatItAlreadyShows() async throws {
        let shown = try keep()
        await initialize()
        let first = try await call(1, "camr_resume")
        // camr_resume's latest commits already carry the decision: it is said once, and nothing is put before it.
        XCTAssertEqual(occurrences(of: shown.id, in: first), 1, first)
        XCTAssertFalse(first.hasPrefix(MCPServer.rulesWithResult), first)
    }

    func testResumeFirstStillGetsADecisionItsLatestCommitsLeftOut() async throws {
        let old = try keep("Matched by account reference only; never guess by phone or amount.", because: "Easter Monday: 31 wrong tickets.",
                           files: ["Home.md"], at: Date().addingTimeInterval(-3_600))
        // Newer commits push the decision out of camr_resume's latest six.
        for number in 1...7 {
            _ = try tools.ledger.commit(.plan, "Look at the shop's file \(number).", files: ["Home.md"], author: "person",
                                        at: Date().addingTimeInterval(Double(number - 10) * 60))
        }
        let resumeAlone = tools.ledger.resume()
        XCTAssertFalse(resumeAlone.contains(old.id), resumeAlone)
        await initialize()
        let first = try await call(1, "camr_resume")
        XCTAssertTrue(first.hasPrefix(MCPServer.rulesWithResult), first)
        XCTAssertEqual(occurrences(of: old.id, in: first), 1, first)
        XCTAssertTrue(first.contains("Because: Easter Monday: 31 wrong tickets."), first)
    }

    func testAShortFindWhoseNotesShowTheDecisionDoesNotRepeatIt() async throws {
        let kept = try keep("We retry a failed charge three times, never more.", because: "The bank blocks a card after the fourth try.")
        let other = try keep(files: ["Home.md"])
        await initialize()
        let first = try await call(1, "camr_find", #"{"query":"retry a failed charge"}"#)
        XCTAssertEqual(occurrences(of: kept.id, in: first), 1, first)
        XCTAssertEqual(occurrences(of: other.id, in: first), 1, first)
    }

    /// Programs cut long results from the end: OpenClaw cut a 20,000-character camr_find to 16,000 in a real run, and
    /// the decision, only in the Ledger notes at its end, never reached the model. So a decision shown only far into the
    /// first result is still put before it.
    func testADecisionShownOnlyAtTheEndOfALongResultIsStillPutFirst() async throws {
        let lines = (1...120).map { "Line \($0): the retry schedule for a failed charge, as finance wrote it down." }
        try lines.joined(separator: "\n").write(to: fixture.vaultFolder.appendingPathComponent("Decisions/Schedule.md"), atomically: true, encoding: .utf8)
        try await tools.vault.refresh(embedder: nil)
        let kept = try keep("We retry a failed charge three times, never more.", because: "The bank blocks a card after the fourth try.",
                            files: ["Decisions/Schedule.md"])
        await initialize()
        let first = try await call(1, "camr_read", #"{"path":"Decisions/Schedule.md"}"#)
        XCTAssertGreaterThan(first.count, MCPServer.shownWithin * 2, first)
        XCTAssertTrue(first.hasPrefix(MCPServer.rulesWithResult), first)
        XCTAssertTrue(String(first.prefix(MCPServer.shownWithin)).contains(kept.id), first)
    }

    // MARK: What the connection kept itself

    func testADecisionKeptFirstIsNotHandedBackButTheOthersAre() async throws {
        let earlier = try keep()
        await initialize()
        let commit = #"{"kind":"decision","message":"Receipts are printed for every sale.","because":"Finance files paper.","files":"Home.md"}"#
        let first = try await call(1, "camr_commit", commit)
        let made = try XCTUnwrap(tools.keptHere.first)
        XCTAssertTrue(first.hasPrefix(MCPServer.rulesWithResult), first)
        XCTAssertTrue(first.contains(earlier.id), first)
        // Confirmed once, by the result itself, not repeated as a decision in force.
        XCTAssertEqual(occurrences(of: made, in: first), 1, first)
        XCTAssertFalse(first.contains("Receipts are printed for every sale. Because"), first)
        let next = try await call(2, "camr_find", #"{"query":"receipts"}"#)
        XCTAssertFalse(next.contains(MCPServer.rulesWithResult), next)
    }

    func testOnlyDecisionKeptFirstMeansNothingIsAdded() async throws {
        await initialize()
        let first = try await call(1, "camr_commit", #"{"kind":"decision","message":"Receipts are printed.","because":"Finance files paper.","files":"Home.md"}"#)
        XCTAssertTrue(first.hasPrefix("Kept as decision"), first)
    }

    // MARK: A call that never gave a result

    func testARefusedCallDoesNotUseUpTheHandover() async throws {
        try keep()
        await initialize()
        let refused = try json(await server.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"camr_read","arguments":{}}}"#))
        XCTAssertNotNil(refused["error"], "\(refused)")
        let first = try await call(2, "camr_find", #"{"query":"a week by the sea"}"#)
        XCTAssertTrue(first.hasPrefix(MCPServer.rulesWithResult), first)
    }

    // MARK: The stateless era

    func testAfterServerDiscoverTheFirstResultStillCarriesThem() async throws {
        try keep()
        _ = await server.handle(DualEraMCPTests.modern(1, "server/discover"))
        let first = try text(await server.handle(DualEraMCPTests.modern(2, "tools/call", #""name":"camr_find","arguments":{"query":"a week by the sea"}"#)))
        XCTAssertTrue(first.hasPrefix(MCPServer.rulesWithResult), first)
        let second = try text(await server.handle(DualEraMCPTests.modern(3, "tools/call", #""name":"camr_find","arguments":{"query":"retry"}"#)))
        XCTAssertFalse(second.contains(MCPServer.rulesWithResult), second)
    }

    // MARK: End to end

    /// The real binary on stdin and stdout, as OpenClaw and Hermes speak to it: initialize, tools/list, then calls.
    func testCAMRMCPOverStdioHandsTheDecisionsWithTheFirstResult() throws {
        let kept = try keep()
        let binary = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("camr")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path), "build camr first: \(binary.path)")
        let process = Process()
        process.executableURL = binary
        process.arguments = ["mcp", fixture.vaultFolder.path]
        var environment = ProcessInfo.processInfo.environment
        environment["CAMR_STATE_DIR"] = fixture.top.appendingPathComponent("state").path
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: watchdog)
        let lines = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"hermes-agent","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"camr_find","arguments":{"query":"a week by the sea"}}}"#,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"camr_find","arguments":{"query":"a week by the sea"}}}"#,
        ]
        input.fileHandleForWriting.write(Data((lines.joined(separator: "\n") + "\n").utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        let replies = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        XCTAssertEqual(replies.count, 4, replies.joined(separator: "\n"))
        let byID = Dictionary(uniqueKeysWithValues: try replies.map { line -> (Int, [String: Any]) in
            let reply = try json(line)
            return (reply["id"] as? Int ?? -1, reply)
        })
        func text(_ id: Int) -> String {
            (((byID[id]?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        }
        let instructions = (byID[1]?["result"] as? [String: Any])?["instructions"] as? String ?? ""
        XCTAssertTrue(instructions.contains(Self.decision + " Because: " + Self.reason), instructions)
        XCTAssertTrue(text(3).hasPrefix(MCPServer.rulesWithResult), text(3))
        XCTAssertTrue(text(3).contains(Self.decision + " Because: " + Self.reason), text(3))
        XCTAssertEqual(occurrences(of: kept.id, in: text(3)), 1, text(3))
        XCTAssertFalse(text(4).contains(MCPServer.rulesWithResult), text(4))
        XCTAssertNil((byID[3]?["result"] as? [String: Any])?["resultType"], "the older era's results stay as they were")
    }
}
