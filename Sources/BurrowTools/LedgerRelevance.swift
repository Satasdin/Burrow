import BurrowCore
import CryptoKit
import Foundation

/// Which Ledger notes come with a search or a read: the ones that fit the request best, not the newest (D-99).
///
/// E3 (14 November, `burrow-film/v4/runs/wording`) found the old choice weaker than a plain vector search: any decision
/// citing any file a search returned scored the same, ties went to the newest, only 3 were attached, and the request's
/// words were never consulted once a file matched. With 40 unrelated decisions in the Ledger, the payment decision came
/// with 12 of 20 oddly worded tasks, and with 3 newer decisions on its own file, with none.
///
/// A note's score is the sum of three parts, each between 0 and 1 before its weight:
/// - **meaning**: how close the note's own words (statement, Because, Rejected) are to the request, by the vault's
///   embedder against the vault's usual closeness for that request, blended with shared words; shared words alone when
///   the embedder is down or the vault has no vectors.
/// - **file** (weight 0.6): how high the files it cites ranked in this search, `3 / (3 + rank)`, half that for a file one
///   import step from a ranked one (D-75).
/// - **read** (weight 0.25): it cites the file actually being read.
/// Recency only breaks ties. A note on no file shown must match by meaning or words on its own to come at all. Up to
/// `limit` notes, held to `characters`: a note that does not fit is left out whole, so a reason is never cut (D-81).
/// The weights were set from queries written for the purpose, not from E3's tasks.
public enum LedgerRelevance {
    public static let limit = 5
    public static let characters = 2_400
    static let fileWeight = 0.6
    static let readWeight = 0.25
    /// `3 / (3 + rank)`: the top file 1, the fourth 0.5, the tenth 0.23.
    static let rankScale = 3.0
    /// Closeness above the request's usual closeness to every note that counts as a full match. For
    /// qwen3-embedding:0.6b a note on the request's subject sits about 0.3 to 0.45 above the median note.
    static let meaningSpan: Float = 0.3
    /// With fewer notes than this the median says little, so a typical closeness between unrelated texts stands in.
    static let fewNotes = 8
    static let unrelatedCloseness: Float = 0.35
    /// A note on no file shown comes only when it matches this well by meaning (0 to 1).
    static let meaningGate = 0.5

    public struct Request {
        public var question: String
        /// The files the search returned, best first.
        public var ranked: [String]
        /// Files one import step from a ranked file, with the rank of the file they neighbour.
        public var near: [String: Int]
        /// The file being read, when this is a read.
        public var read: String?
        public var questionVector: [Float]?
        /// Commit id to the vector of its `stated` text.
        public var vectors: [String: [Float]]

        public init(question: String, ranked: [String] = [], near: [String: Int] = [:], read: String? = nil,
                    questionVector: [Float]? = nil, vectors: [String: [Float]] = [:]) {
            self.question = question
            self.ranked = ranked
            self.near = near
            self.read = read
            self.questionVector = questionVector
            self.vectors = vectors
        }
    }

    /// What a note is matched on: its statement with its reasons, as it is handed over.
    public static func text(of commit: LedgerCommit) -> String { commit.stated }

    /// The notes for a request, best first.
    public static func choose(from commits: [LedgerCommit], wrong: Set<String>, for request: Request,
                              limit: Int = LedgerRelevance.limit, characters: Int = LedgerRelevance.characters) -> [LedgerCommit] {
        scored(from: commits, wrong: wrong, for: request).reduce(into: (kept: [LedgerCommit](), used: 0)) { out, pick in
            guard out.kept.count < limit else { return }
            let length = text(of: pick.commit).count
            // The best note always comes, however long; after it, a note that would pass the room is left out whole.
            guard out.kept.isEmpty || out.used + length <= characters else { return }
            out.kept.append(pick.commit)
            out.used += length
        }.kept
    }

    /// Every note that qualifies, with its score, best first. Recency breaks ties.
    static func scored(from commits: [LedgerCommit], wrong: Set<String>, for request: Request) -> [(commit: LedgerCommit, score: Double)] {
        let candidates = commits.filter { [.fact, .decision, .correction].contains($0.kind) && !wrong.contains($0.id) }
        guard !candidates.isEmpty else { return [] }
        let words = Ledger.words(request.question)
        let place = Dictionary(request.ranked.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let closeness = request.questionVector.map { query in
            candidates.compactMap { note in request.vectors[note.id].flatMap { cosine(query, $0) }.map { (note.id, $0) } }
        } ?? []
        let byID = Dictionary(closeness, uniquingKeysWith: { first, _ in first })
        let usual: Float = {
            guard closeness.count >= fewNotes else { return unrelatedCloseness }
            let sorted = closeness.map(\.1).sorted()
            return sorted[sorted.count / 2]
        }()
        var out: [(commit: LedgerCommit, score: Double)] = []
        for note in candidates {
            let shared = words.isEmpty ? 0 : words.intersection(Ledger.words(note.message + " " + note.body)).count
            // As before (D-69): at least two shared words, or one when the request is that short.
            let wordsMatch = !words.isEmpty && shared >= min(2, words.count)
            let byWords = words.isEmpty ? 0 : min(1, Double(shared) / Double(min(words.count, 4)))
            var meaning = byWords
            var meaningMatch = wordsMatch
            if let close = byID[note.id] {
                let byMeaning = Double(max(0, min(1, (close - usual) / meaningSpan)))
                meaning = 0.8 * byMeaning + 0.2 * byWords
                meaningMatch = byMeaning >= meaningGate || wordsMatch
            }
            let cited = note.cites.keys
            let fileScore = cited.map { path -> Double in
                if let rank = place[path] { return rankScale / (rankScale + Double(rank)) }
                if let rank = request.near[path] { return 0.5 * rankScale / (rankScale + Double(rank)) }
                return 0
            }.max() ?? 0
            let reads = request.read.map { cited.contains($0) } ?? false
            // A note on a file in front of the model always qualifies (D-69); any other must match the request itself.
            guard fileScore > 0 || meaningMatch else { continue }
            out.append((note, meaning + fileWeight * fileScore + (reads ? readWeight : 0)))
        }
        return out.sorted { $0.score == $1.score ? ($0.commit.at == $1.commit.at ? $0.commit.id > $1.commit.id : $0.commit.at > $1.commit.at) : $0.score > $1.score }
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot: Float = 0, left: Float = 0, right: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            left += a[i] * a[i]
            right += b[i] * b[i]
        }
        guard left > 0, right > 0 else { return nil }
        return dot / (left.squareRoot() * right.squareRoot())
    }
}

/// The vectors of the Ledger's notes, kept beside the index in `.burrow/ledger-vectors.json` by commit id, so each
/// note is embedded once (D-99). A commit's text never changes; the stored hash of the text it was embedded from is
/// checked anyway. Any failure leaves the notes without vectors, and they are matched by words.
public struct LedgerVectors {
    public let file: URL

    public init(vault: Vault) { file = vault.store.appendingPathComponent("ledger-vectors.json") }

    private struct Saved: Codable {
        var version = 1
        var vectors: [String: Entry] = [:]
    }

    private struct Entry: Codable {
        var hash: String
        var vector: String  // little-endian Float32, base64
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Vectors for the notes that can come with a lookup, embedding only those not kept yet. `dimension` is the length
    /// of the question's vector: kept vectors of another length came from another model and are made again.
    public func vectors(for commits: [LedgerCommit], embedder: Embedder, dimension: Int) async -> [String: [Float]] {
        let wanted = commits.filter { [.fact, .decision, .correction].contains($0.kind) }
        guard !wanted.isEmpty else { return [:] }
        var saved = (try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: file))) ?? Saved()
        var out: [String: [Float]] = [:]
        var missing: [LedgerCommit] = []
        for commit in wanted {
            if let entry = saved.vectors[commit.id], entry.hash == Self.hash(LedgerRelevance.text(of: commit)),
               let vector = Self.decode(entry.vector), vector.count == dimension {
                out[commit.id] = vector
            } else {
                missing.append(commit)
            }
        }
        guard !missing.isEmpty else { return out }
        var added = false
        var start = 0
        while start < missing.count {
            let batch = Array(missing[start..<min(missing.count, start + 32)])
            start += 32
            guard let made = try? await embedder.embed(batch.map(LedgerRelevance.text(of:))), made.count == batch.count else { break }
            for (commit, vector) in zip(batch, made) where vector.count == dimension {
                out[commit.id] = vector
                saved.vectors[commit.id] = Entry(hash: Self.hash(LedgerRelevance.text(of: commit)), vector: Self.encode(vector))
                added = true
            }
        }
        if added, let data = try? JSONEncoder().encode(saved) { try? data.write(to: file, options: .atomic) }
        return out
    }

    static func encode(_ vector: [Float]) -> String {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString()
    }

    static func decode(_ text: String) -> [Float]? {
        guard let data = Data(base64Encoded: text), data.count % MemoryLayout<Float>.size == 0 else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

extension VaultTools {
    /// The Ledger notes for a search or a read, chosen by relevance to the request (D-99), fenced as data, for the end
    /// of the result. A read has no words of its own, so it is matched against this connection's last search: the file
    /// a program opens is the one it found for that request. `ids` are the commits in the block (D-92).
    func ledgerNotes(for question: String, ranked: [String], read: String? = nil) async -> (text: String, ids: [String]) {
        guard ledgerNotesOn else { return ("", []) }
        if read == nil, !question.isEmpty { lastQuestion = question }
        let asked = read == nil ? question : (lastQuestion ?? "")
        let everything = ledger.all()
        var questionVector: [Float]?
        var vectors: [String: [Float]] = [:]
        if !asked.isEmpty, hasVectors, let embedder {
            questionVector = try? await vault.questionVector(asked, embedder: embedder)
            if let questionVector {
                vectors = await LedgerVectors(vault: vault).vectors(for: everything, embedder: embedder, dimension: questionVector.count)
            }
        }
        let request = LedgerRelevance.Request(question: asked, ranked: ranked, near: Self.near(ranked, in: vault), read: read,
                                              questionVector: questionVector, vectors: vectors)
        let notes = LedgerRelevance.choose(from: everything, wrong: Set(everything.compactMap(\.reverts)), for: request)
        guard !notes.isEmpty else { return ("", []) }
        let text = "\n\nNotes earlier sessions left in the Ledger, best match first: the ones that match this request most closely, rest on the files it found, or rest on a file these import or are imported by. Check them against the excerpts above before relying on them:\n"
            + AskLedger.block(notes, stale: ledger.staleness())
        return (text, notes.map(\.id))
    }

    /// Files one import step from the ranked ones, both ways (D-75), each with the best rank of a file it neighbours.
    static func near(_ ranked: [String], in vault: Vault) -> [String: Int] {
        let shown = Set(ranked)
        var out: [String: Int] = [:]
        for (rank, file) in ranked.enumerated() {
            for neighbour in (try? vault.neighbours(of: file)) ?? [] where neighbour.kind != .about && !shown.contains(neighbour.path) {
                out[neighbour.path] = min(out[neighbour.path] ?? rank, rank)
            }
        }
        return out
    }
}
