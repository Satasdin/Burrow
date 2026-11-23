@testable import CAMRCore
@testable import CAMRTools
import Foundation
import XCTest

/// Bridges as a connected program sees them (D-97): camr_find and camr_read reach the bridged vault, labelled, and
/// its decisions come over only when the bridge was made to share them.
final class BridgeToolsTests: XCTestCase {
    private var top: URL!
    private var home: Vault!
    private var tools: VaultTools!
    /// CAMR's own folder for these tests: where bridges are kept (D-100).
    private var state: URL { top.appendingPathComponent("state") }

    override func setUp() async throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-tools-" + UUID().uuidString)
        for (path, text) in [
            "Home/Rent.md": "# Rent\n\nRent for the Kilimani flat is due on the fifth.\n",
            "Work/Projects/Launch.md": "# Matatu Pay launch\n\nMatatu Pay launches on 2 February 2027. Amina leads QA.\n",
        ] {
            let url = top.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let work = try Vault(project: top.appendingPathComponent("Work"), everything: true)
        work.stateFolder = state
        try await work.refresh()
        _ = try Ledger(vault: work).commit(.decision, "Launch Matatu Pay in February, not December", body: "Because: the pilot needs January.",
                                           files: ["Projects/Launch.md"], author: "person")
        home = try Vault(project: top.appendingPathComponent("Home"), everything: true)
        home.stateFolder = state
        try await home.refresh()
        tools = VaultTools(vault: home, embedder: nil) { _ in FakeAnswerer() }
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: top) }

    func testFindAndReadReachTheBridgedVaultLabelled() async throws {
        try home.addBridge(to: top.appendingPathComponent("Work"))
        let found = try await tools.call("camr_find", arguments: ["query": "When does Matatu Pay launch?"])
        XCTAssertTrue(found.text.contains("file=\"Work › Projects/Launch.md\""), found.text)
        XCTAssertEqual(found.sources.first?.path, "Work › Projects/Launch.md")
        XCTAssertFalse(found.text.contains("Launch Matatu Pay in February"), "notes only: the Ledger stays private")
        for asked in ["Work › Projects/Launch.md", "Work > Projects/Launch.md", "Work/Projects/Launch.md", "Work › Launch"] {
            let read = try await tools.call("camr_read", arguments: ["path": asked])
            XCTAssertFalse(read.isError, "\(asked): \(read.text)")
            XCTAssertTrue(read.text.contains("Amina leads QA"), asked)
        }
        let folders = try await tools.call("vault_folders", arguments: [:])
        XCTAssertTrue(folders.text.contains("bridged vault, read-only"))
        XCTAssertTrue(tools.catalogue().contains("Bridged vaults"))
        let scoped = try await tools.call("camr_find", arguments: ["query": "launch rent", "folder": "Work"])
        XCTAssertFalse(scoped.isError, scoped.text)
        XCTAssertTrue(scoped.sources.allSatisfy { $0.path.hasPrefix("Work › ") })
    }

    func testDecisionsComeOverOnlyWithTheLedger() async throws {
        try home.addBridge(to: top.appendingPathComponent("Work"), withLedger: true)
        let found = try await tools.call("camr_find", arguments: ["query": "When does Matatu Pay launch?"])
        XCTAssertTrue(found.text.contains("<ledger vault=\"Work\">"), found.text)
        XCTAssertTrue(found.text.contains("Work › Ledger "), found.text)
        XCTAssertTrue(found.text.contains("Launch Matatu Pay in February"))
        XCTAssertTrue(found.ledger.isEmpty, "only this vault's own commits count as handed over for its citation check (D-92)")
        XCTAssertTrue(tools.rulesInForce().contains("bridged vault Work"))
        XCTAssertTrue(tools.rulesInForce().contains("Launch Matatu Pay in February"))
        try home.addBridge(to: top.appendingPathComponent("Work"), withLedger: false)
        XCTAssertFalse(tools.rulesInForce().contains("Launch Matatu Pay"))
    }

    // MARK: Only the person on this Mac makes a bridge (D-100)

    /// A bridges file a shared or downloaded vault could carry, pointing at Work and asking for its decisions too.
    private func plantBridgesFile() throws {
        let planted = [Bridge(name: "Work", path: top.appendingPathComponent("Work").path, withLedger: true)]
        try JSONEncoder().encode(planted).write(to: top.appendingPathComponent("Home/.camr/bridges.json"))
    }

    func testAPlantedBridgesFileGivesAConnectedProgramNothing() async throws {
        try plantBridgesFile()
        let found = try await tools.call("camr_find", arguments: ["query": "When does Matatu Pay launch? Who leads QA?"])
        XCTAssertFalse(found.text.contains("Work ›"), found.text)
        XCTAssertFalse(found.text.contains("Amina"), found.text)
        XCTAssertFalse(found.text.contains("Launch Matatu Pay in February"), "the planted --with-ledger hands over no decisions")
        for asked in ["Work › Projects/Launch.md", "Work > Projects/Launch.md", "Work/Projects/Launch.md", "Work › Launch"] {
            let read = try await tools.call("camr_read", arguments: ["path": asked])
            XCTAssertFalse(read.text.contains("Amina"), "\(asked): \(read.text)")
        }
        let scoped = try await tools.call("camr_find", arguments: ["query": "launch", "folder": "Work"])
        XCTAssertFalse(scoped.text.contains("Amina"), scoped.text)
        let folders = try await tools.call("vault_folders", arguments: [:])
        XCTAssertFalse(folders.text.contains("bridged vault"), folders.text)
        XCTAssertFalse(tools.catalogue().contains("Bridged vaults"))
        XCTAssertFalse(tools.rulesInForce().contains("Launch Matatu Pay"))
        // Ask: the local model is shown nothing from Work.
        let answerer = FakeAnswerer()
        let asking = VaultTools(vault: home, embedder: nil) { _ in answerer }
        _ = try await asking.call("vault_ask", arguments: ["question": "When does Matatu Pay launch, and who leads QA?"])
        XCTAssertFalse(answerer.prompts.contains { $0.user.contains("Amina") || $0.system.contains("Amina") }, "\(answerer.prompts)")
        XCTAssertFalse(answerer.prompts.contains { $0.system.contains("Launch Matatu Pay in February") })
    }

    /// The real `camr` binary, with CAMR's own folder set to this test's.
    @discardableResult
    private func camr(_ arguments: [String], input: String? = nil) throws -> (status: Int32, output: String) {
        let binary = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("camr")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path), "build camr first: \(binary.path)")
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["CAMR_STATE_DIR"] = state.path
        process.environment = environment
        let feed = Pipe(), output = Pipe()
        process.standardInput = feed
        process.standardOutput = output
        // An MCP server's log goes to stderr; a command's failure is wanted with its output.
        process.standardError = input == nil ? output : FileHandle.nullDevice
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: watchdog)
        if let input { feed.fileHandleForWriting.write(Data(input.utf8)) }
        try feed.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// `camr mcp` on Home: what camr_find and camr_read hand a connected program.
    private func overMCP() throws -> (find: String, read: String) {
        let lines = [
            DualEraMCPTests.modern(1, "tools/call", #""name":"camr_find","arguments":{"query":"When does Matatu Pay launch? Who leads QA?"}"#),
            DualEraMCPTests.modern(2, "tools/call", #""name":"camr_read","arguments":{"path":"Work › Projects/Launch.md"}"#),
        ]
        let replies = try camr(["mcp", top.appendingPathComponent("Home").path, "--vault"], input: lines.joined(separator: "\n") + "\n").output
        var texts: [Int: String] = [:]
        for line in replies.split(separator: "\n") {
            guard let reply = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let id = reply["id"] as? Int else { continue }
            texts[id] = (((reply["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? "\(reply)"
        }
        return (try XCTUnwrap(texts[1], replies), try XCTUnwrap(texts[2], replies))
    }

    func testTheCommandLineAndMCPServerFollowOnlyBridgesThePersonMade() throws {
        try plantBridgesFile()
        let home = top.appendingPathComponent("Home").path, work = top.appendingPathComponent("Work").path
        var mcp = try overMCP()
        XCTAssertFalse(mcp.find.contains("Work ›"), mcp.find)
        XCTAssertFalse(mcp.find.contains("Amina"), mcp.find)
        XCTAssertFalse(mcp.read.contains("Amina"), mcp.read)
        let find = try camr(["find", home, "When does Matatu Pay launch?", "--vault"])
        XCTAssertFalse(find.output.contains("Work ›"), find.output)
        // bridge list says once that the file is ignored, and lists nothing from it.
        let first = try camr(["bridge", "list", home])
        XCTAssertTrue(first.output.contains("Found bridges written inside this vault folder"), first.output)
        XCTAssertTrue(first.output.contains("has no bridges"), first.output)
        let second = try camr(["bridge", "list", home])
        XCTAssertFalse(second.output.contains("Found bridges"), second.output)
        // A bridge made with the command line works...
        XCTAssertEqual(try camr(["bridge", home, work]).status, 0)
        let listed = try camr(["bridge", "list", home]).output
        XCTAssertTrue(listed.hasPrefix("Work   ") && listed.contains("notes only"), listed)
        mcp = try overMCP()
        XCTAssertTrue(mcp.find.contains("Work › Projects/Launch.md"), mcp.find)
        XCTAssertTrue(mcp.read.contains("Amina leads QA"), mcp.read)
        XCTAssertTrue(try camr(["find", home, "When does Matatu Pay launch?", "--vault"]).output.contains("Work › Projects/Launch.md"))
        // ...and unbridge takes it away.
        XCTAssertEqual(try camr(["unbridge", home, "Work"]).status, 0)
        mcp = try overMCP()
        XCTAssertFalse(mcp.find.contains("Amina"), mcp.find)
        XCTAssertFalse(mcp.read.contains("Amina"), mcp.read)
        // Kept in CAMR's own folder, never in either vault.
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.appendingPathComponent("bridges.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: top.appendingPathComponent("Work/.camr/bridges.json").path))
    }

    func testUnbridgedIsGone() async throws {
        try home.addBridge(to: top.appendingPathComponent("Work"))
        try home.removeBridge("Work")
        let found = try await tools.call("camr_find", arguments: ["query": "When does Matatu Pay launch?"])
        XCTAssertFalse(found.text.contains("Work ›"))
        let read = try await tools.call("camr_read", arguments: ["path": "Work › Projects/Launch.md"])
        XCTAssertTrue(read.isError)
    }
}
