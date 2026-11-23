@testable import CAMRCore
@testable import CAMRMCP
@testable import CAMRTools
import Foundation
import XCTest

/// D-124: Burrow became CAMR. What was set up under the old name keeps working: the burrow_ tool names, the settings
/// folder in Application Support, a vault's `.burrow` folder, and the server, hooks and gate an earlier `burrow connect`
/// wrote, which `camr connect` now replaces instead of adding a second copy beside them.
final class RenameTests: XCTestCase {
    private var top: URL!

    override func setUp() async throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: top, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: top) }

    // MARK: Tool names

    func testOldToolNamesAnswerButAreNotListed() async throws {
        XCTAssertEqual(VaultTools.currentName("burrow_find"), "camr_find")
        XCTAssertEqual(VaultTools.currentName("burrow_resume"), "camr_resume")
        XCTAssertEqual(VaultTools.currentName("vault_search"), "vault_search")
        XCTAssertTrue(VaultTools.callable("burrow_check", in: .door))
        XCTAssertFalse(VaultTools.listed(.full).contains { $0.name.hasPrefix("burrow_") }, "old names are answered, never listed")

        let fixture = try VaultFixture()
        let vault = try await fixture.opened()
        let tools = VaultTools(vault: vault, embedder: nil) { _ in FakeAnswerer() }
        _ = try tools.ledger.commit(.decision, "Rent is split 60/40.", body: "Because: the bigger room.", files: [], author: "person")
        let server = MCPServer(tools: tools, keepsSessions: true)
        server.toolSet = .door
        let reply = await server.handle(DualEraMCPTests.modern(1, "tools/call", #""name":"burrow_resume","arguments":{}"#))
        let result = try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(XCTUnwrap(reply).utf8)) as? [String: Any])?["result"] as? [String: Any], reply ?? "")
        let text = try XCTUnwrap((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(text.contains("Rent is split 60/40."), text)
        XCTAssertNotEqual(result["isError"] as? Bool, true)
    }

    // MARK: The settings folder

    func testTheOldSettingsFolderIsMovedOnceAndLinked() throws {
        let support = top.appendingPathComponent("Application Support")
        let older = support.appendingPathComponent("Burrow")
        try FileManager.default.createDirectory(at: older.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try "/Users/me/Notes\n".write(to: older.appendingPathComponent("last-vault"), atomically: true, encoding: .utf8)

        let folder = CAMRPlaces.settledStateFolder(in: support)
        XCTAssertEqual(folder.lastPathComponent, "CAMR")
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("last-vault"), encoding: .utf8), "/Users/me/Notes\n")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: older.path), folder.path, "the old name points at the new folder")
        XCTAssertEqual(try String(contentsOf: older.appendingPathComponent("last-vault"), encoding: .utf8), "/Users/me/Notes\n", "an older program reads the same file")

        // A second run moves nothing: the link is left as it is.
        XCTAssertEqual(CAMRPlaces.settledStateFolder(in: support).path, folder.path)
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: older.path))
    }

    func testANewMacGetsTheCAMRFolder() {
        XCTAssertEqual(CAMRPlaces.settledStateFolder(in: top).lastPathComponent, "CAMR")
        XCTAssertFalse(FileManager.default.fileExists(atPath: top.appendingPathComponent("Burrow").path))
    }

    // MARK: A vault's hidden folder

    func testAVaultMadeBeforeTheRenameKeepsItsBurrowFolder() throws {
        let notes = top.appendingPathComponent("Notes")
        try FileManager.default.createDirectory(at: notes.appendingPathComponent(".burrow"), withIntermediateDirectories: true)
        try "# Rent\nSplit 60/40.\n".write(to: notes.appendingPathComponent("Rent.md"), atomically: true, encoding: .utf8)

        XCTAssertEqual(CAMRPlaces.store(in: notes).lastPathComponent, ".burrow")
        XCTAssertTrue(Vault.hasIndex(notes))
        let vault = try Vault(project: notes, everything: true)
        XCTAssertEqual(vault.store.lastPathComponent, ".burrow", "read where it is, never moved")
        XCTAssertFalse(FileManager.default.fileExists(atPath: notes.appendingPathComponent(".camr").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: notes.appendingPathComponent(".burrow/index.sqlite").path))

        let fresh = top.appendingPathComponent("Fresh")
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        XCTAssertEqual(try Vault(project: fresh, everything: true).store.lastPathComponent, ".camr")
    }

    func testATeamLedgerInAnOldBurrowFolderIsStillRead() throws {
        let team = Team(name: "Finance", path: top.appendingPathComponent("Finance").path)
        try FileManager.default.createDirectory(at: team.url.appendingPathComponent(".burrow/ledger"), withIntermediateDirectories: true)
        XCTAssertEqual(team.ledgerFolder.path, team.url.appendingPathComponent(".burrow/ledger").path)
    }

    // MARK: What an earlier `burrow connect` wrote

    func testOlderHooksAreRecognised() {
        XCTAssertTrue(Connect.isOlderHook("/Users/me/.local/bin/burrow hook claude /Users/me/Notes"))
        XCTAssertTrue(Connect.isOlderHook("/Users/me/.local/bin/burrow hook claude /Users/me/Notes --gate"))
        XCTAssertTrue(Connect.isOlderHook("BURROW_STATE_DIR='/tmp/s' /opt/burrow hook claude /v"))
        XCTAssertFalse(Connect.isOlderHook("/Users/me/.local/bin/camr hook claude /Users/me/Notes"))
        XCTAssertFalse(Connect.isOlderHook("/usr/bin/burrow-backup --now"))
        XCTAssertFalse(Connect.isOlderHook("say burrow hook"))
    }

    private func setup(_ home: URL) throws -> Connect.Setup {
        let vault = top.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        _ = try Vault(project: vault, everything: true)
        return Connect.Setup(camr: "/opt/camr/bin/camr", vault: Vault.realPath(vault.path), home: home)
    }

    private func write(_ text: String, _ file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func testClaudeCodeSwapsTheOldServerAndHooksForCAMRs() throws {
        let home = top.appendingPathComponent("home")
        let setup = try setup(home)
        let old = "/Users/me/.local/bin/burrow hook claude \(setup.vault)"
        try write(#"{"mcpServers":{"burrow":{"type":"stdio","command":"/Users/me/.local/bin/burrow","args":["mcp","\#(setup.vault)"]},"other":{"command":"x"}}}"#,
                  home.appendingPathComponent(".claude.json"))
        try write(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\#(old) --gate","timeout":30}]},{"hooks":[{"type":"command","command":"afplay done.aiff"}]}],"SessionStart":[{"hooks":[{"type":"command","command":"\#(old)","timeout":10}]}]}}"#,
                  home.appendingPathComponent(".claude/settings.json"))

        try Connect.apply(Connect.plan(.claudeCode, setup), setup)

        let state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: home.appendingPathComponent(".claude.json"))) as? [String: Any])
        let servers = try XCTUnwrap(state["mcpServers"] as? [String: Any])
        XCTAssertNil(servers["burrow"], "the old server is replaced, not kept beside CAMR")
        XCTAssertNotNil(servers["camr"])
        XCTAssertNotNil(servers["other"], "the person's own servers stay")

        let settings = try String(contentsOf: home.appendingPathComponent(".claude/settings.json"), encoding: .utf8)
        XCTAssertFalse(settings.contains("bin/burrow"), settings)
        XCTAssertTrue(settings.contains("afplay done.aiff"), "the person's own hooks stay")
        XCTAssertTrue(settings.contains("/opt/camr/bin/camr hook claude"))
    }

    func testCodexKeepsOneServerUnderTheNewName() throws {
        let home = top.appendingPathComponent("home")
        let setup = try setup(home)
        let codexHome = home.appendingPathComponent(".codex")
        setenv("CODEX_HOME", codexHome.path, 1)
        defer { unsetenv("CODEX_HOME") }
        try write("model = \"o4\"\n\n[mcp_servers.burrow]\ncommand = \"/Users/me/.local/bin/burrow\"\nargs = [\"mcp\", \"/v\"]\n",
                  codexHome.appendingPathComponent("config.toml"))
        try Connect.apply(Connect.plan(.codex, setup), setup)
        let text = try String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertFalse(text.contains("[mcp_servers.burrow]"), text)
        XCTAssertEqual(text.components(separatedBy: "[mcp_servers.camr]").count, 2, "one camr table: \(text)")
        XCTAssertTrue(text.contains("model = \"o4\""))
    }

    func testOpenClawDropsTheOldGateAndServer() throws {
        let home = top.appendingPathComponent("home")
        let setup = try setup(home)
        let oldGate = home.appendingPathComponent(".openclaw/burrow-gate").path
        try write(#"{"mcp":{"servers":{"burrow":{"command":"/x/burrow"}}},"plugins":{"load":{"paths":["\#(oldGate)","/mine/plugin"]},"entries":{"burrow-gate":{"enabled":true},"mine":{"enabled":true}}}}"#,
                  home.appendingPathComponent(".openclaw/openclaw.json"))
        try Connect.apply(Connect.plan(.openClaw, setup), setup)
        let text = try String(contentsOf: home.appendingPathComponent(".openclaw/openclaw.json"), encoding: .utf8)
        XCTAssertFalse(text.contains("burrow"), text)
        XCTAssertTrue(text.contains("/mine/plugin") && text.contains("\"mine\""), "the person's own plugin stays")
        XCTAssertTrue(text.contains("camr-gate"))
    }
}
