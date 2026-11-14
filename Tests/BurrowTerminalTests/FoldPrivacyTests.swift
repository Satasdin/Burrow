@testable import BurrowCore
@testable import BurrowMCP
@testable import BurrowTools
import XCTest

/// D-105: secrets never kept in a fold (or a handoff), folds kept in Burrow's own folder rather than the vault, a tool a
/// connection is not shown refused by name, and a fold's original messages given only to the program and session that
/// wrote them.
final class FoldPrivacyTests: XCTestCase {
    private var top: URL!
    /// Kept for the length of a test: a fixture removes its folder when it goes.
    private var fixtures: [VaultFixture] = []

    override func setUp() {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("fold-privacy-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: top, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: top) }

    // Made-up secrets, in the shapes real ones have.
    private let openAI = "sk-test-4fJ9qLw2Zx7Rt5Yb8Nc3Vd6Km1Hp0Sa"
    private let bearer = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ3YW5qaXJ1In0.c2lnbmF0dXJlLXNpZ25hdHVyZQ"
    private let github = "ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"

    private func line(_ object: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    private func user(_ uuid: String, _ text: String) -> String {
        line(["type": "user", "uuid": uuid, "message": ["role": "user", "content": text]])
    }

    private func assistant(_ uuid: String, _ parts: [[String: Any]]) -> String {
        line(["type": "assistant", "uuid": uuid, "message": ["role": "assistant", "model": "claude-haiku-5-5", "content": parts]])
    }

    private func result(_ uuid: String, _ text: String, failed: Bool = false) -> String {
        line(["type": "user", "uuid": uuid, "message": ["role": "user", "content": [["type": "tool_result", "content": text, "is_error": failed]]]])
    }

    /// A stretch where the person pastes a key, a command sends a bearer header, and the run prints the key back.
    private var leakyStretch: String {
        [
            user("bbbb0001-x", "My key is OPENAI_API_KEY=\(openAI) and the deploy token is \(github). Keep burst at exactly 37 tokens."),
            assistant("bbbb0002-x", [
                ["type": "tool_use", "name": "Bash", "input": ["command": "curl -H \"Authorization: Bearer \(bearer)\" https://api.example.com/v1/limits"]],
                ["type": "tool_use", "name": "Bash", "input": ["command": "psql postgres://app:hunter2secret@db.internal:5432/limits -c 'select 1'"]],
            ]),
            result("bbbb0003-x", "openai.AuthenticationError: Incorrect API key provided: \(openAI). You can find your API key at https://platform.openai.com.\nRuntimeError: clock skew 812 ms exceeds tolerance on node edge-ke-07", failed: true),
            assistant("bbbb0004-x", [["type": "text", "text": "The key \(openAI) was rejected, so I chose to read it from the keychain instead of the environment."],
                                     ["type": "tool_use", "name": "TodoWrite", "input": ["todos": [["content": "Rotate \(github)", "status": "pending"]]]]]),
        ].joined(separator: "\n")
    }

    private func assertClean(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        for secret in [openAI, bearer, github, "hunter2secret", "4fJ9qLw2Zx7Rt5"] {
            XCTAssertFalse(text.contains(secret), "\(secret) kept in:\n\(text)", file: file, line: line)
        }
    }

    // MARK: Secrets

    func testSecretsAreTakenOutAndEverythingElseStaysAsWritten() {
        let cases: [(String, String)] = [
            ("export OPENAI_API_KEY=\(openAI)", "export OPENAI_API_KEY=[secret removed]"),
            ("DB_PASSWORD=\"correct horse\" ./run", "DB_PASSWORD=[secret removed] ./run"),
            ("curl -H 'Authorization: Bearer \(bearer)' x", "curl -H 'Authorization: Bearer [secret removed]' x"),
            ("Authorization: Basic YWxhZGRpbjpvcGVuc2VzYW1l", "Authorization: Basic [secret removed]"),
            ("git clone https://wanjiru:\(github)@github.com/x/y", "git clone https://wanjiru:[secret removed]@github.com/x/y"),
            ("redis://default:s3cretpass@cache:6379/0", "redis://default:[secret removed]@cache:6379/0"),
            ("{\"password\": \"hunter2\", \"user\": \"omar\"}", "{\"password\": [secret removed], \"user\": \"omar\"}"),
            ("client_secret: 9f8e7d6c5b4a39281706", "client_secret: [secret removed]"),
            ("mysql --password hunter2 -u root", "mysql --password [secret removed] -u root"),
            ("token xoxb-1234567890-abcdefghij posted", "token [secret removed] posted"),
            ("aws AKIAIOSFODNN7EXAMPLE configured", "aws [secret removed] configured"),
            ("jwt \(bearer)", "jwt [secret removed]"),
            ("https://x.test/cb?access_token=abc123def456&state=7", "https://x.test/cb?access_token=[secret removed]&state=7"),
            ("-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\n-----END OPENSSH PRIVATE KEY-----\nafter", "[secret removed]\nafter"),
        ]
        for (given, expected) in cases {
            XCTAssertEqual(Secrets.redacted(given), expected, given)
            XCTAssertEqual(Secrets.redacted(expected), expected, "taking secrets out twice changes nothing: \(expected)")
        }
        // What a fold exists to keep word for word stays exactly as printed (D-102).
        for kept in [
            "RuntimeError: clock skew 812 ms exceeds tolerance on node edge-ke-07",
            "KeyError: 'tenant_id'",
            "SyntaxError: Unexpected token ':'",
            "jwt.exceptions.InvalidTokenError: Invalid token: expired",
            "max_tokens=4096 num_tokens: 128",
            "key `tenant:{tenant_id}:route:{route}`",
            "PWD=/Users/wanjiru/limiter",
            "fetch https://example.com:8080/path failed",
            "Burst is exactly 37 tokens, refill every 450 ms",
            "/p/limiter.py:41",
        ] {
            XCTAssertEqual(Secrets.redacted(kept), kept)
        }
    }

    func testAFoldKeepsNoSecretInAnyFieldAndKeepsTheErrorLinesValue() throws {
        let store = FoldStore(folder: top.appendingPathComponent("folds"))
        let fold = try XCTUnwrap(try store.fold(transcript: leakyStretch, path: "/t/sess-9.jsonl", session: "sess-9", event: "PreCompact"))
        let saved = try String(contentsOf: top.appendingPathComponent("folds/sess-9.json"), encoding: .utf8)
        assertClean(saved)
        assertClean(fold.shown())
        XCTAssertTrue(saved.contains("OPENAI_API_KEY=[secret removed]"), saved)
        XCTAssertTrue(saved.contains("Authorization: Bearer [secret removed]"), saved)
        XCTAssertTrue(saved.contains("postgres://app:[secret removed]@db.internal:5432/limits"), saved)
        XCTAssertTrue(saved.contains("Rotate [secret removed]"), saved)
        // The error lines keep every word that is not the secret.
        XCTAssertTrue(fold.errors.contains("openai.AuthenticationError: Incorrect API key provided: [secret removed]. You can find your API key at https://platform.openai.com."), "\(fold.errors)")
        XCTAssertTrue(fold.errors.contains("RuntimeError: clock skew 812 ms exceeds tolerance on node edge-ke-07"), "\(fold.errors)")
        XCTAssertTrue(fold.asked.first?.text.contains("Keep burst at exactly 37 tokens.") == true)
        XCTAssertEqual(fold.client, "claude-code")
    }

    func testAFoldKeptWithASecretIsShownWithoutIt() throws {
        // A fold written before D-105, or planted: the secret is taken out again wherever it is shown.
        var fold = try XCTUnwrap(Fold.make(transcript: user("cccc0001-x", "hello there, carry on"), after: nil, session: "old-1",
                                           number: 1, event: "PreCompact", path: "/t/old-1.jsonl"))
        fold.asked = [Fold.Quote(ref: "cccc0001", text: "use OPENAI_API_KEY=\(openAI)")]
        fold.errors = ["HTTP 401 for Authorization: Bearer \(bearer)"]
        let folder = top.appendingPathComponent("folds")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([fold]).write(to: folder.appendingPathComponent("old-1.json"))
        let store = FoldStore(folder: folder)
        assertClean(Folds.handBack(store.folds(session: "old-1")))
        assertClean(Folds.recall(store, id: "old-1-1", find: nil, full: false).text)
        assertClean(Folds.recall(store, id: nil, find: "401", full: false).text)
        assertClean(Folds.recall(store, id: nil, find: nil, full: false).text)
    }

    // MARK: Where folds live

    func testFoldsLiveInBurrowsOwnFolderNotInTheVault() async throws {
        let fixture = try VaultFixture()
        let vault = try await fixture.opened()
        let store = FoldStore(vault: vault)
        try store.fold(transcript: leakyStretch, path: "/t/s.jsonl", session: "sess-v", event: "SessionEnd")
        XCTAssertTrue(store.folder.path.hasPrefix(vault.stateFolder.path + "/folds/vault-"), store.folder.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.store.appendingPathComponent("folds").path))
        XCTAssertEqual(store.folds(session: "sess-v").count, 1)
        let rights = try FileManager.default.attributesOfItem(atPath: store.folder.path)[.posixPermissions] as? Int
        XCTAssertEqual(rights, 0o700)
        // Another vault with the same folder name has its own folds.
        let twin = try Vault(project: fixture.top.appendingPathComponent("elsewhere/vault"), everything: true)
        twin.stateFolder = vault.stateFolder
        XCTAssertNotEqual(FoldStore(vault: twin).folder, store.folder)
        XCTAssertTrue(FoldStore(vault: twin).all().isEmpty)
        // A fold planted in the vault's own store is never read.
        let planted = vault.store.appendingPathComponent("folds")
        try FileManager.default.createDirectory(at: planted, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: store.folder.appendingPathComponent("sess-v.json"), to: planted.appendingPathComponent("planted.json"))
        XCTAssertEqual(FoldStore(vault: vault).all().map(\.session), ["sess-v"])
    }

    // MARK: Tools a connection is not shown

    private func server(_ set: ToolSet, client: String = "n8n", session: String? = nil) async throws -> (MCPServer, VaultTools) {
        let fixture = try VaultFixture()
        fixtures.append(fixture)
        let vault = try await fixture.opened()
        try FoldStore(vault: vault).fold(transcript: leakyStretch, path: "/nowhere/sess-9.jsonl", session: "sess-9", event: "PreCompact")
        let tools = VaultTools(vault: vault, embedder: nil) { _ in FakeAnswerer() }
        tools.claudeCodeSession = session
        let server = MCPServer(tools: tools, keepsSessions: false)
        server.toolSet = set
        _ = await server.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"\#(client)","version":"1"}}}"#)
        return (server, tools)
    }

    /// The tool's text, or the error's message.
    private func call(_ server: MCPServer, _ name: String, _ arguments: String = "{}") async throws -> (text: String, refused: Bool) {
        let line = await server.handle(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#)
        let reply = try JSONSerialization.jsonObject(with: XCTUnwrap(line).data(using: .utf8)!) as! [String: Any]
        if let error = reply["error"] as? [String: Any] { return (error["message"] as? String ?? "", true) }
        let content = (reply["result"] as? [String: Any])?["content"] as? [[String: Any]]
        return (try XCTUnwrap(content?.first?["text"] as? String, "\(reply)"), false)
    }

    func testAToolTheConnectionIsNotShownIsRefusedByName() async throws {
        let (door, _) = try await server(.door)
        for hidden in ["burrow_recall", "burrow_revert", "burrow_log", "vault_session_list", "vault_remember", "vault_ask"] {
            let answer = try await call(door, hidden)
            XCTAssertTrue(answer.refused, "\(hidden): \(answer.text)")
            XCTAssertTrue(answer.text.contains("is not one of the tools this connection is offered"), answer.text)
        }
        // The older names of the shown search and read are the same tools, and still answer.
        let old = try await call(door, "vault_search", #"{"query":"retry a failed charge"}"#)
        XCTAssertFalse(old.refused, old.text)
        XCTAssertTrue(old.text.contains("Retry"), old.text)
        let read = try await call(door, "vault_read", #"{"path":"Decisions/Retry.md"}"#)
        XCTAssertFalse(read.refused, read.text)
        // A name Burrow does not have is still "Unknown tool".
        let unknown = try await call(door, "burrow_nothing")
        XCTAssertEqual(unknown.text, "Unknown tool: burrow_nothing")

        // The classic list, for runs that must match earlier ones, reaches none of the Ledger's tools.
        let (classic, _) = try await server(.classic)
        let commit = try await call(classic, "burrow_commit", #"{"kind":"fact","message":"x"}"#)
        XCTAssertTrue(commit.refused, commit.text)
        let sessions = try await call(classic, "vault_session_list")
        XCTAssertFalse(sessions.refused, sessions.text)

        // --tools full offers every tool.
        let (full, _) = try await server(.full)
        let log = try await call(full, "burrow_log"), listed = try await call(full, "vault_session_list")
        XCTAssertFalse(log.refused, log.text)
        XCTAssertFalse(listed.refused, listed.text)
    }

    func testTheStatelessEraRefusesAToolNotShownToo() async throws {
        let (door, _) = try await server(.door)
        let line = await door.handle(DualEraMCPTests.modern(5, "tools/call", #""name":"burrow_recall","arguments":{"full":true,"fold":"sess-9-1"}"#, client: "claude-code"))
        let reply = try JSONSerialization.jsonObject(with: XCTUnwrap(line).data(using: .utf8)!) as! [String: Any]
        let message = (reply["error"] as? [String: Any])?["message"] as? String ?? ""
        XCTAssertTrue(message.contains("burrow_recall is not one of the tools this connection is offered"), "\(reply)")
    }

    // MARK: A fold's original messages

    func testOnlyTheProgramAndSessionThatWroteAFoldGetItsOriginals() async throws {
        // n8n with every tool listed: the folds, yes; their original messages, no.
        let (n8n, _) = try await server(.full, client: "n8n")
        let summary = try await call(n8n, "burrow_recall", #"{"fold":"sess-9-1"}"#)
        XCTAssertFalse(summary.refused)
        XCTAssertTrue(summary.text.contains("clock skew 812 ms"), summary.text)
        assertClean(summary.text)
        let full = try await call(n8n, "burrow_recall", #"{"fold":"sess-9-1","full":"yes"}"#)
        XCTAssertEqual(full.text, "The original messages of fold sess-9-1 are given only to the program that wrote them, claude-code in session sess-9, and this connection is n8n. burrow_recall without full gives the fold itself.")
        XCTAssertFalse(full.text.contains("clock skew"))

        // Claude Code in another session: no.
        let (other, _) = try await server(.full, client: "claude-code", session: "sess-other")
        let elsewhere = try await call(other, "burrow_recall", #"{"fold":"sess-9-1","full":true}"#)
        XCTAssertTrue(elsewhere.text.contains("this connection serves another session"), elsewhere.text)

        // Claude Code in the fold's own session goes on to the transcript (not where Claude Code keeps them here, so not read).
        let (same, _) = try await server(.full, client: "claude-code", session: "sess-9")
        let own = try await call(same, "burrow_recall", #"{"fold":"sess-9-1","full":true}"#)
        XCTAssertTrue(own.text.contains("can't be read"), own.text)
    }

    func testTheOriginalsComeBackWithoutSecretsToTheirOwnSession() throws {
        let roots = top.appendingPathComponent("projects")
        let transcript = roots.appendingPathComponent("-p/sess-9.jsonl")
        try FileManager.default.createDirectory(at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        try leakyStretch.write(to: transcript, atomically: true, encoding: .utf8)
        let store = FoldStore(folder: top.appendingPathComponent("folds"))
        try store.fold(transcript: leakyStretch, path: transcript.path, session: "sess-9", event: "PreCompact")
        let mine = Folds.recall(store, id: "sess-9-1", find: nil, full: true, reader: Folds.Reader(client: "claude-code", session: "sess-9"), roots: [roots])
        XCTAssertTrue(mine.found, mine.text)
        XCTAssertTrue(mine.text.contains("The original messages of fold sess-9-1"), mine.text)
        XCTAssertTrue(mine.text.contains("RuntimeError: clock skew 812 ms exceeds tolerance on node edge-ke-07"), mine.text)
        // The tool call comes back as JSON: its escaped quotes stay escaped around the marker.
        XCTAssertTrue(mine.text.contains(#"curl -H \"Authorization: Bearer [secret removed]\" https://api.example.com/v1/limits"#), mine.text)
        assertClean(mine.text)
        // The person at `burrow recall --full` (no reader) is given them too.
        XCTAssertTrue(Folds.recall(store, id: "sess-9-1", find: nil, full: true, roots: [roots]).found)
        // Without the session (a Claude Code that does not say it), the program's name decides.
        XCTAssertTrue(Folds.mayRestore(store.find("sess-9-1")!, for: Folds.Reader(client: "claude-code", session: nil)))
        XCTAssertFalse(Folds.mayRestore(store.find("sess-9-1")!, for: Folds.Reader(client: "opencode", session: "sess-9")))
        XCTAssertFalse(Folds.mayRestore(store.find("sess-9-1")!, for: Folds.Reader(client: nil, session: nil)))
    }

    // MARK: Claude Code's own path

    func testTheHandBackAfterACompactionStillWorksAndTheHandoffKeepsNoSecret() throws {
        let ledger = Ledger(folder: top.appendingPathComponent("ledger"), read: { _ in "text" })
        let place = Hooks.Place(branch: "main", root: URL(fileURLWithPath: "/p"), prefix: "")
        let store = FoldStore(folder: top.appendingPathComponent("folds"))
        let fold = try XCTUnwrap(try store.fold(transcript: leakyStretch, path: "/t/sess-9.jsonl", session: "sess-9", event: "PreCompact"))
        let made = try Hooks.checkpoint(ledger: ledger, place: place, transcript: Hooks.readTranscript(leakyStretch), session: "sess-9",
                                        event: "PreCompact", folded: fold)
        let handoff = try XCTUnwrap(made.last)
        XCTAssertEqual(made.map(\.kind), [.plan, .handoff])
        for commit in made { assertClean(commit.message + "\n" + commit.body) }
        XCTAssertTrue(made[0].message.contains("Rotate [secret removed]"), made[0].message)
        XCTAssertTrue(handoff.message.contains("OPENAI_API_KEY=[secret removed]"), handoff.message)
        let start = Folds.sessionStartAfterCompact(ledger: ledger, place: place, folds: store.folds(session: "sess-9"))
        let reply = try JSONSerialization.jsonObject(with: Data(start.utf8)) as! [String: Any]
        let context = (reply["hookSpecificOutput"] as! [String: Any])["additionalContext"] as! String
        XCTAssertTrue(context.contains("<burrow-folds>"), context)
        XCTAssertTrue(context.contains("RuntimeError: clock skew 812 ms exceeds tolerance on node edge-ke-07"), context)
        XCTAssertTrue(context.contains("Keep burst at exactly 37 tokens."), context)
        assertClean(context)
    }
}
