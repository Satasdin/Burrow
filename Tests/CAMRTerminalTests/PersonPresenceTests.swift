@testable import CAMRCore
@testable import CAMRTools
import CryptoKit
import Darwin
import XCTest

/// D-113: a connected agent with a shell can make a pseudo-terminal and type yes, so a terminal and a yes no longer
/// count as the person on their own. CAMR refuses an agent's environment (layer 1) and an agent's process tree
/// (layer 2), and for the steps that defeat the gate (overriding a breaking change, confirming or clearing a decision's
/// check) asks for a one-time code shown only outside the terminal (layer 3). The typed yes stays the last step.
final class PersonPresenceTests: XCTestCase {
    private var top: URL!
    private var vault: Vault!
    private var state: URL { top.appendingPathComponent("state") }
    private var code: URL { top.appendingPathComponent("shop") }
    private var matcher: URL { code.appendingPathComponent("payments/matcher.py") }
    private let matcherText = "def ticket_for_line(store, line):\n    return store.tickets.get(line.account_ref)\n"
    private let phoneFallback = "def ticket_for_line(store, line):\n    for t in store.tickets.values():\n        if t.phone == line.phone:\n            return t\n    return store.tickets.get(line.account_ref)\n"

    override func setUp() async throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("presence-\(UUID().uuidString)")
        for (path, text) in [
            "vault/Home.md": "# Home\n\nThe shop's back office.\n",
            "shop/payments/__init__.py": "",
            "shop/payments/matcher.py": matcherText,
            "elsewhere/notes.md": "Other notes.\n",
        ] {
            let url = top.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        for arguments in [["init", "-q"], ["add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qm", "start"]] {
            _ = VaultTools.git(code, arguments)
        }
        vault = try Vault(project: top.appendingPathComponent("vault"), everything: true)
        vault.stateFolder = state
        try vault.linkFolder(code)
        try await vault.refresh(embedder: nil)
        // An empty record of codes made, so the real binary waits the usual 2 seconds before each code rather than the 20
        // it waits when it can't tell (that wait is tested on its own).
        try "[]".write(to: state.appendingPathComponent("person-codes.json"), atomically: true, encoding: .utf8)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: top) }

    /// A decision with a confirmed check, and a change that breaks it: `camr check` exits 3.
    private func heldDecision() throws -> LedgerCommit {
        let decision = try Ledger(vault: vault).commit(.decision, "ticket_for_line matches a statement line by its account reference only.",
                                                       body: "Rejected: phone and amount.", files: ["shop/payments/matcher.py"],
                                                       author: "claude-opus-5-5", client: "claude-code")
        try DecisionChecks.confirm(DecisionCheck.parse(#"forbid: \.phone\s*=="#, by: "you"), for: decision.id, vault: vault)
        try phoneFallback.write(to: matcher, atomically: true, encoding: .utf8)
        XCTAssertEqual(Gate.check(vault: vault, by: "test").exitCode, 3)
        return decision
    }

    private func overridden(_ decision: LedgerCommit) -> Bool {
        Gate.check(vault: vault, by: "test").verdicts.first { $0.decision == decision.id }?.overridden ?? false
    }

    // MARK: Layer 1

    func testEveryAgentsOwnVariablesAreRefusedButAPersonsOwnProfileIsNot() {
        for (name, agent) in [("CLAUDECODE", "Claude Code"), ("CLAUDE_CODE_SESSION_ID", "Claude Code"), ("OPENCODE", "OpenCode"),
                              ("OPENCODE_SESSION_ID", "OpenCode"), ("CODEX_THREAD_ID", "Codex"), ("CODEX_SANDBOX", "Codex"),
                              ("OPENCLAW_SHELL", "OpenClaw"), ("OPENCLAW_CLI", "OpenClaw"), ("HERMES_AGENT", "Hermes"),
                              ("HERMES_SESSION_ID", "Hermes"), ("GEMINI_CLI", "Gemini CLI"), ("CURSOR_AGENT", "Cursor's agent"),
                              ("AI_AGENT", "an AI agent"), ("CAMR_MCP", "camr mcp"), ("CAMR_CHECK_RUN", "a decision check CAMR is running")] {
            let refusal = PersonPresence.environmentRefusal(["HOME": "/Users/x", name: ""])
            XCTAssertEqual(refusal?.reason, "it was run from inside \(agent) (\(name) is set)", name)
        }
        // The nearest agent is named, not the outermost one AI_AGENT names.
        XCTAssertEqual(PersonPresence.environmentRefusal(["AI_AGENT": "claude-code_2-1-321_agent", "OPENCODE": "1"])?.reason,
                       "it was run from inside OpenCode (OPENCODE is set)")
        // What a person exports in their own shell profile is not an agent.
        XCTAssertNil(PersonPresence.environmentRefusal(["CLAUDE_CODE_USE_BEDROCK": "1", "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "8000", "HERMES_HOME": "/x",
                                                        "OPENCODE_CONFIG": "/y", "CODEX_HOME": "/z", "TERM": "xterm-256color", "AGENT": "1"]))
    }

    // MARK: Layer 2

    func testAgentsAreKnownByTheirProcessNamesAndArguments() {
        func process(_ name: String, _ path: String = "", _ arguments: [String] = []) -> PersonPresence.ProcessFacts {
            PersonPresence.ProcessFacts(pid: 10, parent: 1, name: name, path: path, arguments: arguments)
        }
        let agents: [(PersonPresence.ProcessFacts, String)] = [
            (process("claude", "/Users/x/Library/Application Support/Claude/claude-code/2.1.321/abc/claude.app/Contents/MacOS/claude", ["claude", "-p"]), "Claude Code"),
            (process("2.1.322", "/Users/x/.local/share/claude/versions/2.1.322", ["claude"]), "Claude Code"),
            (process("node", "/opt/homebrew/bin/node", ["node", "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"]), "Claude Code"),
            (process("Claude", "/Applications/Claude.app/Contents/MacOS/Claude", ["/Applications/Claude.app/Contents/MacOS/Claude"]), "the Claude app"),
            (process("opencode", "/opt/homebrew/Cellar/opencode/2.2.7/bin/opencode", ["opencode", "serve", "--service"]), "OpenCode"),
            (process("codex", "/Users/x/.local/bin/codex", ["codex", "exec", "fix it"]), "Codex"),
            // OpenClaw sets process.title, so its argv says only "openclaw".
            (process("node", "/x/node/bin/node", ["openclaw"]), "OpenClaw"),
            (process("node", "/x/node/bin/node", ["node", "/x/openclaw/node_modules/openclaw/dist/process/supervisor/service-child-relay.js"]), "OpenClaw"),
            (process("python3.14", "/x/venv/bin/python3.14", ["/x/venv/bin/python", "-m", "hermes_cli.main", "gateway", "run"]), "Hermes"),
            (process("node", "/opt/homebrew/bin/node", ["node", "/opt/homebrew/lib/node_modules/@google/gemini-cli/dist/index.js"]), "Gemini CLI"),
            (process("cursor-agent", "/Users/x/.local/bin/cursor-agent", ["cursor-agent"]), "Cursor's agent"),
            (process("camr", "/x/camr", ["camr", "mcp", "/v"]), "camr mcp"),
            (process("camr", "/x/camr", ["camr", "check", "/v"]), "camr check"),
            (process("camr", "/x/camr", ["camr", "hook", "claude"]), "camr hook"),
        ]
        for (facts, agent) in agents { XCTAssertEqual(PersonPresence.agent(facts), agent, facts.arguments.joined(separator: " ")) }
        let people: [PersonPresence.ProcessFacts] = [
            process("zsh", "/bin/zsh", ["-zsh"]), process("login", "/usr/bin/login", ["login", "-pf", "x"]),
            process("Terminal", "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
            process("Code Helper", "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"),
            process("node", "/opt/homebrew/bin/node", ["node", "server.js"]), process("python3", "/usr/bin/python3", ["python3", "manage.py", "runserver"]),
            process("camr", "/x/camr", ["camr", "find", "/v", "fares"]), process("tmux", "/opt/homebrew/bin/tmux", ["tmux"]),
            // A script under a folder that merely contains a name is not that agent.
            process("python3", "/usr/bin/python3", ["python3", "/Users/x/notes/claude-ideas.py"]),
        ]
        for facts in people { XCTAssertNil(PersonPresence.agent(facts), facts.arguments.joined(separator: " ")) }
    }

    func testParentsThatCannotBeReadAreRefusedAndTheTerminalsSessionCounts() throws {
        let parent = getppid()
        // An agent two steps up.
        XCTAssertEqual(PersonPresence.processRefusal { pid in
            pid == parent ? .init(pid: pid, parent: 4242, name: "zsh", arguments: ["-zsh"])
                : pid == 4242 ? .init(pid: 4242, parent: 1, name: "opencode", arguments: ["opencode", "serve"]) : .init(pid: pid, parent: 1, name: "zsh")
        }?.reason, "it was started by OpenCode (opencode serve, process 4242)")
        // A parent that can't be read: fails closed.
        XCTAssertEqual(PersonPresence.processRefusal { pid in
            pid == parent ? .init(pid: pid, parent: 4242, name: "zsh") : pid == 4242 ? nil : .init(pid: pid, parent: 1, name: "zsh")
        }?.reason, "camr could not see which program started it")
        // Clean all the way up: nothing to refuse.
        XCTAssertNil(PersonPresence.processRefusal { .init(pid: $0, parent: 1, name: "zsh") })
        // camr's own parents clean, but its session was started by an agent.
        let leader = getsid(0)
        try XCTSkipIf(leader <= 1 || leader == parent || leader == getpid(), "this test process's session leader is its parent")
        XCTAssertEqual(PersonPresence.processRefusal { pid in
            pid == leader ? .init(pid: pid, parent: 5151, name: "zsh") : pid == 5151 ? .init(pid: 5151, parent: 1, name: "claude", arguments: ["claude"])
                : .init(pid: pid, parent: 1, name: "zsh")
        }?.reason, "its terminal belongs to a session started by Claude Code (claude, process 5151)")
    }

    func testTheRealBinaryUnderAProgramNamedLikeAnAgentIsRefusedWithItsVariablesTakenOut() throws {
        // bash, run through a link named opencode (as ~/.local/bin/claude links to Claude Code), stands in for the agent;
        // every agent variable is taken out of the environment. (A copy of a system binary is killed by code signing.)
        let fake = top.appendingPathComponent("bin/opencode")
        try FileManager.default.createDirectory(at: fake.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: fake.path, withDestinationPath: "/bin/bash")
        let process = Process()
        process.executableURL = fake
        process.arguments = ["-c", "{ sleep 2; echo yes; sleep 1; } | /usr/bin/script -q /dev/null \"$0\" link approve \"$1\" \"$2\"",
                             CAMRBinary.url.path, vault.root.path, code.path]
        process.environment = CAMRBinary.personsEnvironment(state)
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertNotEqual(process.terminationStatus, 0, text)
        XCTAssertTrue(text.contains("Refused because it was started by OpenCode (opencode -c"), text)
        XCTAssertFalse(text.contains("Type yes"), text)
    }

    // MARK: Layer 3

    /// Codes made without real waiting; the waits asked for are recorded.
    private func issue(_ action: String = "x", state: URL? = nil, at now: Date = Date(), waits: inout [TimeInterval]) throws -> PersonCode.Challenge {
        var asked: [TimeInterval] = []
        defer { waits += asked }
        return try PersonCode.issue(action: action, state: state ?? self.state, now: { now }, wait: { asked.append($0) })
    }

    func testACodeIsCheckedOnlyInTheMemoryOfTheRunThatMadeItUsedOnceForTwoMinutesAndThreeTries() throws {
        let now = Date()
        var waits: [TimeInterval] = []
        let challenge = try issue("let a change through", at: now, waits: &waits)
        XCTAssertEqual(challenge.plain.count, 8)
        XCTAssertTrue(challenge.plain.allSatisfy(\.isNumber))
        let wrong = challenge.plain == "00000000" ? "11111111" : "00000000"
        XCTAssertEqual(challenge.verify(wrong, now: now), .wrong(triesLeft: 2))
        XCTAssertEqual(challenge.verify(" \(challenge.plain.prefix(4)) \(challenge.plain.dropFirst(4)) ", now: now), .accepted, "typed as shown, in two groups")
        XCTAssertEqual(challenge.verify(challenge.plain, now: now), .spent, "used once")

        let late = try issue(at: now, waits: &waits)
        XCTAssertEqual(late.verify(late.plain, now: now.addingTimeInterval(121)), .expired)
        XCTAssertEqual(late.verify(late.plain, now: now), .spent, "an expired code is gone")

        let guessed = try issue(at: now, waits: &waits)
        let guess = guessed.plain == "00000000" ? "11111111" : "00000000"
        XCTAssertEqual(guessed.verify(guess, now: now), .wrong(triesLeft: 2))
        XCTAssertEqual(guessed.verify(guess, now: now), .wrong(triesLeft: 1))
        XCTAssertEqual(guessed.verify(guess, now: now), .spent)
        XCTAssertEqual(guessed.verify(guessed.plain, now: now), .spent, "three wrong tries end it")
        PersonCode.record(guessed, state: state)
        XCTAssertEqual(PersonCode.history(state)?.first { $0.id == guessed.id }?.wrong, 3)

        let abandoned = try issue(at: now, waits: &waits)
        abandoned.abandon()
        XCTAssertEqual(abandoned.verify(abandoned.plain, now: now), .spent)
    }

    func testTheRecordCanNeverCheckACodeAndAPlantedOneLetsNothingThrough() throws {
        var waits: [TimeInterval] = []
        let challenge = try issue("let a change through although it breaks decision d1", waits: &waits)
        let file = state.appendingPathComponent("person-codes.json")
        let text = try String(contentsOf: file, encoding: .utf8)
        // Only when, for what and how it ended: no code, no salt, no digest, no hash, nothing to test a guess against.
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        XCTAssertEqual(Set(entries.flatMap(\.keys)), ["id", "action", "issued", "expires", "used", "wrong"])
        for word in ["salt", "digest", "hash", "\"code\"", challenge.plain] { XCTAssertFalse(text.contains(word), word) }
        // Created 0600, in a folder made 0700 here.
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let fresh = top.appendingPathComponent("fresh-state")
        _ = try issue(state: fresh, waits: &waits)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: fresh.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)

        // A program writes a record for a code it knows, in the old shape with a salted hash and with the code itself,
        // and marks the real one used: the code it knows still isn't the code, and the real one still works.
        let known = "12345678"
        let salt = Data(repeating: 7, count: 16)
        let planted: [[String: Any]] = [
            ["id": challenge.id, "action": challenge.action, "issued": "2026-11-15T00:00:00Z", "expires": "2099-01-01T00:00:00Z", "used": true, "wrong": 0,
             "salt": salt.base64EncodedString(), "digest": Data(SHA256.hash(data: salt + Data(known.utf8))).base64EncodedString()],
            ["id": "planted", "action": "x", "issued": "2026-11-15T00:00:00Z", "expires": "2099-01-01T00:00:00Z", "used": false, "wrong": 0,
             "code": known],
        ]
        try JSONSerialization.data(withJSONObject: planted).write(to: file)
        if challenge.plain != known { XCTAssertEqual(challenge.verify(known), .wrong(triesLeft: 2)) }
        XCTAssertEqual(challenge.verify(challenge.plain), .accepted, "the file never decides")
    }

    func testMakingACodeIsSlowedAndAMissingRecordSlowsItMore() throws {
        let now = Date()
        var waits: [TimeInterval] = []
        // No record (setUp's empty one taken away): can't tell how many were made, so the long wait.
        try FileManager.default.removeItem(at: state.appendingPathComponent("person-codes.json"))
        _ = try issue(at: now, waits: &waits)
        XCTAssertEqual(waits, [PersonCode.unknownHistoryDelay])
        // A readable record: the short wait.
        _ = try issue(at: now, waits: &waits)
        XCTAssertEqual(waits.last, PersonCode.issueDelay)
        // Unreadable (a program wrote rubbish): the long wait again, never an empty history.
        try "not json".write(to: state.appendingPathComponent("person-codes.json"), atomically: true, encoding: .utf8)
        _ = try issue(at: now, waits: &waits)
        XCTAssertEqual(waits.last, PersonCode.unknownHistoryDelay)
        XCTAssertEqual(PersonCode.issueDelay, 2)
        XCTAssertEqual(PersonCode.unknownHistoryDelay, 20)
        // At most six in ten minutes, counted from the record.
        let crowded = top.appendingPathComponent("crowded")
        for _ in 0..<PersonCode.perTenMinutes { _ = try issue(state: crowded, at: now, waits: &waits) }
        XCTAssertThrowsError(try issue(state: crowded, at: now.addingTimeInterval(60), waits: &waits))
        XCTAssertNoThrow(try issue(state: crowded, at: now.addingTimeInterval(601), waits: &waits))
    }

    func testTheCodeGoesOnlyToANotificationAndNothingListensForIt() throws {
        var waits: [TimeInterval] = []
        let challenge = try issue("confirm the check for decision d1", waits: &waits)
        // The test hook exists in debug builds only (this one); the release binary has no such branch.
        let hook = top.appendingPathComponent("hook")
        XCTAssertEqual(PersonCode.show(challenge, environment: ["CAMR_TEST_CODE_FILE": hook.path]), .testHook)
        XCTAssertEqual(try String(contentsOf: hook, encoding: .utf8), challenge.plain)
        XCTAssertEqual(PersonCode.grouped("12345678"), "1234 5678")
        // No message port carries a code any more: under the names the app used to register, for this state folder and
        // the person's own, nobody is listening (the app registers none; camr sends to none).
        for folder in [state, CAMRPlaces.stateFolder] {
            let path = folder.standardizedFileURL.resolvingSymlinksInPath().path
            let hash = SHA256.hash(data: Data(path.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
            XCTAssertNil(CFMessagePortCreateRemote(nil, "app.camr.mac.code.\(getuid()).\(hash)" as CFString))
        }
        // What goes into the notification's script can't break out of its string or carry control characters.
        XCTAssertEqual(PersonCode.appleScriptString("a \"b\" \\ c\u{1b}[2J\u{202e}"), "\"a \\\"b\\\" \\\\ c[2J\"")
        // A decision check's command is never taken for the person, nor is anything camr mcp starts.
        let run = DecisionChecks.run(try DecisionCheck.parse("/usr/bin/printenv CAMR_CHECK_RUN", by: "you"), in: code, added: [:])
        XCTAssertEqual(run.status, .passed, run.output)
        XCTAssertEqual(run.output.trimmingCharacters(in: .whitespacesAndNewlines), "1")
    }

    // MARK: The real binary, end to end

    func testAProgramSetOnItGetsPastTheTerminalForALinkButNeverPastTheCode() throws {
        let decision = try heldDecision()
        let path = vault.root.path
        // The documented way round layers 1 and 2: agent variables taken out, detached from the tree, yes typed into a
        // pseudo-terminal. A linked folder is approved that way (no code is asked for it): the honest limit.
        let linkState = top.appendingPathComponent("link-state")
        try FileManager.default.createDirectory(at: linkState, withIntermediateDirectories: true)
        let linked = try CAMRBinary.inTerminal(["link", path, top.appendingPathComponent("elsewhere").path], state: linkState, answer: "yes")
        XCTAssertEqual(linked.status, 0, linked.out)
        XCTAssertTrue(linked.out.contains("approved on this Mac"), linked.out)
        XCTAssertFalse(linked.out.contains("Type the code"), linked.out)

        // The override that would defeat the gate: no code, a wrong code three times, then a code from another run.
        let walked = try CAMRBinary.inTerminal(["decision", "override", path, decision.id], state: state, answer: "yes", code: .none)
        XCTAssertEqual(walked.status, 1, walked.out)
        XCTAssertTrue(walked.out.contains("CAMR showed an 8-digit code in the test's code file. It is never printed here"), walked.out)
        XCTAssertTrue(walked.out.contains("no code was typed: nothing was allowed"), walked.out)
        XCTAssertFalse(walked.out.contains("Type yes"), "the yes comes only after the code")
        XCTAssertFalse(overridden(decision))
        XCTAssertTrue(PersonCode.history(state)?.allSatisfy(\.used) ?? false, "a code nobody typed is ended on file")

        // A program plants a record for a code it knows, with the salted hash the first build kept and with the code
        // itself, then types that code three times: nothing written can make a code valid.
        let salt = Data(repeating: 7, count: 16)
        let planted: [[String: Any]] = [["id": "planted", "action": "let a change through although it breaks decision \(decision.id)",
                                         "issued": ISO8601DateFormatter().string(from: Date()), "expires": "2099-01-01T00:00:00Z", "used": false, "wrong": 0,
                                         "salt": salt.base64EncodedString(), "digest": Data(SHA256.hash(data: salt + Data("12345678".utf8))).base64EncodedString(),
                                         "code": "12345678"]]
        try JSONSerialization.data(withJSONObject: planted).write(to: state.appendingPathComponent("person-codes.json"))
        let guessed = try CAMRBinary.inTerminal(["decision", "override", path, decision.id], state: state, answer: "yes", code: .typed("12345678"))
        XCTAssertEqual(guessed.status, 1, guessed.out)
        XCTAssertTrue(guessed.out.contains("That isn't the code. 2 tries left."), guessed.out)
        XCTAssertTrue(guessed.out.contains("That isn't the code. 1 try left."), guessed.out)
        XCTAssertTrue(guessed.out.contains("that code can't be used any more: nothing was allowed"), guessed.out)
        XCTAssertFalse(overridden(decision))

        // Confirming and clearing a check need the code too; without it nothing changes.
        let proposed = try DecisionCheck.parse("python3 -c 'print(1)'", by: "claude-code")
        let other = try Ledger(vault: vault).commit(.decision, "matcher stays small", files: ["shop/payments/matcher.py"], author: "t", client: "t")
        try DecisionChecks.propose(proposed, for: other.id, vault: vault)
        let confirm = try CAMRBinary.inTerminal(["decision", "check", path, other.id, "--confirm"], state: state, answer: "yes", code: .none)
        XCTAssertEqual(confirm.status, 1, confirm.out)
        XCTAssertNil(DecisionChecks.confirmed(vault)[other.id])
        let clear = try CAMRBinary.inTerminal(["decision", "check", path, decision.id, "--clear"], state: state, answer: "yes", code: .none)
        XCTAssertEqual(clear.status, 1, clear.out)
        XCTAssertNotNil(DecisionChecks.confirmed(vault)[decision.id])
        // --set in a terminal confirms only with the code; without it the check is kept as proposed.
        let set = try CAMRBinary.inTerminal(["decision", "check", path, other.id, "--set", "forbid: amount"], state: state, answer: "yes", code: .none)
        XCTAssertEqual(set.status, 0, set.out)
        XCTAssertTrue(set.out.contains("check proposed, not run: forbid: amount"), set.out)
        XCTAssertNil(DecisionChecks.confirmed(vault)[other.id])

        // With an agent's variable still set, even a pseudo-terminal detached from the tree is refused before any code
        // is made.
        let codes = state.appendingPathComponent("person-codes.json")
        let before = try String(contentsOf: codes, encoding: .utf8)
        let marked = try CAMRBinary.inTerminal(["decision", "override", path, decision.id], state: state, answer: "yes", code: .shown,
                                                 environment: ["CLAUDECODE": "1"])
        XCTAssertEqual(marked.status, 1, marked.out)
        XCTAssertTrue(marked.out.contains("Refused because it was run from inside Claude Code (CLAUDECODE is set)."), marked.out)
        XCTAssertEqual(try String(contentsOf: codes, encoding: .utf8), before, "no code was made")
        XCTAssertFalse(overridden(decision))
    }

    func testWithTheCodeShownOutsideTheTerminalThePersonOverridesConfirmsAndClears() throws {
        let decision = try heldDecision()
        let path = vault.root.path
        let through = try CAMRBinary.inTerminal(["decision", "override", path, decision.id], state: state, answer: "yes", code: .shown)
        XCTAssertEqual(through.status, 0, through.out)
        XCTAssertTrue(through.out.contains("Type the code (valid 2 minutes): "), through.out)
        XCTAssertTrue(through.out.contains("let through: this exact change, for \(decision.id)."), through.out)
        XCTAssertTrue(overridden(decision))
        XCTAssertEqual(Gate.check(vault: vault, by: "test").exitCode, 0)
        // The right code, then anything but yes: nothing.
        try (phoneFallback + "# more\n").write(to: matcher, atomically: true, encoding: .utf8)
        let no = try CAMRBinary.inTerminal(["decision", "override", path, decision.id], state: state, answer: "no", code: .shown)
        XCTAssertEqual(no.status, 1, no.out)
        XCTAssertFalse(overridden(decision))

        let other = try Ledger(vault: vault).commit(.decision, "matcher stays small", files: ["shop/payments/matcher.py"], author: "t", client: "t")
        try DecisionChecks.propose(try DecisionCheck.parse("forbid: amount", by: "claude-code"), for: other.id, vault: vault)
        let confirm = try CAMRBinary.inTerminal(["decision", "check", path, other.id, "--confirm"], state: state, answer: "yes", code: .shown)
        XCTAssertEqual(confirm.status, 0, confirm.out)
        XCTAssertTrue(confirm.out.contains("Proposed by claude-code, not by you."), confirm.out)
        XCTAssertEqual(DecisionChecks.confirmed(vault)[other.id]?.shown, "forbid: amount")
        let clear = try CAMRBinary.inTerminal(["decision", "check", path, other.id, "--clear"], state: state, answer: "yes", code: .shown)
        XCTAssertEqual(clear.status, 0, clear.out)
        XCTAssertNil(DecisionChecks.confirmed(vault)[other.id])
        // Each code was used once and is spent on file.
        XCTAssertTrue(PersonCode.history(state)?.allSatisfy(\.used) ?? false)
    }
}
