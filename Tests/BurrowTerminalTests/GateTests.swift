@testable import BurrowCore
@testable import BurrowMCP
@testable import BurrowTools
import XCTest

/// D-93: a change that goes against a decision is held until the decision has been shown beside it, by `burrow check`,
/// Claude Code's Stop hook and git's pre-commit hook, whether or not the model calls burrow_check. The vault's linked code
/// is a git repository where reconcile.py imports matcher.py, as in the Matatu project, and the decision cites reconcile.py.
final class GateTests: XCTestCase {
    private var top: URL!
    private var vault: Vault!
    private var code: URL { top.appendingPathComponent("shop") }
    private var matcher: URL { code.appendingPathComponent("payments/matcher.py") }
    private let phoneFallback = "def ticket_for_line(store, line):\n    for t in store.tickets.values():\n        if t.phone == line.phone:\n            return t\n"

    override func setUp() async throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("gate-\(UUID().uuidString)")
        let files = [
            "vault/Home.md": "# Home\n\nThe shop's back office.\n",
            "shop/README.md": "The shop.\n",
            "shop/payments/__init__.py": "",
            "shop/payments/matcher.py": "def ticket_for_line(store, line):\n    return store.tickets.get(line.account_ref)\n",
            "shop/payments/reconcile.py": "from .matcher import ticket_for_line\n\n\ndef reconcile(store, lines):\n    return [ticket_for_line(store, line) for line in lines]\n",
        ]
        for (path, text) in files {
            let url = top.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        for arguments in [["init", "-q"], ["add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qm", "start"]] {
            _ = VaultTools.git(code, arguments)
        }
        vault = try Vault(project: top.appendingPathComponent("vault"), everything: true)
        try vault.linkFolder(code)
        try await vault.refresh(embedder: nil)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: top) }

    @discardableResult
    private func decide() throws -> LedgerCommit {
        try Ledger(vault: vault).commit(.decision, "A statement line is matched by its account reference only.",
                                        body: "Rejected: Matching on phone and amount.\nBecause: Conductors pay for whole groups from one phone, so phone and amount name the wrong passenger.",
                                        files: ["shop/payments/reconcile.py"], author: "claude-opus-5-5", client: "claude-code")
    }

    private func git(_ arguments: String...) -> String? {
        VaultTools.git(code, ["-c", "user.name=t", "-c", "user.email=t@example.com"] + arguments)
    }

    // MARK: exit codes and the fingerprint

    func testNothingRestsOnTheChangeSoItPasses() throws {
        try decide()
        XCTAssertEqual(Gate.check(vault: vault, by: "test").exitCode, 0, "no change at all")
        try "The shop, now with notes.\n".write(to: code.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let outcome = Gate.check(vault: vault, by: "test")
        XCTAssertEqual(outcome.exitCode, 0)
        XCTAssertNil(outcome.fingerprint)
        XCTAssertTrue(outcome.text.contains("No decision in the Ledger rests on these files"), outcome.text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: Gate.folder(vault).path), "nothing to record")
    }

    func testAChangeOneImportAwayIsHeldOnceThenPassesUntilItChangesAgain() throws {
        let decision = try decide()
        // matcher.py is not cited; reconcile.py, which imports it, is.
        try phoneFallback.write(to: matcher, atomically: true, encoding: .utf8)
        let first = Gate.check(vault: vault, by: "test")
        XCTAssertEqual(first.exitCode, 2)
        XCTAssertTrue(first.holds)
        XCTAssertEqual(first.report.rules.map(\.id), [decision.id])
        XCTAssertEqual(first.report.resting, ["shop/payments/matcher.py"])
        XCTAssertTrue(first.text.contains("Because: Conductors pay for whole groups"), first.text)
        XCTAssertTrue(first.text.contains("+        if t.phone == line.phone:"), first.text)

        let second = Gate.check(vault: vault, by: "test")
        XCTAssertEqual(second.exitCode, 0)
        XCTAssertTrue(second.shownBefore)
        XCTAssertEqual(second.fingerprint, first.fingerprint)
        XCTAssertEqual(second.text, first.text, "the same words every time")

        try (phoneFallback + "# and amount\n").write(to: matcher, atomically: true, encoding: .utf8)
        let third = Gate.check(vault: vault, by: "test")
        XCTAssertEqual(third.exitCode, 2, "a different change to the same file is held again")
        XCTAssertNotEqual(third.fingerprint, first.fingerprint)

        // A new decision on the same, already shown, content is a new thing to show.
        _ = Gate.check(vault: vault, by: "test")
        try Ledger(vault: vault).commit(.decision, "Statement lines are never matched by time.", body: "Because: finance said so.",
                                        files: ["shop/payments/matcher.py"], author: "person")
        XCTAssertEqual(Gate.check(vault: vault, by: "test").exitCode, 2)
    }

    func testAReversedDecisionIsNotShownButItsCorrectionIs() throws {
        let decision = try decide()
        let correction = try Ledger(vault: vault).revert(decision.id, why: "Phone matching is fine now.", author: "person", client: "terminal")
        try phoneFallback.write(to: matcher, atomically: true, encoding: .utf8)
        // The correction rests on the same file and is what is in force now, so the change is held beside it.
        let outcome = Gate.check(vault: vault, by: "test")
        XCTAssertEqual(outcome.report.rules.map(\.id), [correction.id])
        XCTAssertEqual(outcome.exitCode, 2)
        XCTAssertTrue(outcome.text.contains("[correction] Wrong: \"A statement line is matched by its account reference only.\". Phone matching is fine now."), outcome.text)
        XCTAssertFalse(outcome.text.contains("Because: Conductors"), "the reversed decision itself is not among them")
    }

    func testTheRecordSaysWhatWasShownAndByWhat() throws {
        let decision = try decide()
        try phoneFallback.write(to: matcher, atomically: true, encoding: .utf8)
        let outcome = Gate.check(vault: vault, by: "burrow check")
        let file = Gate.folder(vault).appendingPathComponent(outcome.fingerprint! + ".json")
        let record = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        XCTAssertEqual(record["shown_by"] as? String, "burrow check")
        XCTAssertEqual(record["decisions"] as? [String], [decision.id])
        let blob = VaultTools.git(code, ["hash-object", "payments/matcher.py"])!.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(record["files"] as? [[String]], [["shop/payments/matcher.py", blob]])
        XCTAssertTrue(file.path.hasPrefix(vault.store.path + "/checks/"), file.path)
    }

    // MARK: the MCP tool and the CLI say the same words, and either counts as shown

    func testBurrowCheckOverMCPShowsTheSameWordsAndCountsAsShown() async throws {
        try decide()
        try phoneFallback.write(to: matcher, atomically: true, encoding: .utf8)
        let tools = VaultTools(vault: vault, embedder: nil) { _ in FakeAnswerer() }
        let server = MCPServer(tools: tools, keepsSessions: false)
        server.toolSet = .door
        _ = await server.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"opencode","version":"1"}}}"#)
        let line = await server.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"burrow_check","arguments":{}}}"#)
        let reply = try JSONSerialization.jsonObject(with: XCTUnwrap(line).data(using: .utf8)!) as! [String: Any]
        let text = (((reply["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""

        let outcome = Gate.check(vault: vault, by: "test")
        XCTAssertEqual(text, outcome.text, "burrow_check and burrow check print identical words")
        XCTAssertTrue(outcome.shownBefore, "the model's burrow_check already showed it")
        XCTAssertEqual(outcome.exitCode, 0)
    }

    // MARK: staged, for the git gate

    func testStagedChecksWhatTheNextCommitHoldsAndAgreesWithTheWorkingTree() throws {
        try decide()
        try phoneFallback.write(to: matcher, atomically: true, encoding: .utf8)
        XCTAssertEqual(Gate.check(vault: vault, staged: true, by: "test").exitCode, 0, "nothing staged yet")
        // Shown in the working tree (as burrow_check or the Stop hook would), then staged: the same content passes.
        XCTAssertEqual(Gate.check(vault: vault, by: "test").exitCode, 2)
        _ = git("add", "-A")
        let staged = Gate.check(vault: vault, staged: true, by: "test")
        XCTAssertEqual(staged.report.changed, ["shop/payments/matcher.py"])
        XCTAssertEqual(staged.exitCode, 0, "same blob staged as shown")
        // Edited after staging: the staged content is what counts, and it was shown.
        try (phoneFallback + "# later\n").write(to: matcher, atomically: true, encoding: .utf8)
        XCTAssertEqual(Gate.check(vault: vault, staged: true, by: "test").exitCode, 0)
        XCTAssertEqual(Gate.check(vault: vault, by: "test").exitCode, 2, "the working tree now differs from what was shown")
    }

    // MARK: Claude Code's Stop hook

    private func stopEvent(active: Bool) -> [String: Any] {
        ["session_id": "abc123", "transcript_path": "/nonexistent.jsonl", "cwd": top.path, "permission_mode": "default",
         "hook_event_name": "Stop", "stop_hook_active": active, "last_assistant_message": "Done.", "background_tasks": [], "session_crons": []]
    }

    func testTheStopHookBlocksOnceWithTheDecisionAndNeverLoops() throws {
        try decide()
        XCTAssertNil(Gate.stop(event: stopEvent(active: false), vault: vault), "no change, no block")
        try phoneFallback.write(to: matcher, atomically: true, encoding: .utf8)
        // Already continuing because of a stop hook: never block, and do not count it as shown.
        XCTAssertNil(Gate.stop(event: stopEvent(active: true), vault: vault))

        let line = try XCTUnwrap(Gate.stop(event: stopEvent(active: false), vault: vault))
        XCTAssertFalse(line.contains("\n"), "one JSON object on one line")
        let reply = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
        XCTAssertEqual(Set(reply.keys), ["decision", "reason"])
        XCTAssertEqual(reply["decision"] as? String, "block")
        let reason = reply["reason"] as? String ?? ""
        XCTAssertTrue(reason.hasPrefix(Gate.check(vault: vault, by: "test").text), "the check's own words first")
        XCTAssertTrue(reason.contains("A statement line is matched by its account reference only."), reason)
        XCTAssertTrue(reason.contains("Because: Conductors pay for whole groups"), reason)
        XCTAssertTrue(reason.hasSuffix(Gate.stopNote), reason)
        XCTAssertTrue(Gate.stopNote.contains("tell the person which decision this change touches and whether it goes against it"))

        // Claude carries on, says its piece, and stops again: the same change has been shown, so it may stop.
        XCTAssertNil(Gate.stop(event: stopEvent(active: false), vault: vault))
        // It edits again in the continued turn: stop_hook_active is true there, so still no second block.
        try (phoneFallback + "# again\n").write(to: matcher, atomically: true, encoding: .utf8)
        XCTAssertNil(Gate.stop(event: stopEvent(active: true), vault: vault))
    }

    func testTheGitGateScriptRunsTheStagedCheckAndRefusesOnlyOnTwo() {
        let script = Gate.preCommitScript(burrow: "'/opt/b/burrow'", vault: "'/v'")
        XCTAssertTrue(script.hasPrefix("#!/bin/sh\n"))
        XCTAssertTrue(script.contains("out=$('/opt/b/burrow' check '/v' --staged 2>&1)"), script)
        XCTAssertTrue(script.contains("if [ \"$status\" -eq 2 ]; then"), script)
        XCTAssertTrue(script.contains("committing anyway"), "a Burrow error never blocks a commit")
    }

    // MARK: the real binary: exit codes, the git gate in a repository, the printed Claude Code settings

    private func binary() throws -> URL {
        let built = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("burrow")
        guard FileManager.default.isExecutableFile(atPath: built.path) else { throw XCTSkip("run swift build first: no burrow binary beside the tests") }
        return built
    }

    private func run(_ arguments: [String], in folder: URL? = nil, input: String? = nil, executable: URL? = nil) throws -> (status: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = try executable ?? binary()
        process.arguments = arguments
        process.currentDirectoryURL = folder ?? code
        let out = Pipe(), err = Pipe(), stdin = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = stdin
        try process.run()
        if let input { stdin.fileHandleForWriting.write(Data(input.utf8)) }
        try stdin.fileHandleForWriting.close()
        let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }

    func testTheCommandExitsZeroTwoAndOne() throws {
        try decide()
        let vaultPath = vault.root.path
        XCTAssertEqual(try run(["check", vaultPath]).status, 0)
        try phoneFallback.write(to: matcher, atomically: true, encoding: .utf8)
        let held = try run(["check", vaultPath])
        XCTAssertEqual(held.status, 2, held.err)
        XCTAssertTrue(held.out.contains("matched by its account reference only"), held.out)
        XCTAssertTrue(held.err.contains("held"), held.err)
        let json = try run(["check", vaultPath, "--json"])
        XCTAssertEqual(json.status, 0)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.out.utf8)) as! [String: Any]
        XCTAssertEqual(parsed["shown_before"] as? Bool, true)
        XCTAssertEqual((parsed["decisions"] as? [[String: Any]])?.first?["because"] as? String,
                       "Conductors pay for whole groups from one phone, so phone and amount name the wrong passenger.")
        XCTAssertEqual(try run(["check", top.appendingPathComponent("missing").path]).status, 1)
    }

    func testTheGitGateRefusesTheCommitOnceAndKeepsThePostCommitHook() throws {
        try decide()
        let vaultPath = vault.root.path
        let installed = try run(["hook", "install", "git-gate", vaultPath])
        XCTAssertEqual(installed.status, 0, installed.err)
        XCTAssertEqual(try run(["hook", "install", "git", vaultPath]).status, 0, "the post-commit writer still works beside it")
        XCTAssertNotEqual(try run(["hook", "install", "git-gate", vaultPath]).status, 0, "an existing hook is never replaced")
        let hooks = code.appendingPathComponent(".git/hooks")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: hooks.appendingPathComponent("pre-commit").path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: hooks.appendingPathComponent("post-commit").path))

        let gitTool = URL(fileURLWithPath: "/usr/bin/git")
        let commit = ["-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qm", "phone fallback"]
        try phoneFallback.write(to: matcher, atomically: true, encoding: .utf8)
        _ = git("add", "-A")
        let refused = try run(commit, executable: gitTool)
        XCTAssertNotEqual(refused.status, 0)
        XCTAssertTrue(refused.err.contains("matched by its account reference only"), refused.err)
        XCTAssertTrue(refused.err.contains("commit refused"), refused.err)
        XCTAssertEqual(git("log", "-1", "--format=%s")?.trimmingCharacters(in: .whitespacesAndNewlines), "start")

        let passed = try run(commit, executable: gitTool)
        XCTAssertEqual(passed.status, 0, passed.err)
        XCTAssertEqual(git("log", "-1", "--format=%s")?.trimmingCharacters(in: .whitespacesAndNewlines), "phone fallback")
        // The post-commit hook linked it in the Ledger as before.
        XCTAssertTrue(Ledger(vault: vault).all().contains { $0.kind == .code && $0.message.hasSuffix("phone fallback") })

        // Outside a linked repository the gate is not installed.
        let elsewhere = top.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        _ = VaultTools.git(elsewhere, ["init", "-q"])
        XCTAssertNotEqual(try run(["hook", "install", "git-gate", vaultPath], in: elsewhere).status, 0)
    }

    func testClaudeSettingsIncludeTheStopGateAndTheHookHoldsThroughTheBinary() throws {
        try decide()
        let vaultPath = vault.root.path
        let printed = try run(["hook", "install", "claude", vaultPath]).out
        let json = String(printed[printed.range(of: "{")!.lowerBound...])
        let settings = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]
        XCTAssertEqual(Set(hooks.keys), ["SessionStart", "PreCompact", "SessionEnd", "Stop"])
        let stop = (((hooks["Stop"] as! [[String: Any]])[0]["hooks"]) as! [[String: Any]])[0]
        let command = stop["command"] as! String
        XCTAssertTrue(command.hasSuffix(" --gate"), command)
        XCTAssertNil((hooks["Stop"] as! [[String: Any]])[0]["matcher"], "Stop takes no matcher")

        try phoneFallback.write(to: matcher, atomically: true, encoding: .utf8)
        let event = try String(decoding: JSONSerialization.data(withJSONObject: stopEvent(active: false)), as: UTF8.self)
        let blocked = try run(["hook", "claude", vaultPath, "--gate"], input: event)
        XCTAssertEqual(blocked.status, 0)
        let reply = try JSONSerialization.jsonObject(with: Data(blocked.out.utf8)) as! [String: Any]
        XCTAssertEqual(reply["decision"] as? String, "block")
        let again = try run(["hook", "claude", vaultPath, "--gate"], input: event)
        XCTAssertEqual(again.out, "", "shown once; the next Stop goes through")
    }

    func testStopWithoutTheGateFlagStillWritesTheHandoff() throws {
        // A Stop entry set up before D-93 (`burrow hook claude <vault>`, no --gate) keeps its handoff when nothing is held.
        let transcript = top.appendingPathComponent("t.jsonl")
        try #"{"type":"user","message":{"role":"user","content":"Tidy the README"}}"#.write(to: transcript, atomically: true, encoding: .utf8)
        var event = stopEvent(active: false)
        event["transcript_path"] = transcript.path
        event["cwd"] = code.path
        let input = try String(decoding: JSONSerialization.data(withJSONObject: event), as: UTF8.self)
        let ran = try run(["hook", "claude", vault.root.path], input: input)
        XCTAssertEqual(ran.out, "")
        XCTAssertTrue(ran.err.contains("kept handoff"), ran.err)
        XCTAssertTrue(Ledger(vault: vault).all().contains { $0.kind == .handoff && $0.message.contains("Tidy the README") })
        // With --gate, the same Stop writes nothing.
        let before = Ledger(vault: vault).all().count
        _ = try run(["hook", "claude", vault.root.path, "--gate"], input: input)
        XCTAssertEqual(Ledger(vault: vault).all().count, before)
    }
}
