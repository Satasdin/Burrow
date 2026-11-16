@testable import BurrowCore
@testable import BurrowTools
import Foundation
import XCTest

/// D-114: what three volunteers hit with Burrow 1.2.1 on 16 November, each run the way they met it.
final class TesterFixesTests: XCTestCase {
    private var top: URL!
    private var state: URL { top.appendingPathComponent("state") }
    private var home: URL { top.appendingPathComponent("home") }

    override func setUp() async throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("testers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: top) }

    private func folder(_ path: String) throws -> URL {
        let url = top.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: 5. an index no one asked for

    /// A tester's ~/Downloads got a 1.2 GB `.burrow`: every command that opens a vault made one in whatever folder it was
    /// given. Now each refuses a folder that isn't a vault, says how to make it one, and leaves nothing behind.
    func testNoCommandBuildsAnIndexInAFolderThatIsNotAVault() throws {
        let downloads = try folder("Downloads")
        try "a pdf, say\n".write(to: downloads.appendingPathComponent("paper.md"), atomically: true, encoding: .utf8)
        let commands: [[String]] = [
            ["find", downloads.path, "anything"], ["stats", downloads.path], ["ask", downloads.path, "hi"], ["brief", downloads.path, "hi"],
            ["mcp", downloads.path], ["chat", downloads.path], ["tui", downloads.path], ["log", downloads.path], ["resume", downloads.path],
            ["commit", downloads.path, "a decision"], ["check", downloads.path], ["recall", downloads.path], ["hook", "claude", downloads.path],
            ["link", "list", downloads.path], ["config", downloads.path, "list"], ["bridge", "list", downloads.path],
            ["connect", "claude-code", downloads.path], ["team", "list", downloads.path],
        ]
        for command in commands {
            let ran = try BurrowBinary.piped(command, state: state, input: "{}\n")
            XCTAssertNotEqual(ran.status, 0, "\(command): \(ran.out)")
            XCTAssertTrue(ran.err.contains("isn't a Burrow vault") && ran.err.contains("burrow vault new"), "\(command): \(ran.err)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: downloads.appendingPathComponent(".burrow").path), "\(command) made an index")
        }
        // Started inside it, the bare command makes nothing either.
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloads.appendingPathComponent(".burrow").path))
    }

    /// The ways a person chooses a folder still make one: `vault new`, and `index` naming it.
    func testChoosingAFolderStillMakesItAVault() throws {
        let notes = try folder("Notes"), code = try folder("code")
        XCTAssertEqual(try BurrowBinary.piped(["vault", "new", notes.path, "--no-embed"], state: state).status, 0)
        XCTAssertEqual(try BurrowBinary.piped(["index", code.path, "--no-embed"], state: state).status, 0)
        XCTAssertTrue(Vault.hasIndex(notes))
        XCTAssertTrue(Vault.hasIndex(code))
        XCTAssertEqual(try BurrowBinary.piped(["stats", notes.path], state: state).status, 0)
    }

    // MARK: 8. vault new on a vault

    func testVaultNewOnAVaultSaysSoAndCarriesOn() throws {
        let notes = try folder("BurrowTest")
        let first = try BurrowBinary.piped(["vault", "new", notes.path, "--no-embed"], state: state)
        XCTAssertEqual(first.status, 0, first.err)
        XCTAssertEqual(LastVault.read(in: state), notes.standardizedFileURL.path, "the app's first launch opens it")
        let again = try BurrowBinary.piped(["vault", "new", notes.path, "--no-embed"], state: state)
        XCTAssertEqual(again.status, 0, again.err)
        XCTAssertTrue(again.out.contains("is a vault already"), again.out)
        XCTAssertTrue(again.out.contains("nothing was changed"), again.out)
    }

    // MARK: 5. seeing and removing stray indexes

    func testVaultListShowsKnownAndStrayIndexesAndOnlyThePersonRemovesOne() throws {
        let notes = try folder("home/Notes")
        XCTAssertEqual(try BurrowBinary.piped(["vault", "new", notes.path, "--no-embed"], state: state).status, 0)
        _ = try Vault(project: try folder("home/Downloads"), everything: true)   // as 1.2.1 left it
        var environment = BurrowBinary.environment(state)
        environment["HOME"] = home.path
        let listed = try run(["vault", "list"], environment: environment)
        XCTAssertEqual(listed.status, 0, listed.out)
        XCTAssertTrue(listed.out.contains("Vaults Burrow knows:\n  \(notes.standardizedFileURL.path)"), listed.out)
        XCTAssertTrue(listed.out.contains("not on its list"), listed.out)
        XCTAssertTrue(listed.out.contains(home.appendingPathComponent("Downloads").path), listed.out)
        XCTAssertTrue(listed.out.contains("burrow vault remove <folder>"), listed.out)

        let downloads = home.appendingPathComponent("Downloads")
        let piped = try BurrowBinary.piped(["vault", "remove", downloads.path], state: state, input: "yes\n")
        XCTAssertEqual(piped.status, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloads.appendingPathComponent(".burrow").path), "a program can't remove it")
        let declined = try BurrowBinary.inTerminal(["vault", "remove", downloads.path], state: state, answer: "no")
        XCTAssertEqual(declined.status, 1, declined.out)
        XCTAssertTrue(declined.out.contains("Move Burrow's index for"), declined.out)
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloads.appendingPathComponent(".burrow").path))
    }

    private func run(_ arguments: [String], environment: [String: String]) throws -> (status: Int32, out: String) {
        let process = Process()
        process.executableURL = BurrowBinary.url
        process.arguments = arguments
        process.environment = environment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: 7. small text errors

    /// burrow_resume said "2 commits" and listed one: the other was the handoff, shown under another heading.
    func testResumeCountsEachKindItShows() throws {
        let ledger = Ledger(folder: top.appendingPathComponent("ledger"), read: { _ in nil }, modified: { _ in nil })
        try ledger.commit(.fact, "The API returns JSON", author: "claude", at: Date(timeIntervalSince1970: 10))
        try ledger.commit(.handoff, "Claude Code stopped when the session ended", author: "claude", at: Date(timeIntervalSince1970: 20))
        let head = ledger.resume()
        XCTAssertTrue(head.contains("2 commits (1 fact, 1 handoff)"), head)
        XCTAssertTrue(head.contains("Where the last session stopped: Claude Code stopped"), head)
        XCTAssertTrue(head.contains("[fact] The API returns JSON"), head)
        try ledger.commit(.decision, "Use SQLite", author: "claude", at: Date(timeIntervalSince1970: 30))
        XCTAssertTrue(ledger.resume().contains("3 commits (1 decision, 1 fact, 1 handoff)"), ledger.resume())
        let one = Ledger(folder: top.appendingPathComponent("one"), read: { _ in nil }, modified: { _ in nil })
        try one.commit(.decision, "Use SQLite", author: "claude")
        XCTAssertTrue(one.resume().contains("1 commit (1 decision)"), one.resume())
    }

    /// "0 files changed — The linked code matches its last git commit", in a vault with no code folder linked.
    func testTheFilesChangedTileSaysWhenNoCodeIsLinked() {
        XCTAssertEqual(CheckReport.tileDetail(nil, linkedFolders: 0), "No code folder is linked, so there are no code changes to check")
        let empty = CheckReport(changed: [], diffs: [], rules: [])
        XCTAssertEqual(CheckReport.tileDetail(empty, linkedFolders: 0), "No code folder is linked, so there are no code changes to check")
        XCTAssertEqual(CheckReport.tileDetail(empty, linkedFolders: 1), "The linked code matches its last git commit")
        XCTAssertEqual(CheckReport.tileDetail(CheckReport(changed: ["a.py"], diffs: [], rules: []), linkedFolders: 1), "No decision rests on them")
    }

    // MARK: 8. where handed-over decisions came from

    func testDecisionsHandedToANewSessionSayWhenTheyWereKeptAndFlagLeftovers() async throws {
        let vault = try Vault(project: try folder("vault"), everything: true)
        vault.stateFolder = state
        try "def pay(): pass\n".write(to: vault.root.appendingPathComponent("pay.py"), atomically: true, encoding: .utf8)
        try await vault.refresh()
        let ledger = Ledger(vault: vault)
        try ledger.commit(.decision, "Retry a failed charge three times", files: ["pay.py"], author: "claude", at: Date(timeIntervalSince1970: 1_700_000_000))
        try ledger.commit(.decision, "Flask app listens on port 5050", files: ["app/server.py"], author: "claude", at: Date(timeIntervalSince1970: 1_700_000_100))
        let tools = VaultTools(vault: vault, embedder: nil) { _ in FakeAnswerer() }
        let rules = tools.rulesInForce()
        let lines = rules.split(separator: "\n").map(String.init)
        let retry = try XCTUnwrap(lines.first { $0.contains("Retry a failed charge") })
        let flask = try XCTUnwrap(lines.first { $0.contains("port 5050") })
        XCTAssertTrue(retry.contains("Kept \(Ledger.when(Date(timeIntervalSince1970: 1_700_000_000))) by an earlier session."), retry)
        XCTAssertFalse(retry.contains("LEFT OVER"), retry)
        XCTAssertTrue(flask.contains("LEFT OVER?: none of the files it rests on (app/server.py) is in this vault now"), flask)
        // The session-start hook's text (burrow_resume) flags it too.
        XCTAssertTrue(ledger.resume().contains("LEFT OVER?: none of the files it rests on (app/server.py)"), ledger.resume())
    }

    // MARK: 6. connecting Claude Code while it runs

    /// With Claude Code's own `claude` command, the server goes in through `claude mcp add-json`, so Claude Code can stay
    /// open; Burrow checks the file afterwards rather than taking the command's word. A stand-in `claude` here records
    /// what it was asked and writes what the real one writes (checked against Claude Code 2.1.322 by hand).
    func testClaudeCodeIsConnectedThroughItsOwnCommandWithoutClosingIt() throws {
        let calls = top.appendingPathComponent("calls")
        let fake = top.appendingPathComponent("claude")
        try """
        #!/usr/bin/python3
        import json, os, sys
        open("\(calls.path)", "a").write(" ".join(sys.argv[1:4]) + "\\n")
        path = os.path.join(os.environ["HOME"], ".claude.json")
        root = json.load(open(path)) if os.path.exists(path) else {}
        if sys.argv[1:3] == ["mcp", "add-json"]:
            if "burrow" in root.get("mcpServers", {}): print("MCP server burrow already exists in user config"); sys.exit(1)
            root.setdefault("mcpServers", {})[sys.argv[5]] = json.loads(sys.argv[6])
        elif sys.argv[1:3] == ["mcp", "remove"]:
            root.get("mcpServers", {}).pop("burrow", None)
        json.dump(root, open(path, "w"), indent=2)
        """.write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        try #"{"numStartups": 41, "mcpServers": {"burrow": {"command": "/old/burrow"}}}"#.write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
        let vault = try folder("vault")
        let setup = Connect.Setup(burrow: "/opt/burrow", vault: vault.path, home: home, claudeCommand: fake.path)
        let plan = Connect.plan(.claudeCode, setup)
        XCTAssertFalse(plan.notes.joined().contains("Close Claude Code before writing"), plan.notes.joined())
        XCTAssertTrue(plan.notes.joined().contains("Claude Code can stay open"))
        let said = try Connect.apply(plan, setup)
        XCTAssertTrue(said.joined().contains("mcp add-json"), said.joined())
        XCTAssertEqual(try String(contentsOf: calls, encoding: .utf8), "mcp remove burrow\nmcp add-json --scope\n")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: home.appendingPathComponent(".claude.json"))) as? [String: Any])
        let server = try XCTUnwrap((root["mcpServers"] as? [String: Any])?["burrow"] as? [String: Any])
        XCTAssertEqual(server["alwaysLoad"] as? Bool, true)
        XCTAssertEqual(server["args"] as? [String], ["mcp", vault.path])
        XCTAssertEqual(root["numStartups"] as? Int, 41)
        XCTAssertNotNil(FileManager.default.contents(atPath: home.appendingPathComponent(".claude/settings.json").path), "the hooks are written as before")
        XCTAssertTrue(Connect.plan(.claudeCode, setup).pending.isEmpty, "set up once")

        // A `claude` that says yes and writes nothing is not believed.
        let liar = top.appendingPathComponent("liar")
        try "#!/bin/sh\nexit 0\n".write(to: liar, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: liar.path)
        try FileManager.default.removeItem(at: home.appendingPathComponent(".claude.json"))
        let lied = Connect.Setup(burrow: "/opt/burrow", vault: vault.path, home: home, claudeCommand: liar.path)
        XCTAssertThrowsError(try Connect.apply(Connect.plan(.claudeCode, lied), lied))
        // Without the command, the old way and its warning.
        XCTAssertTrue(Connect.plan(.claudeCode, Connect.Setup(burrow: "/opt/burrow", vault: vault.path, home: home)).notes.joined().contains("Close Claude Code before writing"))
    }

    // MARK: 2. the installer and PATH

    /// A tester got "command not found: burrow": the installer put it in ~/.local/bin and only printed a line about PATH
    /// among others. Run here from a local copy of a release, with a scratch HOME, as `curl … | sh` runs it.
    func testTheInstallerAddsItsFolderToPATHOrSaysExactlyHow() throws {
        let release = try folder("release")
        let staged = try folder("staged")
        try FileManager.default.copyItem(at: BurrowBinary.url, to: staged.appendingPathComponent("burrow"))
        XCTAssertEqual(try shell("tar -czf '\(release.path)/burrow-macos-arm64.tar.gz' -C '\(staged.path)' burrow && cd '\(release.path)' && shasum -a 256 burrow-macos-arm64.tar.gz > SHA256SUMS").status, 0)
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/install.sh").path
        func install(_ flag: String, home: URL) throws -> (status: Int32, out: String) {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            return try shell("cat '\(script)' | HOME='\(home.path)' SHELL=/bin/zsh PATH=/usr/bin:/bin:/usr/sbin:/sbin BURROW_RELEASE_BASE='file://\(release.path)' sh -s -- \(flag)")
        }
        let asked = top.appendingPathComponent("home-add")
        let added = try install("--add-to-path", home: asked)
        XCTAssertEqual(added.status, 0, added.out)
        let zshrc = try String(contentsOf: asked.appendingPathComponent(".zshrc"), encoding: .utf8)
        XCTAssertTrue(zshrc.contains("export PATH=\"$HOME/.local/bin:$PATH\""), zshrc)
        XCTAssertTrue(added.out.contains("New terminal windows find burrow"), added.out)
        // A new zsh, as a new Terminal window starts one, finds it.
        let found = try shell("HOME='\(asked.path)' PATH=/usr/bin:/bin zsh -c 'source ~/.zshrc; burrow --version'")
        XCTAssertEqual(found.out.trimmingCharacters(in: .whitespacesAndNewlines), "burrow \(BurrowVersion.number)")
        // Run again, the line isn't added twice.
        _ = try install("--add-to-path", home: asked)
        XCTAssertEqual(try String(contentsOf: asked.appendingPathComponent(".zshrc"), encoding: .utf8).components(separatedBy: ".local/bin:$PATH").count, 2)

        // Through a pipe with no terminal (an agent running it), nothing is changed and the exact line is printed.
        let quiet = top.appendingPathComponent("home-pipe")
        let printed = try install("", home: quiet)
        XCTAssertEqual(printed.status, 0, printed.out)
        XCTAssertFalse(FileManager.default.fileExists(atPath: quiet.appendingPathComponent(".zshrc").path))
        XCTAssertTrue(printed.out.contains("your shell can't find burrow yet"), printed.out)
        XCTAssertTrue(printed.out.contains("Add this line to \(quiet.path)/.zshrc"), printed.out)
        XCTAssertTrue(printed.out.contains("export PATH=\"$HOME/.local/bin:$PATH\""), printed.out)
    }

    private func shell(_ command: String) throws -> (status: Int32, out: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
