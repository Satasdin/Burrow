@testable import CAMRCore
@testable import CAMRTools
import Foundation
import XCTest

/// D-108: `camr connect <program> <vault>` works out each program's setup (CAMR as an MCP server, its tools always in
/// view, the gate plugin), shows every change to an existing setting before writing, writes only in the person's own
/// terminal after a typed yes, and installs gate plugins that hold a change resting on a decision once, then let it pass.
final class ConnectTests: XCTestCase {
    private var top: URL!
    private var home: URL { top.appendingPathComponent("home") }
    private var vaultFolder: URL { top.appendingPathComponent("vault") }
    private var state: URL { top.appendingPathComponent("state") }
    private var code: URL { top.appendingPathComponent("shop") }
    private let camrPath = "/opt/camr/bin/camr"

    override func setUp() async throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("connect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try "# Home\n".write(to: vaultFolder.appendingPathComponent("Home.md"), atomically: true, encoding: .utf8)
        // A vault, as `camr vault new` leaves it: connect refuses any other folder (D-114).
        _ = try Vault(project: vaultFolder, everything: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: top) }

    private func setup(stateDir: String? = nil) -> Connect.Setup {
        Connect.Setup(camr: camrPath, vault: Vault.realPath(vaultFolder.path), home: home, stateDir: stateDir)
    }

    private func write(_ text: String, _ path: String) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func read(_ path: String) -> String? { try? String(contentsOf: home.appendingPathComponent(path), encoding: .utf8) }

    private func json(_ path: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(read(path)).utf8)) as? [String: Any])
    }

    private func value(_ root: [String: Any], _ path: String) -> Any? {
        var current: Any? = root
        for key in path.split(separator: ".") { current = (current as? [String: Any])?[String(key)] }
        return current
    }

    // MARK: the plugins are the repository's own files

    func testTheGatePluginsInstalledAreTheFilesInIntegrations() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        XCTAssertEqual(ConnectPlugins.sources.count, 6)
        for source in ConnectPlugins.sources {
            let file = try String(contentsOf: root.appendingPathComponent(source.path), encoding: .utf8)
            XCTAssertEqual(source.text, file, "\(source.path) differs from what camr connect installs: run scripts/embed-integrations.py")
        }
    }

    // MARK: what each program gets

    func testOpenCodeGetsTheServerWithCodeModeOffAndTheGatePlugin() throws {
        let plan = Connect.plan(.openCode, setup(stateDir: state.path))
        XCTAssertNil(plan.refusal)
        try Connect.apply(plan, setup(stateDir: state.path))
        let settings = try json(".config/opencode/opencode.json")
        XCTAssertEqual(value(settings, "mcp.camr.command") as? [String], [camrPath, "mcp", Vault.realPath(vaultFolder.path)])
        XCTAssertEqual(value(settings, "mcp.camr.codemode") as? Bool, false, "CAMR's tools listed directly, not behind execute")
        XCTAssertEqual(value(settings, "mcp.camr.environment.CAMR_STATE_DIR") as? String, state.path)
        XCTAssertEqual(read(".config/opencode/plugins/camr-gate/index.js"), ConnectPlugins.openCode)
        let gate = try json(".config/opencode/plugins/camr-gate/camr-gate.json")
        XCTAssertEqual(gate["vault"] as? String, Vault.realPath(vaultFolder.path))
        XCTAssertEqual(gate["stateDir"] as? String, state.path)
        XCTAssertTrue(Connect.plan(.openCode, setup(stateDir: state.path)).pending.isEmpty, "a second run changes nothing")
    }

    func testOpenCodeTwoShapeKeepsServersWhereTheyAre() throws {
        try write(#"{"mcp": {"servers": {"web": {"type": "remote", "url": "https://example.com/mcp"}}}}"#, ".config/opencode/opencode.json")
        try Connect.apply(Connect.plan(.openCode, setup()), setup())
        let settings = try json(".config/opencode/opencode.json")
        XCTAssertNotNil(value(settings, "mcp.servers.web"))
        XCTAssertEqual(value(settings, "mcp.servers.camr.codemode") as? Bool, false)
        XCTAssertNil(value(settings, "mcp.camr"))
    }

    func testOpenClawMergeKeepsWhatIsThereAndShowsEveryChange() throws {
        try write("""
        {"models": {"providers": {"ollama": {"baseUrl": "http://127.0.0.1:11434", "api": "ollama"}}},
         "tools": {"toolSearch": true, "profile": "coding"},
         "plugins": {"load": {"paths": ["/elsewhere/other-plugin"]}}}
        """, ".openclaw/openclaw.json")
        let plan = Connect.plan(.openClaw, setup())
        let settings = try XCTUnwrap(plan.changes.first)
        XCTAssertTrue(settings.shown.contains("~ tools.toolSearch: true → false"), settings.shown.joined(separator: "\n"))
        XCTAssertTrue(settings.shown.contains { $0.hasPrefix("+ mcp = ") || $0.hasPrefix("+ mcp.servers") }, settings.shown.joined(separator: "\n"))
        XCTAssertTrue(settings.shown.contains { $0.hasPrefix("~ plugins.load.paths:") }, settings.shown.joined(separator: "\n"))
        XCTAssertFalse(settings.shown.contains { $0.contains("models") || $0.contains("profile") }, "untouched settings are not listed")
        let described = Connect.describe(plan, setup())
        XCTAssertTrue(described.contains("~/.openclaw/openclaw.json: these settings change"), described)

        try Connect.apply(plan, setup())
        let after = try json(".openclaw/openclaw.json")
        XCTAssertEqual(value(after, "models.providers.ollama.baseUrl") as? String, "http://127.0.0.1:11434")
        XCTAssertEqual(value(after, "tools.profile") as? String, "coding")
        XCTAssertEqual(value(after, "tools.toolSearch") as? Bool, false)
        XCTAssertEqual(value(after, "mcp.servers.camr.args") as? [String], ["mcp", Vault.realPath(vaultFolder.path)])
        XCTAssertEqual(value(after, "plugins.load.paths") as? [String], ["/elsewhere/other-plugin", home.appendingPathComponent(".openclaw/camr-gate").path])
        XCTAssertEqual(value(after, "plugins.entries.camr-gate.enabled") as? Bool, true)
        XCTAssertEqual(value(after, "plugins.entries.camr-gate.config.vault") as? String, Vault.realPath(vaultFolder.path))
        XCTAssertNotNil(read(".openclaw/openclaw.json.before-camr"), "the old file is kept")
        XCTAssertEqual(read(".openclaw/camr-gate/index.mjs"), ConnectPlugins.openClaw)
        XCTAssertEqual(read(".openclaw/camr-gate/openclaw.plugin.json"), ConnectPlugins.openClawManifest)
        XCTAssertTrue(Connect.plan(.openClaw, setup()).pending.isEmpty)
    }

    func testHermesSettingsAreAddedLineByLineAndEveryOtherLineIsKept() throws {
        let base = """
        # my Hermes
        model:
          default: "gemma4:12b"   # local
          base_url: "http://127.0.0.1:11434/v1"
        tools:
          connectors: false

        plugins:
          enabled: [notes-sync]
        """
        try write(base + "\n", ".hermes/config.yaml")
        let plan = Connect.plan(.hermes, setup(stateDir: state.path))
        XCTAssertNil(plan.refusal)
        try Connect.apply(plan, setup(stateDir: state.path))
        let after = try XCTUnwrap(read(".hermes/config.yaml"))
        let lines = after.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Every line the person wrote is still there, in order (the plugins list grew by one item).
        var at = 0
        for line in base.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) where line != "  enabled: [notes-sync]" {
            guard let found = lines[at...].firstIndex(of: line) else { return XCTFail("lost \(line)\n\(after)") }
            at = found + 1
        }
        XCTAssertTrue(after.contains("tools:\n  connectors: false\n  tool_search:\n    enabled: \"off\"\n"), after)
        XCTAssertTrue(after.contains("  enabled: [notes-sync, camr-gate]"), after)
        XCTAssertTrue(after.contains("mcp_servers:\n  camr:\n    command: \"\(camrPath)\"\n"), after)
        XCTAssertTrue(after.contains("      CAMR_STATE_DIR: \"\(state.path)\""), after)
        XCTAssertEqual(read(".hermes/plugins/camr-gate/__init__.py"), ConnectPlugins.hermes)
        XCTAssertEqual(read(".hermes/plugins/camr-gate/plugin.yaml"), ConnectPlugins.hermesManifest)
        XCTAssertTrue(Connect.plan(.hermes, setup(stateDir: state.path)).pending.isEmpty, "a second run changes nothing")
    }

    func testHermesBlockListGetsTheItemAppended() throws {
        try write("plugins:\n  enabled:\n    - notes-sync\n  disabled: []\n", ".hermes/config.yaml")
        try Connect.apply(Connect.plan(.hermes, setup()), setup())
        XCTAssertTrue(read(".hermes/config.yaml")!.hasPrefix("plugins:\n  enabled:\n    - notes-sync\n    - camr-gate\n  disabled: []\n"), read(".hermes/config.yaml")!)
    }

    func testHermesSettingAlreadySetOtherwiseIsRefusedNotOverwritten() throws {
        for base in ["tools:\n  tool_search:\n    enabled: \"auto\"\n", "tools: {connectors: false}\n", "mcp_servers:\n  camr:\n    command: \"/old/camr\"\n"] {
            try write(base, ".hermes/config.yaml")
            let plan = Connect.plan(.hermes, setup())
            XCTAssertNotNil(plan.refusal, base)
            XCTAssertTrue(plan.changes.isEmpty)
            XCTAssertThrowsError(try Connect.apply(plan, setup()))
            XCTAssertEqual(read(".hermes/config.yaml"), base, "left alone")
        }
        try write("tools:\n  tool_search:\n    enabled: off\n", ".hermes/config.yaml")
        XCTAssertNil(Connect.plan(.hermes, setup()).refusal, "off without quotes is the same setting")
    }

    func testASettingsFileWithCommentsIsNeverRewritten() throws {
        let text = "{\n  // my servers\n  \"mcp\": {}\n}\n"
        try write(text, ".config/opencode/opencode.json")
        let plan = Connect.plan(.openCode, setup())
        XCTAssertNotNil(plan.refusal)
        XCTAssertThrowsError(try Connect.apply(plan, setup()))
        XCTAssertEqual(read(".config/opencode/opencode.json"), text)
        XCTAssertNil(read(".config/opencode/plugins/camr-gate/index.js"), "nothing written when the settings can't be")
    }

    func testClaudeCodeGetsAlwaysLoadAndTheHooksOnceBesideOtherHooks() throws {
        try write(#"{"numStartups": 41, "mcpServers": {"github": {"type": "http", "url": "https://example.com"}}}"#, ".claude.json")
        try write(#"{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]}, "theme": "dark"}"#, ".claude/settings.json")
        try Connect.apply(Connect.plan(.claudeCode, setup()), setup())
        let state = try json(".claude.json")
        XCTAssertEqual(state["numStartups"] as? Int, 41)
        XCTAssertNotNil(value(state, "mcpServers.github"))
        XCTAssertEqual(value(state, "mcpServers.camr.alwaysLoad") as? Bool, true)
        let settings = try json(".claude/settings.json")
        XCTAssertEqual(settings["theme"] as? String, "dark")
        let stop = try XCTUnwrap(value(settings, "hooks.Stop") as? [[String: Any]])
        let commands = stop.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands.first, "say done")
        XCTAssertTrue(commands.last!.hasSuffix(" --gate"), commands.last!)
        XCTAssertTrue(Connect.plan(.claudeCode, setup()).pending.isEmpty, "hooks are not added twice")
    }

    func testN8nIsPrintedNeverWritten() {
        let plan = Connect.plan(.n8n, setup())
        XCTAssertTrue(plan.changes.isEmpty)
        XCTAssertTrue(plan.manual!.contains("Endpoint: http://127.0.0.1:8790/mcp"))
        XCTAssertTrue(plan.manual!.contains("check '\(Vault.realPath(vaultFolder.path))' --json") || plan.manual!.contains("check \(Vault.realPath(vaultFolder.path)) --json"))
    }

    /// A vault path holding `"`, `$(…)` and a backtick stays one path in every printed command: the n8n line pasted
    /// into a shell gives `--stdio` one argument, and that argument run by a shell (as supergateway runs it) gives the
    /// binary, `mcp` and the exact path, and nothing runs. Found by a security review of the first version, which wrapped
    /// the shell-quoted parts in double quotes.
    func testPrintedCommandsKeepAHostilePathAsOneArgument() throws {
        let hostile = top.appendingPathComponent("a\"$(touch PWNED)\"b`touch PWNED2`")
        try FileManager.default.createDirectory(at: hostile, withIntermediateDirectories: true)
        let sandbox = top.appendingPathComponent("sandbox")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        let setup = Connect.Setup(camr: camrPath, vault: Vault.realPath(hostile.path), home: home, stateDir: state.path + "/$(touch PWNED3)")
        let manual = try XCTUnwrap(Connect.plan(.n8n, setup).manual)
        let line = try XCTUnwrap(manual.split(separator: "\n").first { $0.contains("supergateway@") })
            .trimmingCharacters(in: .whitespaces)
        func sh(_ script: String) throws -> [String] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]
            process.currentDirectoryURL = sandbox
            let out = Pipe()
            process.standardOutput = out
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).dropLast().map(String.init)
        }
        // The pasted line, with npx replaced by something that prints each argument and the variable it was given.
        let pasted = line.replacingOccurrences(of: "npx -y supergateway@4.2.2", with: "sh -c 'printf \"%s\\n\" \"$CAMR_STATE_DIR\" \"$@\"' sh")
        let arguments = try sh(pasted)
        XCTAssertEqual(arguments.first, state.path + "/$(touch PWNED3)", line)
        let stdio = try XCTUnwrap(arguments.firstIndex(of: "--stdio"), "\(arguments)")
        // supergateway hands that one argument to a shell.
        let words = try sh("set -- " + arguments[stdio + 1] + "; for a in \"$@\"; do printf '%s\\n' \"$a\"; done")
        XCTAssertEqual(words, [camrPath, "mcp", Vault.realPath(hostile.path)])
        let check = try XCTUnwrap(manual.split(separator: "\n").first { $0.contains(" check ") })
        let checkLine = String(check.split(separator: ":", maxSplits: 1)[1]).trimmingCharacters(in: .whitespaces)
        XCTAssertEqual(try sh("set -- " + checkLine + "; for a in \"$@\"; do printf '%s\\n' \"$a\"; done"),
                       [camrPath, "check", Vault.realPath(hostile.path), "--json"])
        // Claude Code runs its hook commands with a shell too.
        let plan = Connect.plan(.claudeCode, setup)
        let hooks = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(plan.changes[1].after.utf8)) as? [String: Any])
        let stop = try XCTUnwrap(((value(hooks, "hooks.Stop") as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String)
        let printer = "sh -c 'printf \"%s\\n\" \"$CAMR_STATE_DIR\" \"$@\"' sh"
        XCTAssertEqual(try sh(stop.replacingOccurrences(of: camrPath, with: printer)),
                       [state.path + "/$(touch PWNED3)", "hook", "claude", Vault.realPath(hostile.path), "--gate"], stop)
        let created = try FileManager.default.contentsOfDirectory(atPath: sandbox.path) + FileManager.default.contentsOfDirectory(atPath: top.path)
        XCTAssertFalse(created.contains { $0.hasPrefix("PWNED") }, "nothing ran: \(created)")
    }

    func testAPathWithControlCharactersIsRefusedNotCleaned() throws {
        for setup in [Connect.Setup(camr: camrPath, vault: "/tmp/Notes\u{1b}]0;x\u{07}", home: home),
                      Connect.Setup(camr: camrPath, vault: "/tmp/Notes\u{202e}txt", home: home),
                      Connect.Setup(camr: camrPath, vault: "/tmp/Notes", home: home, stateDir: "/tmp/state\nrm -rf ~")] {
            for program in Connect.Program.allCases {
                let plan = Connect.plan(program, setup)
                XCTAssertNotNil(plan.refusal, "\(program) \(setup.vault)")
                XCTAssertNil(plan.manual)
                XCTAssertTrue(plan.changes.isEmpty)
                XCTAssertFalse(Connect.describe(plan, setup).unicodeScalars.contains { Printable.hasControl(String($0)) && $0 != "\n" })
            }
        }
        let folder = top.appendingPathComponent("Notes\u{202e}txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let refused = try CAMRBinary.piped(["connect", "n8n", folder.path, "--home", home.path], state: state)
        XCTAssertEqual(refused.status, 1)
        XCTAssertTrue(refused.err.contains("control or invisible characters"), refused.err)
    }

    // MARK: the command

    func testTheCommandPrintsAndOnlyThePersonWrites() throws {
        let vault = vaultFolder.path
        let printed = try CAMRBinary.piped(["connect", "opencode", vault, "--home", home.path], state: state)
        XCTAssertEqual(printed.status, 0, printed.err)
        XCTAssertTrue(printed.out.contains("\"codemode\" : false"), printed.out)
        XCTAssertTrue(printed.out.contains("Nothing was written"), printed.out)
        XCTAssertNil(read(".config/opencode/opencode.json"))

        let piped = try CAMRBinary.piped(["connect", "opencode", vault, "--home", home.path, "--write"], state: state, input: "yes\n")
        XCTAssertEqual(piped.status, 1)
        XCTAssertTrue(piped.err.contains("only you can change a program's settings"), piped.err)
        XCTAssertNil(read(".config/opencode/opencode.json"), "a piped yes writes nothing")

        try write(#"{"model": "ollama/gemma4:12b"}"#, ".config/opencode/opencode.json")
        let declined = try CAMRBinary.inTerminal(["connect", "opencode", vault, "--home", home.path, "--write"], state: state, answer: "y")
        XCTAssertEqual(declined.status, 1, declined.out)
        XCTAssertTrue(declined.out.contains("+ mcp = ") || declined.out.contains("+ mcp."), "the change is shown before the question: \(declined.out)")
        XCTAssertEqual(read(".config/opencode/opencode.json"), #"{"model": "ollama/gemma4:12b"}"#)

        let accepted = try CAMRBinary.inTerminal(["connect", "opencode", vault, "--home", home.path, "--write"], state: state, answer: "yes")
        XCTAssertEqual(accepted.status, 0, accepted.out)
        XCTAssertEqual(try json(".config/opencode/opencode.json")["model"] as? String, "ollama/gemma4:12b")
        XCTAssertEqual(read(".config/opencode/opencode.json.before-camr"), #"{"model": "ollama/gemma4:12b"}"#)
        XCTAssertEqual(read(".config/opencode/plugins/camr-gate/index.js"), ConnectPlugins.openCode)
        let gate = try json(".config/opencode/plugins/camr-gate/camr-gate.json")
        XCTAssertEqual(gate["camr"] as? String, Vault.realPath(CAMRBinary.url.path), "the binary that wrote it, resolved")
        XCTAssertEqual(gate["stateDir"] as? String, state.path, "CAMR_STATE_DIR is carried")

        let again = try CAMRBinary.piped(["connect", "opencode", vault, "--home", home.path, "--write"], state: state)
        XCTAssertEqual(again.status, 0, again.err)
        XCTAssertTrue(again.out.contains("Already set up; nothing to write."), again.out)

        // A later change keeps the copy from before CAMR, not the one before this run.
        let other = try XCTUnwrap(read(".config/opencode/opencode.json")).replacingOccurrences(of: "\"codemode\" : false", with: "\"codemode\" : true")
        try write(other, ".config/opencode/opencode.json")
        let rerun = try CAMRBinary.inTerminal(["connect", "opencode", vault, "--home", home.path, "--write"], state: state, answer: "yes")
        XCTAssertEqual(rerun.status, 0, rerun.out)
        XCTAssertTrue(rerun.out.contains("~ mcp.camr.codemode: true → false"), rerun.out)
        XCTAssertEqual(read(".config/opencode/opencode.json.before-camr"), #"{"model": "ollama/gemma4:12b"}"#)
        // ...and, every write, a dated copy of the file exactly as it was just before (D-115), named in what is said.
        let folder = home.appendingPathComponent(".config/opencode")
        let dated = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("opencode.json.before-camr-") }.sorted()
        XCTAssertEqual(dated.count, 2, "one per write: \(dated)")
        XCTAssertEqual(read(".config/opencode/" + dated.last!), other, "the newest copy is the file as it was before this write")
        XCTAssertTrue(rerun.out.contains("as it was in ~/.config/opencode/opencode.json.before-camr-"), rerun.out)

        let unknown = try CAMRBinary.piped(["connect", "cursor", vault], state: state)
        XCTAssertEqual(unknown.status, 1)
        XCTAssertTrue(unknown.err.contains("Programs: claude-code, codex, opencode, openclaw, hermes, n8n"), unknown.err)
    }

    /// Without --home, the home is $HOME, the one the programs read (Node's os.homedir, Python's ~, OpenCode), not the
    /// account's home NSHomeDirectory() gives: a sandboxed HOME must never send settings to the person's real folder.
    func testWithoutHomeTheSettingsGoUnderHOME() throws {
        // Run as the person runs it (D-113): the shared helper takes out agent variables and detaches from this tree.
        let ran = try CAMRBinary.inTerminal(["connect", "hermes", vaultFolder.path, "--write"], state: state, answer: "yes",
                                              environment: ["HOME": home.path, "HERMES_HOME": "", "XDG_CONFIG_HOME": ""])
        let said = ran.out
        XCTAssertEqual(ran.status, 0, said)
        XCTAssertTrue(said.contains("~/.hermes/config.yaml"), said)
        XCTAssertNotNil(read(".hermes/plugins/camr-gate/__init__.py"), said)
        XCTAssertTrue(read(".hermes/config.yaml")?.contains("camr-gate") == true)
    }

    // MARK: the gates themselves, run by the program's own language against the real camr binary

    /// A vault whose linked repository has a decision on reconcile.py, matcher.py one import away, and an approval in this
    /// test's own state folder.
    private func gateFixture() async throws {
        for (path, text) in [
            "shop/payments/__init__.py": "",
            "shop/payments/matcher.py": "def ticket_for_line(store, line):\n    return store.tickets.get(line.account_ref)\n",
            "shop/payments/reconcile.py": "from .matcher import ticket_for_line\n\n\ndef reconcile(store, lines):\n    return [ticket_for_line(store, line) for line in lines]\n",
        ] {
            let url = top.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        for arguments in [["init", "-q"], ["add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qm", "start"]] {
            _ = VaultTools.git(code, arguments)
        }
        let vault = try Vault(project: vaultFolder, everything: true)
        vault.stateFolder = state
        try vault.linkFolder(code)
        try await vault.refresh(embedder: nil)
        try Ledger(vault: vault).commit(.decision, "A statement line is matched by its account reference only.",
                                        body: "Rejected: Matching on phone and amount.\nBecause: Conductors pay for whole groups from one phone (Easter Monday, 31 wrong tickets).",
                                        files: ["shop/payments/reconcile.py"], author: "claude-opus-5-5", client: "claude-code")
    }

    private func editMatcher(_ marker: String) throws {
        let matcher = code.appendingPathComponent("payments/matcher.py")
        try (String(contentsOf: matcher, encoding: .utf8) + "# \(marker)\n").write(to: matcher, atomically: true, encoding: .utf8)
    }

    private func installed(_ program: Connect.Program) throws -> Connect.Setup {
        let setup = Connect.Setup(camr: Vault.realPath(CAMRBinary.url.path), vault: Vault.realPath(vaultFolder.path), home: home, stateDir: state.path)
        try Connect.apply(Connect.plan(program, setup), setup)
        return setup
    }

    private func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, out: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "CAMR_STATE_DIR")  // the plugin must carry it from its own settings
        process.environment = environment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// A string as a JSON (and JavaScript, and Python) literal.
    private func quoted(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text], options: [.withoutEscapingSlashes])) ?? Data()
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    private func available(_ tool: String) -> Bool { (try? run(tool, ["--version"]).status) == 0 }

    func testTheOpenCodeGateHoldsAChangeOnceAndAgainWhenItChanges() async throws {
        try XCTSkipUnless(available("node"), "node is not installed")
        try await gateFixture()
        _ = try installed(.openCode)
        let plugin = home.appendingPathComponent(".config/opencode/plugins/camr-gate/index.js")
        let script = top.appendingPathComponent("drive.mjs")
        try """
        const plugin = (await import(\(quoted(plugin.absoluteString)))).default;
        let idle; const sent = [];
        await plugin.setup({ session: {
          hook: async (name, callback) => { if (name === "experimental.idle") idle = callback; },
          synthetic: async (message) => { sent.push(message); } } });
        const step = process.argv[2];
        await idle({ sessionID: "s1", background: [] });
        const first = sent.length;
        if (step.startsWith("then")) {
          // The model stops again in the same session: with the held change still there, or after putting it back.
          if (step === "then put back") { const fs = await import("node:fs"); fs.writeFileSync(process.argv[3], process.argv[4]); }
          await idle({ sessionID: "s1", background: [] });
          await idle({ sessionID: "s1", background: [] });
        }
        console.log(JSON.stringify({ id: plugin.id, step, first, sent }));
        """.write(to: script, atomically: true, encoding: .utf8)

        let quiet = try run("node", [script.path, "nothing changed"])
        XCTAssertTrue(quiet.out.contains("\"sent\":[]"), quiet.out)
        try editMatcher("phone fallback")
        let held = try run("node", [script.path, "changed"])
        XCTAssertTrue(held.out.contains("\"id\":\"camr-gate\""), held.out)
        XCTAssertTrue(held.out.contains("matched by its account reference only"), held.out)
        XCTAssertTrue(held.out.contains("Easter Monday, 31 wrong tickets"), held.out)
        XCTAssertTrue(held.out.contains("CAMR held your reply"), held.out)
        XCTAssertTrue(held.out.contains("\"sessionID\":\"s1\""), held.out)
        let again = try run("node", [script.path, "same change"])
        XCTAssertTrue(again.out.contains("\"sent\":[]"), "the same change is held once: \(again.out)")
        try editMatcher("and more")
        let changedAgain = try run("node", [script.path, "changed again"])
        XCTAssertTrue(changedAgain.out.contains("CAMR held your reply"), "a new change is held again: \(changedAgain.out)")

        // Held, then the model stops again without putting it back (gemma4:12b wrote "I have reverted" twice and had
        // not): one follow-up naming the file, then nothing.
        try editMatcher("third change")
        let stillThere = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try run("node", [script.path, "then the same"]).out.utf8)) as? [String: Any])
        let sent = try XCTUnwrap(stillThere["sent"] as? [[String: Any]])
        XCTAssertEqual(stillThere["first"] as? Int, 1)
        XCTAssertEqual(sent.count, 2, "\(sent)")
        XCTAssertTrue((sent[1]["text"] as? String ?? "").contains("still in shop/payments/matcher.py"), "\(sent[1])")
        XCTAssertTrue((sent[1]["text"] as? String ?? "").contains("you have not yet: put it back now"), "\(sent[1])")
        // Held, then put back: nothing more.
        let matcher = code.appendingPathComponent("payments/matcher.py")
        let original = "def ticket_for_line(store, line):\n    return store.tickets.get(line.account_ref)\n"
        try editMatcher("fourth change")
        let putBack = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try run("node", [script.path, "then put back", matcher.path, original]).out.utf8)) as? [String: Any])
        XCTAssertEqual((putBack["sent"] as? [Any])?.count, 1, "\(putBack)")
    }

    func testTheOpenClawGateAddsTheDecisionsToTheEditsResultOnce() async throws {
        try XCTSkipUnless(available("node"), "node is not installed")
        try await gateFixture()
        let setup = try installed(.openClaw)
        let settings = try json(".openclaw/openclaw.json")
        let config = try XCTUnwrap(value(settings, "plugins.entries.camr-gate.config") as? [String: Any])
        XCTAssertEqual(config["vault"] as? String, setup.vault)
        let plugin = home.appendingPathComponent(".openclaw/camr-gate/index.mjs")
        let script = top.appendingPathComponent("drive-openclaw.mjs")
        try """
        const plugin = (await import(\(quoted(plugin.absoluteString)))).default;
        let middleware;
        plugin.register({ pluginConfig: \(Connect.json(config).trimmingCharacters(in: .whitespacesAndNewlines)),
          registerAgentToolResultMiddleware: (callback) => { middleware = callback; } });
        const result = { content: [{ type: "text", text: "Edited matcher.py" }] };
        const read = await middleware({ toolName: "read", result });
        const first = await middleware({ toolName: "edit", result });
        const second = await middleware({ toolName: "edit", result });
        console.log(JSON.stringify({ read: read ?? null, first: first ?? null, second: second ?? null }));
        """.write(to: script, atomically: true, encoding: .utf8)
        try editMatcher("phone fallback")
        let out = try run("node", [script.path]).out
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(XCTUnwrap(out.split(separator: "\n").last).utf8)) as? [String: Any], out)
        XCTAssertTrue(parsed["read"] is NSNull, "a read changes nothing, so it is not checked")
        XCTAssertTrue(parsed["second"] is NSNull, "the same change is held once")
        let content = try XCTUnwrap(value(try XCTUnwrap(parsed["first"] as? [String: Any]), "result.content") as? [[String: Any]])
        XCTAssertEqual(content.first?["text"] as? String, "Edited matcher.py", "the tool's own result is kept")
        let added = try XCTUnwrap(content.last?["text"] as? String)
        XCTAssertTrue(added.contains("matched by its account reference only") && added.contains("CAMR held your reply"), added)
    }

    func testTheHermesGateAsksAtTheEndOfTheTurnOnceAndAfterAShellEdit() async throws {
        try XCTSkipUnless(available("python3"), "python3 is not installed")
        try await gateFixture()
        _ = try installed(.hermes)
        let plugins = home.appendingPathComponent(".hermes/plugins")
        let script = top.appendingPathComponent("drive.py")
        try """
        import importlib, json, sys
        sys.path.insert(0, \(quoted(plugins.path)))
        gate = importlib.import_module("camr-gate")
        hooks = {}
        gate.register(type("Ctx", (), {"register_hook": lambda self, name, callback: hooks.__setitem__(name, callback)})())
        step = sys.argv[1]
        out = {"hooks": sorted(hooks)}
        if step == "turn":
            out["first"] = hooks["pre_verify"](session_id="s1", attempt=0, changed_paths=["payments/matcher.py"])
            out["second"] = hooks["pre_verify"](session_id="s1", attempt=1, changed_paths=["payments/matcher.py"])
            out["third"] = hooks["pre_verify"](session_id="s1", attempt=2, changed_paths=["payments/matcher.py"])
        else:
            out["read"] = hooks["transform_tool_result"](tool_name="read_file", result="text", session_id="s2")
            out["shell"] = hooks["transform_tool_result"](tool_name="terminal", result="$ sed -i ...", session_id="s2")
            out["end"] = hooks["pre_verify"](session_id="s2", attempt=0, changed_paths=[])
            with open(sys.argv[2], "w") as handle:
                handle.write(sys.argv[3])  # the model puts the code back
            out["after"] = hooks["pre_verify"](session_id="s2", attempt=1, changed_paths=[])
        print(json.dumps(out))
        """.write(to: script, atomically: true, encoding: .utf8)

        try editMatcher("phone fallback")
        let turn = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try run("python3", ["-I", script.path, "turn"]).out.utf8)) as? [String: Any])
        XCTAssertEqual(turn["hooks"] as? [String], ["pre_verify", "transform_tool_result"])
        let first = try XCTUnwrap(turn["first"] as? [String: Any])
        XCTAssertEqual(first["decision"] as? String, "block")
        XCTAssertTrue((first["reason"] as? String ?? "").contains("Easter Monday, 31 wrong tickets"))
        let second = try XCTUnwrap(turn["second"] as? [String: Any], "the change is still there: one follow-up")
        XCTAssertTrue((second["reason"] as? String ?? "").contains("still in shop/payments/matcher.py"), "\(second)")
        XCTAssertTrue(turn["third"] is NSNull, "and only one")

        try editMatcher("a shell edit")
        let original = "def ticket_for_line(store, line):\n    return store.tickets.get(line.account_ref)\n"
        let matcher = code.appendingPathComponent("payments/matcher.py").path
        let shell = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try run("python3", ["-I", script.path, "shell", matcher, original]).out.utf8)) as? [String: Any])
        XCTAssertTrue(shell["read"] is NSNull)
        XCTAssertTrue((shell["shell"] as? String ?? "").hasPrefix("$ sed -i ...\n\nYou changed"), "\(shell["shell"] ?? "")")
        XCTAssertEqual((shell["end"] as? [String: Any])?["decision"] as? String, "block", "shown in the shell's result, still asked at the end")
        XCTAssertTrue(shell["after"] is NSNull, "put back: no follow-up")
    }
}
