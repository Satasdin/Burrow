@testable import BurrowChat
@testable import BurrowCore
import BurrowTools
import XCTest

/// Plays back a script of replies and records what it was sent.
final class ScriptedBackend: ChatBackend {
    let model: String
    var script: [ModelReply]
    private(set) var sent: [[[String: Any]]] = []
    private(set) var toolsOffered: [Bool] = []

    init(model: String = "stand-in", script: [ModelReply]) {
        self.model = model
        self.script = script
    }

    func reply(messages: [[String: Any]], tools: [[String: Any]]?, onWord: @escaping (String) -> Void) async throws -> ModelReply {
        sent.append(messages)
        toolsOffered.append(tools != nil)
        let reply = script.isEmpty ? ModelReply(text: "done", toolCalls: []) : script.removeFirst()
        if !reply.text.isEmpty { onWord(reply.text) }
        return reply
    }
}

final class ChatTests: XCTestCase {
    private var fixture: VaultFixture!
    private var tools: VaultTools!

    override func setUp() async throws {
        fixture = try VaultFixture()
        let vault = try await fixture.opened()
        let answerer = FakeAnswerer()
        tools = VaultTools(vault: vault, embedder: nil) { _ in answerer }
    }

    private func search(_ query: String) -> ModelReply {
        ModelReply(text: "", toolCalls: [ModelToolCall(name: "vault_search", arguments: ["query": query])])
    }

    func testToolsAreReallyCalledAndTheResultGoesBack() async throws {
        let backend = ScriptedBackend(script: [search("retry"), ModelReply(text: "Three times.", toolCalls: [])])
        let turn = try await ChatSession(tools: tools, backend: backend).ask("How often?")
        XCTAssertEqual(turn.answer, "Three times.")
        XCTAssertEqual(turn.rounds, 2)
        XCTAssertEqual(turn.modelCalls, 1)
        XCTAssertEqual(turn.events[0].name, "vault_search")
        let tool = backend.sent[1].first { $0["role"] as? String == "tool" }
        XCTAssertEqual(tool?["tool_name"] as? String, "vault_search")
        XCTAssertTrue((tool?["content"] as? String)?.contains("<excerpt") ?? false)
        XCTAssertFalse(turn.sources.isEmpty)
    }

    func testAToolTheChatDidNotOfferIsRefusedAndWritesNothing() async throws {
        let sneaky = ModelReply(text: "", toolCalls: [ModelToolCall(name: "vault_session_log", arguments: ["session": "new", "question": "q", "answer": "a"])])
        let backend = ScriptedBackend(script: [sneaky, ModelReply(text: "ok", toolCalls: [])])
        let turn = try await ChatSession(tools: tools, backend: backend).ask("Save it")
        XCTAssertTrue(turn.events[0].failed)
        XCTAssertEqual(turn.events[0].outcome, "refused: not offered in this chat")
        XCTAssertTrue(tools.sessions.list().isEmpty, "nothing was written to the vault")
    }

    func testTheLoopStopsAtItsRoundLimitAndStillAnswers() async throws {
        let many = (0..<20).map { search("query \($0)") }
        let backend = ScriptedBackend(script: many + [ModelReply(text: "unused", toolCalls: [])])
        var settings = ChatSession.Settings()
        settings.mostRounds = 3
        let turn = try await ChatSession(tools: tools, backend: backend, settings: settings).ask("Loop?")
        XCTAssertEqual(turn.events.count, 3)
        XCTAssertTrue(turn.endedAtLimit)
        XCTAssertEqual(backend.toolsOffered.last, false, "the last round offers no tools, so the model has to answer")
    }

    func testAFailedCallIsToldToTheModelNotThrown() async throws {
        let bad = ModelReply(text: "", toolCalls: [ModelToolCall(name: "vault_read", arguments: [:])])
        let backend = ScriptedBackend(script: [bad, ModelReply(text: "ok", toolCalls: [])])
        let turn = try await ChatSession(tools: tools, backend: backend).ask("?")
        XCTAssertTrue(turn.events[0].failed)
        XCTAssertTrue((backend.sent[1].last?["content"] as? String)?.contains("did not work") ?? false)
    }

    func testAnIdenticalCallIsNotRunTwice() async throws {
        let backend = ScriptedBackend(script: [search("retry"), search("retry"), ModelReply(text: "ok", toolCalls: [])])
        let turn = try await ChatSession(tools: tools, backend: backend).ask("?")
        XCTAssertEqual(turn.events.count, 1)
    }

    func testAlwaysSearchRunsFirstAndIsMarkedAsNotTheModelsChoice() async throws {
        let backend = ScriptedBackend(script: [ModelReply(text: "Answer.", toolCalls: [])])
        var settings = ChatSession.Settings()
        settings.alwaysSearchFirst = true
        let turn = try await ChatSession(tools: tools, backend: backend, settings: settings).ask("retry failed charge")
        XCTAssertEqual(turn.events.count, 1)
        XCTAssertTrue(turn.events[0].forced)
        XCTAssertEqual(turn.modelCalls, 0)
        XCTAssertTrue(backend.sent[0].contains { $0["role"] as? String == "tool" })
    }

    func testTheChatHearsTheLedgerAsTheAppsAskDoes() async throws {
        // 14 November: `burrow chat` said "the split of the rent is not recorded" with the split kept as a decision,
        // because only the app's Ask read the Ledger (D-90).
        let kept = try tools.ledger.commit(.decision, "From December the retry limit for a failed charge is five, and I check it each Monday",
                                           body: "Because: the bank asked for more tries.", author: "claude-opus", client: "claude-code")
        let backend = ScriptedBackend(script: [ModelReply(text: "Five tries (Ledger \(kept.id)), because the bank asked. (notes/plan.md:12)", toolCalls: [])])
        var settings = ChatSession.Settings()
        settings.alwaysSearchFirst = true
        var streamed = ""
        var watching = ChatSession.Observer()
        watching.word = { streamed += $0 }
        let turn = try await ChatSession(tools: tools, backend: backend, settings: settings)
            .ask("How many times is a failed charge retried from December?", observer: watching)
        let system = try XCTUnwrap(backend.sent[0].first?["content"] as? String)
        XCTAssertTrue(system.contains(AskLedger.rule), "the chat is told what the Ledger is, in the app's words")
        let prepared = try XCTUnwrap(backend.sent[0].first { $0["role"] as? String == "tool" }?["content"] as? String)
        XCTAssertTrue(prepared.contains("<ledger>"), prepared)
        XCTAssertTrue(prepared.contains("- \(AskLedger.label(kept.id)) [decision]: From December"), prepared)
        XCTAssertTrue(prepared.contains("Because: the bank asked for more tries."), prepared)
        XCTAssertEqual(turn.ledger, [kept.id])
        // The decision it was given stays cited; the file it was never shown is taken out, from the screen and the answer.
        XCTAssertEqual(turn.answer, "Five tries (Ledger \(kept.id)), because the bank asked.")
        XCTAssertEqual(streamed, turn.answer)
        XCTAssertEqual(turn.unverified, ["notes/plan.md:12"])
    }

    func testALedgerIdWrittenInANoteDoesNotCountAsHandedOver() async throws {
        // A note or file can hold an id-shaped string. Before D-92 the chat read every id out of a tool's text, so a model
        // citing one a note carried passed the check as if the Ledger had handed it over.
        let planted = "20261114-065345-a355"
        try "# Rent split\n\nThe rent split is settled: I pay 40%. Decided in Ledger \(planted).\n"
            .write(to: fixture.vaultFolder.appendingPathComponent("Rent split.md"), atomically: true, encoding: .utf8)
        let vault = try await fixture.opened()
        let answerer = FakeAnswerer()
        let tools = VaultTools(vault: vault, embedder: nil) { _ in answerer }
        let kept = try tools.ledger.commit(.decision, "The rent split is 60/40 and I pay 40% of the rent",
                                           body: "Because: my room is the smaller one.", author: "claude-opus", client: "claude-code")
        XCTAssertNotEqual(kept.id, planted)
        let backend = ScriptedBackend(script: [
            search("rent split"),
            ModelReply(text: "You pay 40% (Ledger \(planted)) (Ledger \(kept.id)), because your room is the smaller one.", toolCalls: []),
        ])
        let turn = try await ChatSession(tools: tools, backend: backend).ask("What is the rent split?")
        let searched = try XCTUnwrap(backend.sent[1].last { $0["role"] as? String == "tool" }?["content"] as? String)
        XCTAssertTrue(searched.contains("Decided in Ledger \(planted)"), "the note's id reached the model: \(searched)")
        XCTAssertTrue(searched.contains(AskLedger.label(kept.id)), searched)
        XCTAssertEqual(turn.ledger, [kept.id], "only what the tool put in its own <ledger> block counts as handed over")
        XCTAssertEqual(turn.ledgerCited, [kept.id])
        XCTAssertEqual(turn.unverified, ["Ledger \(planted)"])
        XCTAssertEqual(turn.answer, "You pay 40% (Ledger \(kept.id)), because your room is the smaller one.")
    }

    func testTheLedgerStaysOutOfPrepareWhenItsNotesAreOff() async throws {
        _ = try tools.ledger.commit(.decision, "A failed charge is retried five times", body: "Because: the bank asked.", author: "a")
        tools.ledgerNotesOn = false
        let result = try await tools.call("vault_prepare", arguments: ["task": "How often is a failed charge retried?"])
        XCTAssertFalse(result.text.contains("<ledger>"), result.text)
    }

    func testAModelCannotKeepANoteUnlessSomeoneAgrees() async throws {
        let before = try fixture.snapshot()
        let remember = ModelReply(text: "", toolCalls: [ModelToolCall(name: "vault_remember", arguments: ["text": "evil", "kind": "note"])])
        let backend = ScriptedBackend(script: [remember, ModelReply(text: "ok", toolCalls: [])])
        let turn = try await ChatSession(tools: tools, backend: backend).ask("?")
        XCTAssertEqual(try fixture.snapshot(), before)
        XCTAssertTrue(turn.events[0].failed)
    }

    func testAgreeingKeepsTheNote() async throws {
        let remember = ModelReply(text: "", toolCalls: [ModelToolCall(name: "vault_remember", arguments: ["text": "We chose three", "kind": "decision"])])
        let backend = ScriptedBackend(script: [remember, ModelReply(text: "ok", toolCalls: [])])
        var observer = ChatSession.Observer()
        observer.mayRemember = { _, _ in true }
        let turn = try await ChatSession(tools: tools, backend: backend).ask("?", observer: observer)
        XCTAssertFalse(turn.events[0].failed)
        XCTAssertEqual(try fixture.snapshot().filter { $0.key.contains("/Memory/") }.count, 1)
    }

    func testOnlyQuestionsAndAnswersAreCarriedForward() async throws {
        let backend = ScriptedBackend(script: [search("retry"), ModelReply(text: "First.", toolCalls: []), ModelReply(text: "Second.", toolCalls: [])])
        let session = ChatSession(tools: tools, backend: backend)
        _ = try await session.ask("one")
        _ = try await session.ask("two")
        let last = backend.sent.last!
        XCTAssertFalse(last.contains { $0["role"] as? String == "tool" }, "old excerpts aren't resent")
        XCTAssertTrue(last.contains { $0["content"] as? String == "First." })
    }

    func testQwenGetsItsOffSwitch() async throws {
        let backend = ScriptedBackend(model: "qwen3:4b", script: [ModelReply(text: "ok", toolCalls: [])])
        _ = try await ChatSession(tools: tools, backend: backend).ask("hello")
        XCTAssertTrue((backend.sent[0].last?["content"] as? String)?.hasSuffix("/no_think") ?? false)
    }

    func testThinkingIsHiddenAsItStreams() {
        var filter = ThinkFilter()
        XCTAssertEqual(filter.add("<thi"), "")
        XCTAssertEqual(filter.add("nk>secret reasoning"), "")
        XCTAssertEqual(filter.add("</think>\n\nThe"), "The")
        XCTAssertEqual(filter.add(" answer"), " answer")
    }

    func testAnswersWithoutThinkingPassStraightThrough() {
        var filter = ThinkFilter()
        XCTAssertEqual(filter.add("Hello"), "Hello")
        XCTAssertEqual(filter.add(" there"), " there")
    }

    func testToolSchemaIsInOllamasShape() throws {
        let schema = OllamaChat.schema(of: VaultTools.definitions[0])
        XCTAssertEqual(schema["type"] as? String, "function")
        let function = try XCTUnwrap(schema["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "vault_search")
        XCTAssertNotNil(function["parameters"] as? [String: Any])
    }
}
