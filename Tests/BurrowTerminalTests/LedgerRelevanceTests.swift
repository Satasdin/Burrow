@testable import BurrowCore
@testable import BurrowTools
import Foundation
import XCTest

/// D-99: the Ledger notes that come with a search or a read are the ones that fit the request, not the newest.
/// E3 (14 November) found the old choice delivered the payment decision for 12 of 20 oddly worded tasks with 40 unrelated
/// decisions in the Ledger, and for none once 3 newer decisions cited its file.
final class LedgerRelevanceTests: XCTestCase {
    /// Meaning without shared words: words that mean the same thing land on the same axis, so "MSISDN" is close to
    /// "phone" although no word is shared. Other words land on a few noise axes by a stable hash.
    struct ConceptEmbedder: Embedder {
        static let concepts: [String: Int] = [
            "phone": 0, "msisdn": 0, "sender": 0, "mobile": 0, "number": 0,
            "match": 1, "matches": 1, "matching": 1, "matched": 1, "pair": 1, "link": 1, "guess": 1, "fallback": 1,
            "amount": 2, "fare": 2, "fares": 2, "money": 2,
            "payment": 3, "payments": 3, "paid": 3, "statement": 3, "pesa": 3, "reconcile_statement": 3,
            "unmatched": 4, "orphan": 4, "leftover": 4, "suspense": 4, "unknown": 4,
            "reference": 5, "account": 5,
            "api": 6, "request": 6, "requests": 6, "device": 6, "endpoint": 6,
            "route": 7, "routes": 7, "stage": 7, "stages": 7,
            "sms": 8, "message": 8, "language": 8, "receipt": 8,
            "upload": 9, "screen": 9, "counts": 9, "shows": 9,
            "code": 10, "codes": 10, "typed": 10, "normalised": 10,
        ]
        let calls = Counter()

        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var texts = 0
            func add(_ count: Int) { lock.lock(); texts += count; lock.unlock() }
            var embedded: Int { lock.lock(); defer { lock.unlock() }; return texts }
        }

        func embed(_ texts: [String]) async throws -> [[Float]] {
            calls.add(texts.count)
            return texts.map { text in
                var vector = [Float](repeating: 0, count: 20)
                for word in text.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "_" }) {
                    if let axis = Self.concepts[String(word)] {
                        vector[axis] += 1
                    } else {
                        let stable = word.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
                        vector[11 + stable % 9] += 0.1
                    }
                }
                vector[19] += 0.05
                return vector
            }
        }
    }

    private var top: URL!
    private var vault: Vault!
    private var embedder: ConceptEmbedder!
    private var target: LedgerCommit!
    private var anchored: [LedgerCommit] = []

    static let reconcile = "pay/payments/reconcile.py"
    static let matcher = "pay/payments/matcher.py"
    static let handlers = "pay/api/handlers.py"
    static let others = ["pay/api/handlers.py", "pay/fares/table.py", "pay/notify/sms.py", "pay/routes/stages.py", "pay/payments/suspense.py"]

    override func setUp() async throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files = [
            "vault/Home.md": "# Matatu\n\nThe ticketing service for route 46.\n",
            "pay/payments/reconcile.py": "from .matcher import ticket_for_line\n\ndef reconcile_statement(statement):\n    # each statement line: payment by reference, else suspense\n    for line in statement:\n        ticket = ticket_for_line(line)\n",
            "pay/payments/matcher.py": "def ticket_for_line(line):\n    # the payment reference names the ticket\n    return TICKETS.get(line.reference)\n",
            "pay/payments/suspense.py": "def add_to_suspense(line, reason):\n    SUSPENSE.append((line, reason))\n",
            "pay/api/handlers.py": "def handle(request):\n    # every api request from a conductor device, payment or ticket\n    return route(request)\n",
            "pay/fares/table.py": "FARES = {'town': 80}\n# fare per stage\n",
            "pay/notify/sms.py": "def send_receipt(phone, message):\n    pass\n",
            "pay/routes/stages.py": "STAGES = ['Kencom', 'Ngara']\n",
        ]
        for (path, text) in files {
            let url = top.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        embedder = ConceptEmbedder()
        vault = try Vault(project: top.appendingPathComponent("vault"), everything: true)
        // Approvals go to this test's own folder, never the person's (D-101).
        vault.stateFolder = top.appendingPathComponent("state")
        try vault.linkFolder(top.appendingPathComponent("pay"))
        try await vault.refresh(embedder: embedder)

        let ledger = Ledger(vault: vault)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        // The decision under test, kept first, so everything after it is newer.
        target = try ledger.commit(.decision, "reconcile_statement matches a statement line to a ticket by its account reference and nothing else.",
                                   body: "Rejected: matching on phone and amount.\nBecause: on Easter Monday 31 tickets were marked paid against the wrong passengers when a conductor paid for a group from one phone.",
                                   files: [Self.reconcile, Self.matcher], author: "claude-code", at: start)
        // 40 unrelated decisions, all newer, on the other files a search returns.
        let topics = ["Each conductor device is limited to 60 api requests a minute.", "Fares are rounded up to the next 10 shillings.",
                      "A receipt sms is sent in the passenger's language.", "Stages are named as conductors call them.",
                      "Suspense items are kept for 90 days."]
        for n in 0..<40 {
            try ledger.commit(.decision, "\(topics[n % topics.count]) Variant \(n).", body: "Because: reason number \(n) for this rule.",
                              files: [Self.others[n % Self.others.count]], author: "claude-code", at: start.addingTimeInterval(Double(10 + n)))
        }
        // Three newer decisions about other things, on the target's own file (E3's "anchored" condition).
        anchored = try [
            "reconcile_statement stores the provider's code on the ticket when it marks it paid.",
            "The upload screen shows counts of matched, suspended and skipped lines.",
            "Typed codes are normalised before lookup: upper-case, spaces removed.",
        ].enumerated().map { n, text in
            try ledger.commit(.decision, text, body: "Because: finance asked, \(n).", files: [Self.reconcile], author: "claude-code",
                              at: start.addingTimeInterval(Double(100 + n)))
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: top)
    }

    private func tools(_ embedder: Embedder?) -> VaultTools {
        VaultTools(vault: vault, embedder: embedder) { _ in FakeAnswerer() }
    }

    /// A request worded unlike the decision: no word of it is in the decision apart from "ticket".
    static let oddlyWorded = "Pair orphan M-Pesa payments with an open ticket bought by the same MSISDN for the same fare"

    func testTheRequestSharesFewWordsWithTheDecision() {
        let shared = Ledger.words(Self.oddlyWorded).intersection(Ledger.words(target.message + " " + target.body))
        XCTAssertLessThan(shared.count, 2, "the test request must not match by words: \(shared)")
    }

    func testCrowdedLedgerAMeaningMatchStillBringsTheDecisionWithASearch() async throws {
        let tools = tools(embedder)
        let found = try await tools.call("vault_search", arguments: ["query": Self.oddlyWorded])
        XCTAssertTrue(found.text.contains(Self.reconcile), found.text)
        // Among the first two: in this toy embedder the newer note on the same file about the payment code is as close.
        XCTAssertTrue(found.ledger.prefix(2).contains(target.id), "best matches first: \(found.ledger)")
        XCTAssertLessThanOrEqual(found.ledger.count, LedgerRelevance.limit)
        // Ahead of every one of the 40 newer decisions on the other files the search returned.
        let position = try XCTUnwrap(found.ledger.firstIndex(of: target.id))
        let anchoredIDs = Set(anchored.map(\.id))
        XCTAssertTrue(found.ledger.prefix(position).allSatisfy(anchoredIDs.contains), "\(found.ledger)")
        // Handed over with its reason (D-81).
        XCTAssertTrue(found.text.contains("Because: on Easter Monday 31 tickets"), found.text)
    }

    func testCrowdedLedgerAReadAfterTheSearchCarriesTheDecision() async throws {
        let tools = tools(embedder)
        _ = try await tools.call("vault_search", arguments: ["query": Self.oddlyWorded])
        // matcher.py: the only decision on it is the target, so it comes first.
        let matcher = try await tools.call("vault_read", arguments: ["path": Self.matcher])
        XCTAssertEqual(matcher.ledger.first, target.id, "\(matcher.ledger)")
        // reconcile.py: four decisions rest on it; the target is among the first two, matched on the search's words.
        let reconcile = try await tools.call("vault_read", arguments: ["path": Self.reconcile])
        XCTAssertTrue(reconcile.ledger.prefix(2).contains(target.id), "\(reconcile.ledger)")
    }

    func testAReadWithNoSearchStillCarriesEveryDecisionOnTheFileThatFits() async throws {
        // Four decisions rest on reconcile.py; with five slots all come, though nothing says which one the program needs.
        let read = try await tools(embedder).call("vault_read", arguments: ["path": Self.reconcile])
        XCTAssertTrue(read.ledger.contains(target.id), "\(read.ledger)")
        for note in anchored { XCTAssertTrue(read.ledger.contains(note.id)) }
    }

    func testWhenTheEmbedderIsDownWordsAndFilesStillChoose() async throws {
        let tools = tools(BrokenEmbedder())
        let found = try await tools.call("vault_search", arguments: ["query": "phone and amount matching for a statement line"])
        XCTAssertFalse(found.isError)
        XCTAssertEqual(found.ledger.first, target.id, "\(found.ledger)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: LedgerVectors(vault: vault).file.path))
    }

    func testDecisionVectorsAreKeptAndEmbeddedOnce() async throws {
        let tools = tools(embedder)
        _ = try await tools.call("vault_search", arguments: ["query": Self.oddlyWorded])
        XCTAssertTrue(FileManager.default.fileExists(atPath: LedgerVectors(vault: vault).file.path))
        let after = embedder.calls.embedded
        _ = try await tools.call("vault_search", arguments: ["query": "orphan payments by sender number"])
        // Only the new question is embedded; the 44 notes come from the store.
        XCTAssertEqual(embedder.calls.embedded - after, 1)
        let fresh = ConceptEmbedder()
        let kept = await LedgerVectors(vault: vault).vectors(for: Ledger(vault: vault).all(), embedder: fresh, dimension: 20)
        XCTAssertEqual(kept.count, 44)
        XCTAssertEqual(fresh.calls.embedded, 0)
        // Vectors of another length came from another model: made again.
        let other = await LedgerVectors(vault: vault).vectors(for: Ledger(vault: vault).all(), embedder: fresh, dimension: 7)
        XCTAssertTrue(other.isEmpty)
        XCTAssertEqual(fresh.calls.embedded, 44)
    }

    // MARK: The choice itself, without a vault

    private func note(_ id: String, _ message: String, because: String = "it was decided.", files: [String] = [], at: Double) -> LedgerCommit {
        LedgerCommit(id: id, branch: "main", parent: nil, kind: .decision, message: message, body: "Because: " + because, author: "test",
                     cites: Dictionary(uniqueKeysWithValues: files.map { ($0, "h") }), at: Date(timeIntervalSince1970: at))
    }

    func testAHigherRankedFileBeatsALowerOneAndRecencyOnlyBreaksTies() {
        let first = note("a", "Alpha rule.", files: ["one.py"], at: 1)
        let fourth = note("b", "Beta rule.", files: ["four.py"], at: 2)
        let tieOld = note("c", "Gamma rule.", files: ["two.py"], at: 3)
        let tieNew = note("d", "Delta rule.", files: ["two.py"], at: 4)
        let request = LedgerRelevance.Request(question: "", ranked: ["one.py", "two.py", "three.py", "four.py"])
        let chosen = LedgerRelevance.choose(from: [first, fourth, tieOld, tieNew], wrong: [], for: request).map(\.id)
        XCTAssertEqual(chosen, ["a", "d", "c", "b"])
    }

    func testANoteOnNoFileShownMustMatchByItselfAndAWrongOneNeverComes() {
        let related = note("r", "Statement lines are matched by account reference only.", at: 1)
        let unrelated = note("u", "Stages are named as conductors call them.", at: 2)
        let wrong = note("w", "Statement lines are matched by account reference and phone.", at: 3)
        let request = LedgerRelevance.Request(question: "how are statement lines matched to an account reference")
        let chosen = LedgerRelevance.choose(from: [related, unrelated, wrong], wrong: ["w"], for: request).map(\.id)
        XCTAssertEqual(chosen, ["r"])
    }

    func testMeaningOutranksAFileTieAndAReadBonusCounts() {
        let query: [Float] = [1, 0, 0]
        let close = note("close", "Matched by reference only.", files: ["r.py"], at: 1)
        let far = note("far", "Counts are shown on the upload screen.", files: ["r.py"], at: 2)
        let near = note("near", "Something on the neighbour.", files: ["n.py"], at: 3)
        let vectors: [String: [Float]] = ["close": [0.9, 0.1, 0], "far": [0.2, 1, 0], "near": [0.2, 0, 1]]
        let request = LedgerRelevance.Request(question: "x", ranked: ["r.py"], near: ["n.py": 0], read: "r.py",
                                              questionVector: query, vectors: vectors)
        XCTAssertEqual(LedgerRelevance.choose(from: [close, far, near], wrong: [], for: request).map(\.id), ["close", "far", "near"])
    }

    func testTheRoomIsHeldAndAReasonIsNeverCut() {
        let long = String(repeating: "word ", count: 120)  // about 600 characters a reason
        let notes = (0..<8).map { note("n\($0)", "Rule \($0).", because: long + "end of reason \($0).", files: ["f.py"], at: Double($0)) }
        let chosen = LedgerRelevance.choose(from: notes, wrong: [], for: LedgerRelevance.Request(question: "", ranked: ["f.py"]))
        XCTAssertFalse(chosen.isEmpty)
        XCTAssertLessThanOrEqual(chosen.map { LedgerRelevance.text(of: $0).count }.reduce(0, +), LedgerRelevance.characters)
        XCTAssertLessThan(chosen.count, notes.count)
        for commit in chosen { XCTAssertTrue(LedgerRelevance.text(of: commit).hasSuffix("end of reason \(commit.id.dropFirst()).")) }
        // One note longer than the whole room still comes, whole.
        let huge = note("huge", "Big.", because: String(repeating: "long ", count: 700) + "the end.", files: ["f.py"], at: 99)
        let alone = LedgerRelevance.choose(from: [huge], wrong: [], for: LedgerRelevance.Request(question: "", ranked: ["f.py"]))
        XCTAssertEqual(alone.map(\.id), ["huge"])
    }
}
