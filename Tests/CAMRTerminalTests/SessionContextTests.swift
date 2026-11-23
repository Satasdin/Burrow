@testable import CAMRChat
@testable import CAMRCore
@testable import CAMRTools
import XCTest

/// A live session's context (D-116) and the session archive (D-117): long tool output kept by handle, recall of the exact
/// words that left the context, the compaction steered, every session kept and resumable by any program.
final class SessionContextTests: XCTestCase {
    private var top: URL!

    override func setUp() {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("session-context-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: top, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: top) }

    private func line(_ object: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    private func places() -> SessionHooks.Places { SessionHooks.Places(state: top) }

    private func log(lines: Int, error at: Int? = nil) -> String {
        (1...lines).map { $0 == at ? "ERROR batch \($0) failed: checksum mismatch on shard 0x5F3A" : "INFO worker processed batch \($0) in 12ms" }.joined(separator: "\n")
    }

    /// A Claude Code transcript: a request with a value, a long command output, a compaction, then a new request.
    private func transcript(session: String = "sess-1") -> String {
        [
            line(["type": "user", "uuid": "u0000001-a", "sessionId": session, "cwd": "/p", "timestamp": "2026-11-17T10:00:00.000Z",
                  "message": ["role": "user", "content": "The deploy port is 7431 and the codename is Marmot. Fix the parser in parse.py."]]),
            line(["type": "assistant", "uuid": "a0000002-a", "timestamp": "2026-11-17T10:00:05.000Z",
                  "message": ["role": "assistant", "model": "claude-sonnet-5-5", "usage": ["input_tokens": 10, "cache_read_input_tokens": 20_000, "cache_creation_input_tokens": 500, "output_tokens": 80],
                              "content": [["type": "text", "text": "I chose a hand-written parser because the grammar is tiny."],
                                          ["type": "tool_use", "id": "t1", "name": "Edit", "input": ["file_path": "/p/parse.py"]]]]]),
            line(["type": "user", "uuid": "r0000003-a", "timestamp": "2026-11-17T10:00:06.000Z",
                  "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t1", "content": "edited"]]]]),
            line(["type": "system", "subtype": "compact_boundary", "uuid": "b0000004-a", "compactMetadata": ["trigger": "auto", "preTokens": 99_000, "postTokens": 9_000]]),
            line(["type": "user", "uuid": "s0000005-a", "isCompactSummary": true, "message": ["role": "user", "content": "Summary: worked on the parser."]]),
            line(["type": "user", "uuid": "u0000006-a", "timestamp": "2026-11-17T11:00:00.000Z",
                  "message": ["role": "user", "content": "Now ship it."]]),
            line(["type": "assistant", "uuid": "a0000007-a", "timestamp": "2026-11-17T11:00:04.000Z",
                  "message": ["role": "assistant", "model": "claude-sonnet-5-5", "usage": ["input_tokens": 5, "cache_read_input_tokens": 9_000, "cache_creation_input_tokens": 100, "output_tokens": 30],
                              "content": [["type": "text", "text": "Shipping now."]]]]),
            line(["type": "custom-title", "customTitle": "parser-fix", "sessionId": session]),
        ].joined(separator: "\n")
    }

    // MARK: Lean output

    func testLongBashOutputIsKeptByHandleAndShortened() throws {
        let p = places()
        let output = log(lines: 900, error: 450)
        let event: [String: Any] = ["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Bash",
                                    "tool_input": ["command": "cat server.log"],
                                    "tool_response": ["stdout": output, "stderr": "", "interrupted": false, "isImage": false]]
        let reply = try XCTUnwrap(SessionHooks.handle(event, places: p))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        let shown = try XCTUnwrap(((root["hookSpecificOutput"] as? [String: Any])?["updatedToolOutput"] as? [String: Any])?["stdout"] as? String)
        XCTAssertLessThan(shown.count, output.count / 4, "the model sees a short form")
        XCTAssertTrue(shown.contains("INFO worker processed batch 1 in"), "the head")
        XCTAssertTrue(shown.contains("batch 900"), "the tail")
        XCTAssertTrue(shown.contains("ERROR batch 450 failed: checksum mismatch on shard 0x5F3A"), "an error from the middle, exactly")
        let entry = try XCTUnwrap(p.kept.entries(session: "s1").first)
        XCTAssertTrue(shown.contains(entry.handle))
        XCTAssertEqual(p.kept.text(entry), output, "the whole output is kept")
        let events = p.meter.events(session: "s1")
        XCTAssertEqual(events.first?.kind, .kept)
        XCTAssertEqual(events.first?.original, output.count)
    }

    func testShortOutputBackgroundCommandsAndRangedReadsAreLeftAlone() {
        let p = places()
        let small: [String: Any] = ["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Bash", "tool_input": ["command": "ls"],
                                    "tool_response": ["stdout": "a\nb", "stderr": ""]]
        XCTAssertEqual(SessionHooks.handle(small, places: p), "")
        let background: [String: Any] = ["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Bash",
                                         "tool_input": ["command": "server", "run_in_background": true], "tool_response": ["stdout": log(lines: 900)]]
        XCTAssertEqual(SessionHooks.handle(background, places: p), "")
        let ranged: [String: Any] = ["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Read",
                                     "tool_input": ["file_path": "/x.py", "offset": 10, "limit": 50],
                                     "tool_response": ["type": "text", "file": ["filePath": "/x.py", "content": log(lines: 50), "numLines": 50, "startLine": 10, "totalLines": 5000]]]
        XCTAssertEqual(SessionHooks.handle(ranged, places: p), "")
        XCTAssertTrue(p.kept.entries(session: "s1").isEmpty)
    }

    func testLongWholeFileReadShowsItsStartAndOutline() throws {
        let file = top.appendingPathComponent("big.py")
        let code = (1...2_000).map { $0 % 100 == 1 ? "def step_\($0)():" : "    x = \($0)" }.joined(separator: "\n")
        try code.write(to: file, atomically: true, encoding: .utf8)
        let event: [String: Any] = ["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Read", "tool_input": ["file_path": file.path],
                                    "tool_response": ["type": "text", "file": ["filePath": file.path, "content": code, "numLines": 2000, "startLine": 1, "totalLines": 2000]]]
        let reply = try XCTUnwrap(SessionHooks.handle(event, places: places()))
        let specific = try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])?["hookSpecificOutput"] as? [String: Any])
        let fileOut = try XCTUnwrap((specific["updatedToolOutput"] as? [String: Any])?["file"] as? [String: Any])
        XCTAssertEqual(fileOut["numLines"] as? Int, 120)
        XCTAssertEqual((fileOut["content"] as? String)?.components(separatedBy: "\n").count, 120)
        let note = try XCTUnwrap(specific["additionalContext"] as? String)
        XCTAssertTrue(note.contains("first 120 of 2000 lines"))
        XCTAssertTrue(note.contains("step_1901 1901-"), "the outline names where each function is")
    }

    func testEachLeanPartCanBeSwitchedOff() throws {
        var settings = SessionSettings()
        settings.leanBash = false
        try settings.save(to: top)
        let event: [String: Any] = ["hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Bash", "tool_input": ["command": "cat"],
                                    "tool_response": ["stdout": log(lines: 900)]]
        XCTAssertEqual(SessionHooks.handle(event, places: places()), "")
        // A settings file written before a setting existed keeps that setting's default.
        try #"{"recall": false}"#.write(to: SessionSettings.file(in: top), atomically: true, encoding: .utf8)
        let loaded = SessionSettings.load(from: top)
        XCTAssertFalse(loaded.recall)
        XCTAssertTrue(loaded.leanRead)
    }

    func testExpandGivesLinesOrMatchesAndOnlyToTheSessionThatKeptIt() throws {
        let p = places()
        let entry = try p.kept.keep(log(lines: 900, error: 450), session: "s1", tool: "Bash", label: "cat server.log")
        let lines = SessionTools.expand(handle: entry.handle, lines: "449-451", find: nil, reader: nil, places: p)
        XCTAssertTrue(lines.text.contains("450\tERROR batch 450"))
        XCTAssertFalse(lines.text.contains("452\t"))
        let found = SessionTools.expand(handle: entry.handle, lines: nil, find: "checksum", reader: Folds.Reader(client: "claude-code", session: "s1"), places: p)
        XCTAssertTrue(found.text.contains("450\tERROR"))
        let other = SessionTools.expand(handle: entry.handle, lines: "1-2", find: nil, reader: Folds.Reader(client: "claude-code", session: "s2"), places: p)
        XCTAssertTrue(other.isError)
        let codex = SessionTools.expand(handle: entry.handle, lines: "1-2", find: nil, reader: Folds.Reader(client: "codex-mcp-client", session: nil), places: p)
        XCTAssertTrue(codex.isError)
    }

    // MARK: Reading sessions

    func testClaudeTranscriptIsReadWithItsCompactionAndUsage() {
        let session = SessionText.claudeCode(transcript(), id: "fallback")
        XCTAssertEqual(session.id, "sess-1")
        XCTAssertEqual(session.title, "parser-fix")
        XCTAssertEqual(session.requests.map(\.text).count, 2)
        XCTAssertEqual(session.compactions.count, 1)
        XCTAssertEqual(session.compactions.first?.before, 99_000)
        XCTAssertEqual(session.usage.map(\.context), [20_510, 9_105])
        // Everything before the compaction has left the context; what came after has not.
        XCTAssertTrue(session.pieces.first { $0.text.contains("7431") }?.compacted == true)
        XCTAssertTrue(session.pieces.first { $0.text == "Now ship it." }?.compacted == false)
        XCTAssertFalse(session.pieces.contains { $0.text.contains("Summary: worked") }, "the summary is not something that was said")
    }

    func testCodexRolloutIsRead() {
        let rollout = [
            line(["type": "session_meta", "timestamp": "2026-11-10T09:00:00.000Z", "payload": ["id": "019a-codex", "cwd": "/repo"]]),
            line(["type": "turn_context", "payload": ["model": "gpt-5.3-codex", "cwd": "/repo"]]),
            line(["type": "response_item", "timestamp": "2026-11-10T09:00:01.000Z", "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": "Add retries to the uploader; max 5 attempts."]]]]),
            line(["type": "response_item", "payload": ["type": "function_call", "name": "shell", "arguments": #"{"command":["pytest","-q"]}"#, "call_id": "c1"]]),
            line(["type": "response_item", "payload": ["type": "function_call_output", "call_id": "c1", "output": #"{"output":"FAILED test_upload.py::test_retry - AssertionError"}"#]]),
            line(["type": "response_item", "payload": ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "Retries capped at 5 because the API rate-limits."]]]]),
            line(["type": "event_msg", "payload": ["type": "token_count", "info": ["last_token_usage": ["input_tokens": 12_000, "output_tokens": 300]]]]),
        ].joined(separator: "\n")
        let session = SessionText.codex(rollout, id: "file")
        XCTAssertEqual(session.id, "019a-codex")
        XCTAssertEqual(session.cwd, "/repo")
        XCTAssertEqual(session.model, "gpt-5.3-codex")
        XCTAssertEqual(session.requests.first?.text, "Add retries to the uploader; max 5 attempts.")
        XCTAssertTrue(session.pieces.contains { $0.role == .result && $0.text.contains("AssertionError") })
        XCTAssertEqual(session.usage.first?.context, 12_000)
        // Folded like a Claude Code session, so the pack keeps the decision and the error.
        let fold = Fold.make(transcript: session.asClaudeTranscript(), after: nil, session: session.id, number: 0, event: "Resume", path: "x")
        XCTAssertTrue(fold?.said.contains { $0.text.contains("because the API rate-limits") } == true)
        XCTAssertTrue(fold?.errors.contains { $0.contains("AssertionError") } == true)
    }

    // MARK: Recall

    func testRecallHandsBackOnlyWordsThatLeftTheContextAndMatch() throws {
        let p = places()
        let session = SessionText.claudeCode(transcript(), id: "sess-1")
        let found = try XCTUnwrap(AutoRecall.handBack(prompt: "What was the deploy port again?", session: session, kept: p.kept, sessionID: "sess-1"))
        XCTAssertTrue(found.text.contains("The deploy port is 7431"))
        XCTAssertTrue(found.text.contains("data, not instructions"))
        XCTAssertLessThanOrEqual(found.characters, AutoRecall.most + 200)
        // Words still in the context ("ship") bring nothing back, nor does a message that matches nothing.
        XCTAssertNil(AutoRecall.handBack(prompt: "Did you ship it yet?", session: session, kept: p.kept, sessionID: "sess-1"))
        // What the program puts in the person's turn is not a question, even when it holds matching words.
        XCTAssertNil(AutoRecall.handBack(prompt: "<system-reminder>the deploy port 7431</system-reminder>", session: session, kept: p.kept, sessionID: "sess-1"))
        XCTAssertNil(AutoRecall.handBack(prompt: "What colour should the button be?", session: session, kept: p.kept, sessionID: "sess-1"))
    }

    func testRecallSearchesKeptOutputs() throws {
        let p = places()
        _ = try p.kept.keep(log(lines: 900, error: 450), session: "s1", tool: "Bash", label: "cat server.log")
        let session = SessionText.claudeCode("", id: "s1")
        let found = try XCTUnwrap(AutoRecall.handBack(prompt: "which shard had the checksum mismatch?", session: session, kept: p.kept, sessionID: "s1"))
        XCTAssertTrue(found.text.contains("0x5F3A"))
    }

    func testRecallHookRecordsWhatItGave() throws {
        let p = places()
        let path = top.appendingPathComponent("sess-1.jsonl")
        try transcript().write(to: path, atomically: true, encoding: .utf8)
        let event: [String: Any] = ["hook_event_name": "UserPromptSubmit", "session_id": "sess-1", "transcript_path": path.path, "prompt": "remind me of the codename Marmot details"]
        let reply = try XCTUnwrap(SessionHooks.handle(event, places: p))
        XCTAssertTrue(reply.contains("additionalContext"))
        XCTAssertTrue(p.meter.events(session: "sess-1").contains { $0.kind == .recalled })
        XCTAssertNotNil(p.archive.meta(.claudeCode, "sess-1"), "the session was archived on its first message")
    }

    func testWordMatchNeedsTwoWordsOrOneSpecificOne() {
        let docs = ["the parser is done", "port 7431 for deploy", "nothing here"]
        XCTAssertEqual(WordMatch.rank("parser", documents: docs).count, 0, "one common word is noise")
        XCTAssertEqual(WordMatch.rank("7431", documents: docs).first?.index, 1)
        XCTAssertEqual(WordMatch.rank("is the parser done", documents: docs).first?.index, 0)
        // A short number alone is noise; a code name with a digit in it is not.
        XCTAssertTrue(WordMatch.rank("route 46", documents: ["shard-04 reconciled 46 rows"]).isEmpty)
        XCTAssertEqual(WordMatch.rank("shard 0x5F3A", documents: ["FATAL shard 0x5F3A checksum"]).count, 1)
    }

    // MARK: Steering and resume advice

    func testCompactionIsToldToKeepRequestsValuesAndHandles() throws {
        let p = places()
        let entry = try p.kept.keep(log(lines: 900), session: "sess-1", tool: "Bash", label: "cat server.log")
        let path = top.appendingPathComponent("t.jsonl")
        try transcript().write(to: path, atomically: true, encoding: .utf8)
        let said = SessionHooks.steer(["session_id": "sess-1", "transcript_path": path.path, "trigger": "auto"], fold: "sess-1-2", places: p)
        XCTAssertTrue(said.contains("word for word"))
        XCTAssertTrue(said.contains(entry.handle))
        XCTAssertTrue(said.contains("camr_recall sess-1-2"))
        XCTAssertTrue(said.contains("The deploy port is 7431"))
        XCTAssertLessThanOrEqual(said.count, 4_000)
    }

    func testResumeAdviceOnlyWhenTheCacheExpiredOnALargeSession() {
        let p = places()
        let expired: [String: Any] = ["source": "resume", "session_id": "abcdef12-x", "prompt_cache_likely_expired": true, "context_tokens": 140_000, "estimated_cache_write_usd": 0.56]
        let advice = SessionHooks.resumeAdvice(expired, places: p)
        XCTAssertTrue(advice?.contains("$0.56") == true)
        XCTAssertTrue(advice?.contains("/camr-resume abcdef12") == true)
        var warm = expired; warm["prompt_cache_likely_expired"] = false
        XCTAssertNil(SessionHooks.resumeAdvice(warm, places: p))
        var small = expired; small["context_tokens"] = 9_000
        XCTAssertNil(SessionHooks.resumeAdvice(small, places: p))
        let merged = SessionHooks.merge(advice: "note", into: #"{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"head"}}"#)
        XCTAssertTrue(merged.contains("systemMessage") && merged.contains("head"))
    }

    func testTheLedgerHeadIsNotHandedOverAgainWhileItIsStillInTheContext() {
        let head = #"{"type":"attachment","attachment":{"type":"hook_additional_context","content":["<ledger> This comes from CAMR's Ledger."]}}"#
        XCTAssertTrue(SessionHooks.stillHasHead(transcript: transcript() + "\n" + head))
        XCTAssertFalse(SessionHooks.stillHasHead(transcript: head + "\n" + transcript()), "a compaction since took it away")
        XCTAssertFalse(SessionHooks.stillHasHead(transcript: "{}"))
    }

    // MARK: Archive and resume

    func testAnArchiveOnADriveThatIsNotConnectedKeepsSessionsInCAMRsOwnFolder() {
        var settings = SessionSettings()
        settings.archiveFolder = "/Volumes/NoSuchDrive-\(UUID().uuidString)/CAMRSessions"
        let state = top.appendingPathComponent("state")
        XCTAssertNotNil(SessionArchive.missingDrive(URL(fileURLWithPath: settings.archiveFolder!)))
        XCTAssertEqual(SessionArchive.standard(settings: settings, state: state).folder, state.appendingPathComponent("sessions", isDirectory: true))
        XCTAssertEqual(settings.archiveFolder?.hasPrefix("/Volumes/NoSuchDrive"), true, "the person's setting is left as they set it")

        settings.archiveFolder = top.appendingPathComponent("chosen").path
        XCTAssertNil(SessionArchive.missingDrive(URL(fileURLWithPath: settings.archiveFolder!)), "a folder not on /Volumes is never a missing drive")
        XCTAssertEqual(SessionArchive.standard(settings: settings, state: state).folder.path, top.appendingPathComponent("chosen").path)
        XCTAssertNil(SessionArchive.missingDrive(URL(fileURLWithPath: "/Volumes")), "the volumes folder itself is no drive")
    }

    func testArchiveKeepsFindsAndResumesASession() throws {
        let archive = SessionArchive(folder: top.appendingPathComponent("archive"))
        let path = top.appendingPathComponent("sess-1.jsonl")
        try transcript().write(to: path, atomically: true, encoding: .utf8)
        let meta = try XCTUnwrap(try archive.keep(path: path.path, program: .claudeCode))
        XCTAssertEqual(meta.name, "parser-fix")
        XCTAssertEqual(meta.compactions, 1)
        XCTAssertEqual(meta.contextPeak, 20_510)
        XCTAssertLessThan(meta.archivedBytes, meta.sourceBytes + 200)
        // Kept again unchanged, it is not rewritten.
        let again = try XCTUnwrap(try archive.keep(path: path.path, program: .claudeCode))
        XCTAssertEqual(again.archivedAt, meta.archivedAt)
        // The program deletes its transcript: the archive still has every word.
        try FileManager.default.removeItem(at: path)
        XCTAssertEqual(archive.find("parser").map(\.id), ["sess-1"])
        XCTAssertEqual(archive.find("sess-1").first?.id, "sess-1")
        let session = try XCTUnwrap(archive.load(meta))
        let pack = ResumePack.make(session, meta: meta, raw: archive.raw(meta))
        XCTAssertTrue(pack.contains("The deploy port is 7431 and the codename is Marmot"), "requests word for word")
        XCTAssertTrue(pack.contains("because the grammar is tiny"), "decisions with their reasons")
        XCTAssertTrue(pack.contains("Last request (u0000006)"), "where it stopped")
        XCTAssertTrue(pack.hasPrefix(ResumePack.opening))
        XCTAssertEqual(pack, ResumePack.make(session, meta: meta, raw: archive.raw(meta)), "the same pack every time, so a model's cache of it fits")
        XCTAssertTrue(ResumePack.search(session, query: "codename Marmot")?.contains("u0000001") == true)
        XCTAssertTrue(ResumePack.timeline(session).contains("Now ship it."))
    }

    func testSyncKeepsClaudeAndCodexAndSkipsCodexCopiesOfClaudeSessions() throws {
        let claude = top.appendingPathComponent("claude/projects/-p")
        let codex = top.appendingPathComponent("codex/sessions/2026/11/10")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try transcript().write(to: claude.appendingPathComponent("sess-1.jsonl"), atomically: true, encoding: .utf8)
        let own = line(["type": "response_item", "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": "codex own work"]]]])
        try (line(["type": "session_meta", "payload": ["id": "own-thread"]]) + "\n" + own).write(to: codex.appendingPathComponent("rollout-2026-11-10T09-00-00-own-thread.jsonl"), atomically: true, encoding: .utf8)
        try (line(["type": "session_meta", "payload": ["id": "copied-thread"]]) + "\n" + own).write(to: codex.appendingPathComponent("rollout-2026-11-10T09-00-00-copied-thread.jsonl"), atomically: true, encoding: .utf8)
        let imports = top.appendingPathComponent("codex/external_agent_session_imports.json")
        try #"[{"imported_thread_id":"copied-thread","source_path":"/x.jsonl"}]"#.write(to: imports, atomically: true, encoding: .utf8)
        let archive = SessionArchive(folder: top.appendingPathComponent("archive"))
        let report = archive.sync(SessionArchive.Sources(claude: [top.appendingPathComponent("claude/projects")], codex: top.appendingPathComponent("codex/sessions"), codexImports: imports))
        XCTAssertEqual(report.kept, 2)
        XCTAssertEqual(report.skipped, 1)
        XCTAssertEqual(Set(archive.list().map(\.id)), ["sess-1", "own-thread"])
        XCTAssertEqual(archive.sync(SessionArchive.Sources(claude: [top.appendingPathComponent("claude/projects")], codex: top.appendingPathComponent("codex/sessions"), codexImports: imports)).unchanged, 2)
    }

    func testAnotherProgramGetsThePackButTheOriginalsOnlyOnceThePersonAllows() throws {
        let p = SessionHooks.Places(state: top)
        let path = top.appendingPathComponent("sess-1.jsonl")
        try transcript().write(to: path, atomically: true, encoding: .utf8)
        _ = try p.archive.keep(path: path.path, program: .claudeCode)
        let pack = SessionTools.session("parser-fix", find: nil, timeline: nil, ref: nil, client: "codex-mcp-client", places: p)
        XCTAssertFalse(pack.isError)
        XCTAssertTrue(pack.text.contains("7431"))
        let search = SessionTools.session("sess-1", find: "Marmot", timeline: nil, ref: nil, client: "codex-mcp-client", places: p)
        XCTAssertTrue(search.isError)
        XCTAssertTrue(search.text.contains("camr session allow"))
        XCTAssertFalse(SessionTools.session("sess-1", find: "Marmot", timeline: nil, ref: nil, client: "claude-code", places: p).isError)
        try SessionApprovals(folder: top).allow(session: "sess-1", program: "codex")
        XCTAssertFalse(SessionTools.session("sess-1", find: "Marmot", timeline: nil, ref: nil, client: "codex-mcp-client", places: p).isError)
    }

    func testCodexHooksAreConnectedWithoutLeanOutputAndWithAShortSessionEnd() throws {
        let home = top.appendingPathComponent("home")
        setenv("CODEX_HOME", home.appendingPathComponent(".codex").path, 1)
        defer { unsetenv("CODEX_HOME") }
        let plan = Connect.plan(.codex, Connect.Setup(camr: "/bin/camr", vault: "/v", home: home))
        XCTAssertNil(plan.refusal)
        let config = try XCTUnwrap(plan.changes.first { $0.path.lastPathComponent == "config.toml" })
        XCTAssertTrue(config.after.contains("[mcp_servers.camr]\ncommand = \"/bin/camr\"\nargs = [\"mcp\", \"/v\"]"))
        let hooks = try XCTUnwrap(plan.changes.first { $0.path.lastPathComponent == "hooks.json" })
        XCTAssertTrue(hooks.after.contains("UserPromptSubmit"))
        XCTAssertFalse(hooks.after.contains("PostToolUse"))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(hooks.after.utf8)) as? [String: Any])
        let end = ((root["hooks"] as? [String: Any])?["SessionEnd"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]]
        XCTAssertEqual(end?.first?["timeout"] as? Int, 3)
        XCTAssertTrue(plan.changes.contains { $0.path.path.hasSuffix(".agents/skills/camr-resume/SKILL.md") })
    }

    func testClaudeCodeConnectAddsTheSessionHooksAndSkill() throws {
        let home = top.appendingPathComponent("home")
        let plan = Connect.plan(.claudeCode, Connect.Setup(camr: "/bin/camr", vault: "/v", home: home))
        let hooks = try XCTUnwrap(plan.changes.first { $0.path.lastPathComponent == "settings.json" })
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(hooks.after.utf8)) as? [String: Any])
        let all = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual((all["PostToolUse"] as? [[String: Any]])?.first?["matcher"] as? String, "Bash|Read|Grep")
        XCTAssertNotNil(all["UserPromptSubmit"]); XCTAssertNotNil(all["PostCompact"])
        XCTAssertTrue(plan.changes.contains { $0.path.path.hasSuffix(".claude/skills/camr-resume/SKILL.md") })
        // Connecting twice adds nothing twice.
        let twice = Connect.addHooks(all, Connect.hookEntries("/bin/camr hook claude /v", sessionEnd: 10, postToolUse: true))
        XCTAssertEqual((twice["PostToolUse"] as? [[String: Any]])?.count, 1)
    }

    // MARK: The app's model

    func testLlamaChatSendsToolCallsInOpenAIForm() {
        let messages: [[String: Any]] = [
            ["role": "system", "content": "rules"], ["role": "user", "content": "q"],
            ["role": "assistant", "content": "", "tool_calls": [["function": ["name": "vault_search", "arguments": ["query": "port"]]]]],
            ["role": "tool", "tool_name": "vault_search", "content": "found"],
        ]
        let out = LlamaChat.openAI(messages)
        let call = (out[2]["tool_calls"] as? [[String: Any]])?.first
        XCTAssertEqual(call?["id"] as? String, "call1")
        XCTAssertEqual((call?["function"] as? [String: Any])?["arguments"] as? String, #"{"query":"port"}"#)
        XCTAssertEqual(out[3]["tool_call_id"] as? String, "call1")
        XCTAssertNil(out[3]["tool_name"])
    }

    func testChatCacheKeyIsSafeAsAFileName() {
        XCTAssertEqual(KVShelf.chatKey(conversation: "session-019a/../x y"), "chat-session-019axy")
    }
}
