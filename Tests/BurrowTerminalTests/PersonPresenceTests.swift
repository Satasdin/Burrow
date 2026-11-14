@testable import BurrowCore
@testable import BurrowTools
import Darwin
import XCTest

/// D-113: a connected agent with a shell can make a pseudo-terminal and type yes, so a terminal and a yes no longer
/// count as the person on their own. Burrow refuses an agent's environment (layer 1) and an agent's process tree
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
    }

    override func tearDown() { try? FileManager.default.removeItem(at: top) }

    /// A decision with a confirmed check, and a change that breaks it: `burrow check` exits 3.
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
                              ("AI_AGENT", "an AI agent"), ("BURROW_MCP", "burrow mcp"), ("BURROW_CHECK_RUN", "a decision check Burrow is running")] {
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
            (process("burrow", "/x/burrow", ["burrow", "mcp", "/v"]), "burrow mcp"),
            (process("burrow", "/x/burrow", ["burrow", "check", "/v"]), "burrow check"),
            (process("burrow", "/x/burrow", ["burrow", "hook", "claude"]), "burrow hook"),
        ]
        for (facts, agent) in agents { XCTAssertEqual(PersonPresence.agent(facts), agent, facts.arguments.joined(separator: " ")) }
        let people: [PersonPresence.ProcessFacts] = [
            process("zsh", "/bin/zsh", ["-zsh"]), process("login", "/usr/bin/login", ["login", "-pf", "x"]),
            process("Terminal", "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"),
            process("Code Helper", "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"),
            process("node", "/opt/homebrew/bin/node", ["node", "server.js"]), process("python3", "/usr/bin/python3", ["python3", "manage.py", "runserver"]),
            process("burrow", "/x/burrow", ["burrow", "find", "/v", "fares"]), process("tmux", "/opt/homebrew/bin/tmux", ["tmux"]),
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
        }?.reason, "burrow could not see which program started it")
        // Clean all the way up: nothing to refuse.
        XCTAssertNil(PersonPresence.processRefusal { .init(pid: $0, parent: 1, name: "zsh") })
        // burrow's own parents clean, but its session was started by an agent.
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
                             BurrowBinary.url.path, vault.root.path, code.path]
        process.environment = BurrowBinary.personsEnvironment(state)
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

    func testACodeIsKeptHashedUsedOnceEndsAfterTwoMinutesOrThreeWrongTries() throws {
        let now = Date()
        let issued = try PersonCode.issue(action: "let a change through", state: state, now: now)
        XCTAssertEqual(issued.plain.count, 6)
        XCTAssertTrue(issued.plain.allSatisfy(\.isNumber))
        let file = try String(contentsOf: state.appendingPathComponent("person-codes.json"), encoding: .utf8)
        XCTAssertFalse(file.contains("\"\(issued.plain)\""), "only a salted hash is kept")
        XCTAssertFalse(file.contains(issued.plain), file)
        let attributes = try FileManager.default.attributesOfItem(atPath: state.appendingPathComponent("person-codes.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let wrong = issued.plain == "000000" ? "111111" : "000000"
        XCTAssertEqual(PersonCode.redeem(wrong, issued, state: state, now: now), .wrong(triesLeft: 2))
        XCTAssertEqual(PersonCode.redeem(" \(issued.plain) ", issued, state: state, now: now), .accepted)
        XCTAssertEqual(PersonCode.redeem(issued.plain, issued, state: state, now: now), .spent, "used once")

        let late = try PersonCode.issue(action: "x", state: state, now: now)
        XCTAssertEqual(PersonCode.redeem(late.plain, late, state: state, now: now.addingTimeInterval(121)), .expired)
        XCTAssertEqual(PersonCode.redeem(late.plain, late, state: state, now: now), .spent, "an expired code is gone")

        let guessed = try PersonCode.issue(action: "x", state: state, now: now)
        let guess = guessed.plain == "000000" ? "111111" : "000000"
        XCTAssertEqual(PersonCode.redeem(guess, guessed, state: state, now: now), .wrong(triesLeft: 2))
        XCTAssertEqual(PersonCode.redeem(guess, guessed, state: state, now: now), .wrong(triesLeft: 1))
        XCTAssertEqual(PersonCode.redeem(guess, guessed, state: state, now: now), .spent)
        XCTAssertEqual(PersonCode.redeem(guessed.plain, guessed, state: state, now: now), .spent, "three wrong tries end it")

        // The file can only make it stricter: a record taken away, or rewritten to another code's hash, lets nothing in.
        let forged = try PersonCode.issue(action: "x", state: state, now: now)
        var entries = PersonCode.load(state)
        let other = PersonCode.digest("123456", salt: forged.salt).base64EncodedString()
        entries[entries.firstIndex { $0.id == forged.id }!].digest = other
        try PersonCode.save(entries, state)
        XCTAssertEqual(PersonCode.redeem("123456", forged, state: state, now: now), .spent)
        XCTAssertEqual(PersonCode.redeem(forged.plain, forged, state: state, now: now), .spent)

        // At most six in ten minutes.
        let crowded = top.appendingPathComponent("crowded")
        for _ in 0..<PersonCode.perTenMinutes { _ = try PersonCode.issue(action: "x", state: crowded, now: now) }
        XCTAssertThrowsError(try PersonCode.issue(action: "x", state: crowded, now: now.addingTimeInterval(60)))
        XCTAssertNoThrow(try PersonCode.issue(action: "x", state: crowded, now: now.addingTimeInterval(601)))
    }

    func testTheCodeGoesOnlyOutsideTheTerminal() throws {
        let issued = try PersonCode.issue(action: "confirm the check for decision d1", state: state)
        // The test hook exists in debug builds only (this one); the release binary has no such branch.
        let hook = top.appendingPathComponent("hook")
        XCTAssertEqual(PersonCode.show(issued, state: state, environment: ["BURROW_TEST_CODE_FILE": hook.path]), .testHook)
        XCTAssertEqual(try String(contentsOf: hook, encoding: .utf8), issued.plain)
        // The app is reached by a port named for its state folder, so a test or demo state never reaches the person's app.
        XCTAssertNotEqual(PersonCodeInbox.portName(state: state), PersonCodeInbox.portName(state: top.appendingPathComponent("other")))
        XCTAssertTrue(PersonCodeInbox.portName(state: state).hasPrefix("app.burrow.mac.code.\(getuid())."))
        // What goes into the notification's script can't break out of its string or carry control characters.
        XCTAssertEqual(PersonCode.appleScriptString("a \"b\" \\ c\u{1b}[2J\u{202e}"), "\"a \\\"b\\\" \\\\ c[2J\"")
        // A decision check's command is never taken for the person, nor is anything burrow mcp starts.
        let run = DecisionChecks.run(try DecisionCheck.parse("/usr/bin/printenv BURROW_CHECK_RUN", by: "you"), in: code, added: [:])
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
        let linked = try BurrowBinary.inTerminal(["link", path, top.appendingPathComponent("elsewhere").path], state: linkState, answer: "yes")
        XCTAssertEqual(linked.status, 0, linked.out)
        XCTAssertTrue(linked.out.contains("approved on this Mac"), linked.out)
        XCTAssertFalse(linked.out.contains("Type the code"), linked.out)

        // The override that would defeat the gate: no code, a wrong code three times, then a code from another run.
        let walked = try BurrowBinary.inTerminal(["decision", "override", path, decision.id], state: state, answer: "yes", code: .none)
        XCTAssertEqual(walked.status, 1, walked.out)
        XCTAssertTrue(walked.out.contains("Burrow showed a 6-digit code in the test's code file. It is never printed here"), walked.out)
        XCTAssertTrue(walked.out.contains("no code was typed: nothing was allowed"), walked.out)
        XCTAssertFalse(walked.out.contains("Type yes"), "the yes comes only after the code")
        XCTAssertFalse(overridden(decision))
        XCTAssertTrue(PersonCode.load(state).allSatisfy(\.used), "a code nobody typed is ended on file")

        let guessed = try BurrowBinary.inTerminal(["decision", "override", path, decision.id], state: state, answer: "yes", code: .typed("123456"))
        XCTAssertEqual(guessed.status, 1, guessed.out)
        XCTAssertTrue(guessed.out.contains("That isn't the code. 2 tries left."), guessed.out)
        XCTAssertTrue(guessed.out.contains("That isn't the code. 1 try left."), guessed.out)
        XCTAssertTrue(guessed.out.contains("that code can't be used any more: nothing was allowed"), guessed.out)
        XCTAssertFalse(overridden(decision))

        // Confirming and clearing a check need the code too; without it nothing changes.
        let proposed = try DecisionCheck.parse("python3 -c 'print(1)'", by: "claude-code")
        let other = try Ledger(vault: vault).commit(.decision, "matcher stays small", files: ["shop/payments/matcher.py"], author: "t", client: "t")
        try DecisionChecks.propose(proposed, for: other.id, vault: vault)
        let confirm = try BurrowBinary.inTerminal(["decision", "check", path, other.id, "--confirm"], state: state, answer: "yes", code: .none)
        XCTAssertEqual(confirm.status, 1, confirm.out)
        XCTAssertNil(DecisionChecks.confirmed(vault)[other.id])
        let clear = try BurrowBinary.inTerminal(["decision", "check", path, decision.id, "--clear"], state: state, answer: "yes", code: .none)
        XCTAssertEqual(clear.status, 1, clear.out)
        XCTAssertNotNil(DecisionChecks.confirmed(vault)[decision.id])
        // --set in a terminal confirms only with the code; without it the check is kept as proposed.
        let set = try BurrowBinary.inTerminal(["decision", "check", path, other.id, "--set", "forbid: amount"], state: state, answer: "yes", code: .none)
        XCTAssertEqual(set.status, 0, set.out)
        XCTAssertTrue(set.out.contains("check proposed, not run: forbid: amount"), set.out)
        XCTAssertNil(DecisionChecks.confirmed(vault)[other.id])

        // With an agent's variable still set, even a pseudo-terminal detached from the tree is refused before any code
        // is made.
        let codes = state.appendingPathComponent("person-codes.json")
        let before = try String(contentsOf: codes, encoding: .utf8)
        let marked = try BurrowBinary.inTerminal(["decision", "override", path, decision.id], state: state, answer: "yes", code: .shown,
                                                 environment: ["CLAUDECODE": "1"])
        XCTAssertEqual(marked.status, 1, marked.out)
        XCTAssertTrue(marked.out.contains("Refused because it was run from inside Claude Code (CLAUDECODE is set)."), marked.out)
        XCTAssertEqual(try String(contentsOf: codes, encoding: .utf8), before, "no code was made")
        XCTAssertFalse(overridden(decision))
    }

    func testWithTheCodeShownOutsideTheTerminalThePersonOverridesConfirmsAndClears() throws {
        let decision = try heldDecision()
        let path = vault.root.path
        let through = try BurrowBinary.inTerminal(["decision", "override", path, decision.id], state: state, answer: "yes", code: .shown)
        XCTAssertEqual(through.status, 0, through.out)
        XCTAssertTrue(through.out.contains("Type the code (valid 2 minutes): "), through.out)
        XCTAssertTrue(through.out.contains("let through: this exact change, for \(decision.id)."), through.out)
        XCTAssertTrue(overridden(decision))
        XCTAssertEqual(Gate.check(vault: vault, by: "test").exitCode, 0)
        // The right code, then anything but yes: nothing.
        try (phoneFallback + "# more\n").write(to: matcher, atomically: true, encoding: .utf8)
        let no = try BurrowBinary.inTerminal(["decision", "override", path, decision.id], state: state, answer: "no", code: .shown)
        XCTAssertEqual(no.status, 1, no.out)
        XCTAssertFalse(overridden(decision))

        let other = try Ledger(vault: vault).commit(.decision, "matcher stays small", files: ["shop/payments/matcher.py"], author: "t", client: "t")
        try DecisionChecks.propose(try DecisionCheck.parse("forbid: amount", by: "claude-code"), for: other.id, vault: vault)
        let confirm = try BurrowBinary.inTerminal(["decision", "check", path, other.id, "--confirm"], state: state, answer: "yes", code: .shown)
        XCTAssertEqual(confirm.status, 0, confirm.out)
        XCTAssertTrue(confirm.out.contains("Proposed by claude-code, not by you."), confirm.out)
        XCTAssertEqual(DecisionChecks.confirmed(vault)[other.id]?.shown, "forbid: amount")
        let clear = try BurrowBinary.inTerminal(["decision", "check", path, other.id, "--clear"], state: state, answer: "yes", code: .shown)
        XCTAssertEqual(clear.status, 0, clear.out)
        XCTAssertNil(DecisionChecks.confirmed(vault)[other.id])
        // Each code was used once and is spent on file.
        XCTAssertTrue(PersonCode.load(state).allSatisfy(\.used))
    }
}
