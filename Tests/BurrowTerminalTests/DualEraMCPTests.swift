@testable import BurrowCore
@testable import BurrowMCP
@testable import BurrowTools
import XCTest

/// Burrow answers both eras of MCP (D-95): the `initialize` handshake as before, byte for byte, and the stateless
/// 2026-07-28 revision, where each request carries its version, capabilities and client in `_meta`.
final class DualEraMCPTests: XCTestCase {
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

    private func keepDecision() throws {
        _ = try tools.ledger.commit(.decision, Self.decision, body: "Because: \(Self.reason)", files: ["Decisions/Retry.md"], author: "person")
    }

    private func json(_ line: String?) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: XCTUnwrap(line).data(using: .utf8)!) as! [String: Any]
    }

    /// A request of the stateless era, as a 2026-07-28 client sends it.
    static func modern(_ id: Int, _ method: String, _ params: String = "", client: String? = "next-client", version: String = "2026-07-28",
                       capabilities: Bool = true) -> String {
        var meta = [#""io.modelcontextprotocol/protocolVersion":"\#(version)""#]
        if capabilities { meta.append(#""io.modelcontextprotocol/clientCapabilities":{}"#) }
        if let client { meta.append(#""io.modelcontextprotocol/clientInfo":{"name":"\#(client)","version":"1"}"#) }
        let rest = params.isEmpty ? "" : params + ","
        return #"{"jsonrpc":"2.0","id":\#(id),"method":"\#(method)","params":{\#(rest)"_meta":{\#(meta.joined(separator: ","))}}}"#
    }

    private func text(_ line: String?) throws -> String {
        let content = (try json(line)["result"] as? [String: Any])?["content"] as? [[String: Any]]
        return try XCTUnwrap(content?.first?["text"] as? String, line ?? "no reply")
    }

    // MARK: The older era, unchanged

    func testTheOldEraLooksExactlyAsItDid() async throws {
        try keepDecision()
        let initialize = try json(await server.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"opencode","version":"1"}}}"#))
        let result = try XCTUnwrap(initialize["result"] as? [String: Any])
        XCTAssertEqual(Set(result.keys), ["protocolVersion", "capabilities", "serverInfo", "instructions"])
        XCTAssertEqual((result["capabilities"] as? [String: Any])?["tools"] as? [String: Bool], ["listChanged": false])
        let instructions = try XCTUnwrap(result["instructions"] as? String)
        XCTAssertEqual(instructions, MCPServer.instructions + tools.rulesInForce() + "\nThis vault holds: " + tools.catalogue() + ".")
        XCTAssertTrue(instructions.contains(Self.reason), instructions)

        let list = try json(await server.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        XCTAssertEqual(Set((list["result"] as! [String: Any]).keys), ["tools"])
        let call = await server.handle(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"burrow_find","arguments":{"query":"retry a failed charge"}}}"#)
        let callResult = try XCTUnwrap(try json(call)["result"] as? [String: Any])
        XCTAssertEqual(Set(callResult.keys), ["content", "isError"])
        // The rules came with initialize, so a tool result in this era never repeats them.
        XCTAssertFalse(try text(call).contains(MCPServer.rulesWithResult))
        XCTAssertFalse(call!.contains("resultType"), call!)
    }

    func testTheOldEraStillWantsInitializeAndDoesNotKnowDiscover() async throws {
        let list = try json(await server.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        XCTAssertEqual((list["error"] as? [String: Any])?["code"] as? Int, MCPServer.Code.notInitialized)
        // server/discover without the stateless `_meta` is a request of the older era, where it never existed.
        let discover = try json(await server.handle(#"{"jsonrpc":"2.0","id":3,"method":"server/discover"}"#))
        XCTAssertEqual((discover["error"] as? [String: Any])?["code"] as? Int, MCPServer.Code.methodNotFound)
        // `_meta` without a protocol version (a progress token, say) leaves a request in the older era.
        let tagged = try json(await server.handle(#"{"jsonrpc":"2.0","id":4,"method":"tools/list","params":{"_meta":{"progressToken":7}}}"#))
        XCTAssertEqual((tagged["error"] as? [String: Any])?["code"] as? Int, MCPServer.Code.notInitialized)
    }

    // MARK: The stateless era

    func testDiscoverNamesTheServerItsVersionsAndTheRulesInForce() async throws {
        try keepDecision()
        let reply = try json(await server.handle(Self.modern(1, "server/discover")))
        let result = try XCTUnwrap(reply["result"] as? [String: Any], "\(reply)")
        XCTAssertEqual(result["resultType"] as? String, "complete")
        XCTAssertEqual(result["supportedVersions"] as? [String], ["2026-07-28"])
        XCTAssertNotNil((result["capabilities"] as? [String: Any])?["tools"])
        let info = ((result["_meta"] as? [String: Any])?["io.modelcontextprotocol/serverInfo"]) as? [String: String]
        XCTAssertEqual(info, ["name": "burrow", "version": BurrowVersion.number])
        XCTAssertEqual(result["ttlMs"] as? Int, 0)
        XCTAssertEqual(result["cacheScope"] as? String, "private")
        let instructions = try XCTUnwrap(result["instructions"] as? String)
        XCTAssertTrue(instructions.hasPrefix(MCPServer.instructions), instructions)
        XCTAssertTrue(instructions.contains(Self.decision + " Because: " + Self.reason), instructions)
        XCTAssertTrue(instructions.contains("This vault holds: "), instructions)
        // Told at discover, so the first tool result does not say them again.
        let found = try text(await server.handle(Self.modern(2, "tools/call", #""name":"burrow_find","arguments":{"query":"retry a failed charge"}"#)))
        XCTAssertFalse(found.contains(MCPServer.rulesWithResult), found)
    }

    func testToolsAnswerWithoutInitializeAndSayTheyAreComplete() async throws {
        let list = try json(await server.handle(Self.modern(1, "tools/list")))
        let listed = try XCTUnwrap(list["result"] as? [String: Any], "\(list)")
        XCTAssertEqual(listed["resultType"] as? String, "complete")
        XCTAssertEqual((listed["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }.sorted(),
                       ["burrow_check", "burrow_commit", "burrow_find", "burrow_read", "burrow_resume"])
        XCTAssertNotNil((listed["_meta"] as? [String: Any])?["io.modelcontextprotocol/serverInfo"])
        XCTAssertNotNil(listed["ttlMs"])
        let call = try json(await server.handle(Self.modern(2, "tools/call", #""name":"burrow_find","arguments":{"query":"retry a failed charge"}"#)))
        let result = try XCTUnwrap(call["result"] as? [String: Any], "\(call)")
        XCTAssertEqual(result["resultType"] as? String, "complete")
        XCTAssertEqual(result["isError"] as? Bool, false)
        XCTAssertTrue(((result["content"] as? [[String: Any]])?.first?["text"] as? String ?? "").contains("Retry"))
        // No decisions are kept, so there is nothing to hand over with the result.
        XCTAssertFalse(((result["content"] as? [[String: Any]])?.first?["text"] as? String ?? "").contains(MCPServer.rulesWithResult))
    }

    func testAVersionItDoesNotSpeakIsRefusedWithTheOnesItDoes() async throws {
        let reply = try json(await server.handle(Self.modern(1, "tools/list", version: "2030-01-01")))
        let error = try XCTUnwrap(reply["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? Int, -32022)
        XCTAssertEqual((error["data"] as? [String: Any])?["supported"] as? [String], ["2026-07-28"])
        XCTAssertEqual((error["data"] as? [String: Any])?["requested"] as? String, "2030-01-01")
        let bare = try json(await server.handle(Self.modern(2, "tools/list", capabilities: false)))
        XCTAssertEqual((bare["error"] as? [String: Any])?["code"] as? Int, MCPServer.Code.invalidParams)
        let ping = try json(await server.handle(Self.modern(3, "ping")))
        XCTAssertEqual((ping["error"] as? [String: Any])?["code"] as? Int, MCPServer.Code.methodNotFound)
    }

    func testTheFirstToolResultCarriesTheRulesOnceForEachProgram() async throws {
        try keepDecision()
        let first = try text(await server.handle(Self.modern(1, "tools/call", #""name":"burrow_find","arguments":{"query":"retry a failed charge"}"#)))
        XCTAssertTrue(first.hasPrefix(MCPServer.rulesWithResult), first)
        XCTAssertTrue(first.contains(Self.decision + " Because: " + Self.reason), first)
        XCTAssertTrue(first.contains("Retry"), first)
        let second = try text(await server.handle(Self.modern(2, "tools/call", #""name":"burrow_find","arguments":{"query":"retry a failed charge"}"#)))
        XCTAssertFalse(second.contains(MCPServer.rulesWithResult), second)
        // Another program on the same process has not had them.
        let other = try text(await server.handle(Self.modern(3, "tools/call", #""name":"burrow_resume","arguments":{}"#, client: "another")))
        XCTAssertTrue(other.hasPrefix(MCPServer.rulesWithResult), other)
    }

    func testEachRequestsClientSignsWhatItKeeps() async throws {
        let commit = #""name":"burrow_commit","arguments":{"kind":"decision","message":"Receipts are printed.","because":"Finance files paper.","files":"Home.md","model":"claude-code"}"#
        _ = try text(await server.handle(Self.modern(1, "tools/call", commit, client: "codex-next")))
        let kept = try XCTUnwrap(tools.ledger.log().first)
        XCTAssertEqual(kept.client, "codex-next")
        XCTAssertEqual(kept.author, "codex-next")
        // The conversation this connection keeps is named for that program (D-86).
        XCTAssertEqual(tools.connection?.client, "codex-next")
        let fact = #""name":"burrow_commit","arguments":{"kind":"fact","message":"Cash-up is at 21:00."}"#
        _ = try text(await server.handle(Self.modern(2, "tools/call", fact, client: "zed-agent")))
        XCTAssertEqual(tools.ledger.log().first { $0.message == "Cash-up is at 21:00." }?.client, "zed-agent")
    }

    func testBothErasOnOneProcess() async throws {
        try keepDecision()
        _ = await server.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"opencode","version":"1"}}}"#)
        let old = await server.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"burrow_resume","arguments":{}}}"#)
        XCTAssertFalse(old!.contains("resultType"))
        let new = await server.handle(Self.modern(3, "tools/call", #""name":"burrow_resume","arguments":{}"#))
        XCTAssertTrue(try text(new).hasPrefix(MCPServer.rulesWithResult))
        XCTAssertEqual((try json(new)["result"] as? [String: Any])?["resultType"] as? String, "complete")
    }

    // MARK: End to end

    /// The real binary on stdin and stdout, sent new-era lines only, as a 2026-07-28 client that never asks
    /// server/discover: the decisions in force arrive with its first tool result.
    func testBurrowMCPOverStdioHandsTheDecisionsToANewEraClient() throws {
        try keepDecision()
        let binary = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("burrow")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path), "build burrow first: \(binary.path)")
        let process = Process()
        process.executableURL = binary
        process.arguments = ["mcp", fixture.vaultFolder.path]
        var environment = ProcessInfo.processInfo.environment
        environment["BURROW_STATE_DIR"] = fixture.top.appendingPathComponent("state").path
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: watchdog)
        let lines = [
            Self.modern(1, "tools/list"),
            Self.modern(2, "tools/call", #""name":"burrow_find","arguments":{"query":"rent split"}"#),
            Self.modern(3, "tools/call", #""name":"burrow_find","arguments":{"query":"rent split"}"#),
            Self.modern(4, "server/discover", client: "probe"),
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
        for id in 1...4 { XCTAssertEqual((byID[id]?["result"] as? [String: Any])?["resultType"] as? String, "complete", "\(byID[id] ?? [:])") }
        func text(_ id: Int) -> String {
            (((byID[id]?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        }
        XCTAssertTrue(text(2).hasPrefix(MCPServer.rulesWithResult), text(2))
        XCTAssertTrue(text(2).contains(Self.decision + " Because: " + Self.reason), text(2))
        XCTAssertFalse(text(3).contains(MCPServer.rulesWithResult), text(3))
        let instructions = (byID[4]?["result"] as? [String: Any])?["instructions"] as? String ?? ""
        XCTAssertTrue(instructions.contains(Self.decision + " Because: " + Self.reason), instructions)
    }
}
