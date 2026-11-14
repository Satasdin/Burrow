@testable import BurrowCore
@testable import BurrowTools
import Foundation
import XCTest

/// Bridges as a connected program sees them (D-97): burrow_find and burrow_read reach the bridged vault, labelled, and
/// its decisions come over only when the bridge was made to share them.
final class BridgeToolsTests: XCTestCase {
    private var top: URL!
    private var home: Vault!
    private var tools: VaultTools!

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
        try await work.refresh()
        _ = try Ledger(vault: work).commit(.decision, "Launch Matatu Pay in February, not December", body: "Because: the pilot needs January.",
                                           files: ["Projects/Launch.md"], author: "person")
        home = try Vault(project: top.appendingPathComponent("Home"), everything: true)
        try await home.refresh()
        tools = VaultTools(vault: home, embedder: nil) { _ in FakeAnswerer() }
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: top) }

    func testFindAndReadReachTheBridgedVaultLabelled() async throws {
        try home.addBridge(to: top.appendingPathComponent("Work"))
        let found = try await tools.call("burrow_find", arguments: ["query": "When does Matatu Pay launch?"])
        XCTAssertTrue(found.text.contains("file=\"Work › Projects/Launch.md\""), found.text)
        XCTAssertEqual(found.sources.first?.path, "Work › Projects/Launch.md")
        XCTAssertFalse(found.text.contains("Launch Matatu Pay in February"), "notes only: the Ledger stays private")
        for asked in ["Work › Projects/Launch.md", "Work > Projects/Launch.md", "Work/Projects/Launch.md", "Work › Launch"] {
            let read = try await tools.call("burrow_read", arguments: ["path": asked])
            XCTAssertFalse(read.isError, "\(asked): \(read.text)")
            XCTAssertTrue(read.text.contains("Amina leads QA"), asked)
        }
        let folders = try await tools.call("vault_folders", arguments: [:])
        XCTAssertTrue(folders.text.contains("bridged vault, read-only"))
        XCTAssertTrue(tools.catalogue().contains("Bridged vaults"))
        let scoped = try await tools.call("burrow_find", arguments: ["query": "launch rent", "folder": "Work"])
        XCTAssertFalse(scoped.isError, scoped.text)
        XCTAssertTrue(scoped.sources.allSatisfy { $0.path.hasPrefix("Work › ") })
    }

    func testDecisionsComeOverOnlyWithTheLedger() async throws {
        try home.addBridge(to: top.appendingPathComponent("Work"), withLedger: true)
        let found = try await tools.call("burrow_find", arguments: ["query": "When does Matatu Pay launch?"])
        XCTAssertTrue(found.text.contains("<ledger vault=\"Work\">"), found.text)
        XCTAssertTrue(found.text.contains("Work › Ledger "), found.text)
        XCTAssertTrue(found.text.contains("Launch Matatu Pay in February"))
        XCTAssertTrue(found.ledger.isEmpty, "only this vault's own commits count as handed over for its citation check (D-92)")
        XCTAssertTrue(tools.rulesInForce().contains("bridged vault Work"))
        XCTAssertTrue(tools.rulesInForce().contains("Launch Matatu Pay in February"))
        try home.addBridge(to: top.appendingPathComponent("Work"), withLedger: false)
        XCTAssertFalse(tools.rulesInForce().contains("Launch Matatu Pay"))
    }

    func testUnbridgedIsGone() async throws {
        try home.addBridge(to: top.appendingPathComponent("Work"))
        try home.removeBridge("Work")
        let found = try await tools.call("burrow_find", arguments: ["query": "When does Matatu Pay launch?"])
        XCTAssertFalse(found.text.contains("Work ›"))
        let read = try await tools.call("burrow_read", arguments: ["path": "Work › Projects/Launch.md"])
        XCTAssertTrue(read.isError)
    }
}
