import BurrowCore
import Foundation

/// One session read from a program's own transcript, in one shape whatever the program (D-117): Claude Code's JSON-lines
/// transcript, or a Codex rollout. Unknown lines are skipped, so a format change loses detail, never the reading.
public struct SessionText: Sendable {
    public enum Program: String, Codable, Sendable { case claudeCode = "claude-code", codex }

    /// One message or tool step, as it was said.
    public struct Piece: Sendable, Equatable {
        public enum Role: String, Sendable { case person, model, call, result }
        /// The first 8 characters of the entry's id, or "c" and its line number for a Codex record.
        public var ref: String
        public var role: Role
        public var text: String
        /// The tool a call or result belongs to.
        public var tool: String?
        public var at: Date?
        /// Before the last compaction and not carried past it: the model no longer has these words.
        public var compacted: Bool = false
    }

    /// Context size after one request: input, cache reads and cache writes together.
    public struct Usage: Sendable, Equatable {
        public var at: Date?
        public var context: Int
        public var output: Int
    }

    public var program: Program
    public var id: String
    public var cwd: String?
    public var title: String?
    public var model: String?
    public var pieces: [Piece] = []
    public var usage: [Usage] = []
    /// Each compaction, with the context size before and after when the program says.
    public var compactions: [(at: Date?, before: Int?, after: Int?)] = []

    public var started: Date? { pieces.first?.at ?? usage.first?.at }
    public var ended: Date? { pieces.last?.at ?? usage.last?.at }
    public var requests: [Piece] { pieces.filter { $0.role == .person } }

    /// A name a person would recognise: the program's own title, else the first request's first words.
    public var name: String {
        if let title, !title.isEmpty { return title }
        let first = requests.first?.text.replacingOccurrences(of: "\n", with: " ") ?? "untitled"
        return String(first.prefix(70))
    }

    static let stamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plainStamp = ISO8601DateFormatter()
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return stamp.date(from: text) ?? plainStamp.date(from: text)
    }

    /// What Claude Code put in the person's turn that the person did not type.
    static func typed(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("<") && !trimmed.hasPrefix("[Request interrupted") && !trimmed.hasPrefix("Caveat:")
    }

    static func resultText(_ content: Any?) -> String {
        if let text = content as? String { return text }
        return (content as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    static func compactInput(_ input: Any?) -> String {
        guard let input = input as? [String: Any] else { return "" }
        for key in ["command", "file_path", "pattern", "path", "url", "query", "description", "prompt"] {
            if let value = input[key] as? String, !value.isEmpty { return value }
        }
        let data = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(String(data: data, encoding: .utf8)?.prefix(400) ?? "")
    }

    // MARK: Claude Code

    public static func claudeCode(_ text: String, id fallback: String) -> SessionText {
        var session = SessionText(program: .claudeCode, id: fallback)
        var lastBoundary: Int?
        var preserved = Set<String>()
        var uuids: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            let type = entry["type"] as? String ?? ""
            if let id = entry["sessionId"] as? String, session.id == fallback || session.id.isEmpty { session.id = id }
            if session.cwd == nil, let cwd = entry["cwd"] as? String { session.cwd = cwd }
            switch type {
            case "custom-title": if let title = entry["customTitle"] as? String { session.title = title }
            case "ai-title": if session.title == nil, let title = entry["aiTitle"] as? String { session.title = title }
            case "summary": if session.title == nil, let title = entry["summary"] as? String { session.title = title }
            case "system" where entry["subtype"] as? String == "compact_boundary":
                let meta = entry["compactMetadata"] as? [String: Any] ?? [:]
                session.compactions.append((date(entry["timestamp"]), meta["preTokens"] as? Int, meta["postTokens"] as? Int))
                lastBoundary = session.pieces.count
                preserved = Set(((meta["preservedMessages"] as? [String: Any])?["allUuids"] as? [String] ?? []).map { String($0.prefix(8)) })
            default: break
            }
            guard ["user", "assistant"].contains(type), let message = entry["message"] as? [String: Any],
                  entry["isCompactSummary"] as? Bool != true, entry["isMeta"] as? Bool != true else { continue }
            let ref = String((entry["uuid"] as? String ?? "").prefix(8))
            let at = date(entry["timestamp"])
            if type == "assistant" {
                if let model = message["model"] as? String, !model.hasPrefix("<") { session.model = model }
                if let usage = message["usage"] as? [String: Any] {
                    let context = (usage["input_tokens"] as? Int ?? 0) + (usage["cache_read_input_tokens"] as? Int ?? 0) + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                    // One request can be written as several entries (text, then each tool call) with the same usage.
                    let last = session.usage.last
                    if context > 0, !(last?.context == context && last?.output == usage["output_tokens"] as? Int ?? 0) {
                        session.usage.append(Usage(at: at, context: context, output: usage["output_tokens"] as? Int ?? 0))
                    }
                }
            }
            uuids.append(ref)
            if let words = message["content"] as? String {
                if type == "user" ? typed(words) : true { session.pieces.append(Piece(ref: ref, role: type == "user" ? .person : .model, text: words, at: at)) }
                continue
            }
            for part in message["content"] as? [[String: Any]] ?? [] {
                switch part["type"] as? String {
                case "text":
                    let words = part["text"] as? String ?? ""
                    if type == "user" { if typed(words) { session.pieces.append(Piece(ref: ref, role: .person, text: words, at: at)) } }
                    else if !words.isEmpty { session.pieces.append(Piece(ref: ref, role: .model, text: words, at: at)) }
                case "tool_use":
                    session.pieces.append(Piece(ref: ref, role: .call, text: compactInput(part["input"]), tool: part["name"] as? String, at: at))
                case "tool_result":
                    session.pieces.append(Piece(ref: ref, role: .result, text: resultText(part["content"]), at: at))
                default: break
                }
            }
        }
        if let lastBoundary {
            for index in 0..<lastBoundary where !preserved.contains(session.pieces[index].ref) { session.pieces[index].compacted = true }
        }
        return session
    }

    // MARK: Codex

    public static func codex(_ text: String, id fallback: String) -> SessionText {
        var session = SessionText(program: .codex, id: fallback)
        var number = 0
        var lastCompaction: Int?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            number += 1
            guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            let payload = record["payload"] as? [String: Any] ?? [:]
            let at = date(record["timestamp"])
            let ref = "c\(number)"
            switch record["type"] as? String {
            case "session_meta":
                if let id = (payload["id"] ?? payload["session_id"]) as? String { session.id = id }
                session.cwd = payload["cwd"] as? String ?? session.cwd
            case "turn_context":
                session.model = payload["model"] as? String ?? session.model
                session.cwd = payload["cwd"] as? String ?? session.cwd
            case "compacted":
                session.compactions.append((at, nil, nil))
                lastCompaction = session.pieces.count
            case "event_msg":
                if payload["type"] as? String == "token_count", let info = payload["info"] as? [String: Any],
                   let last = info["last_token_usage"] as? [String: Any] {
                    let context = (last["input_tokens"] as? Int ?? 0)
                    if context > 0 { session.usage.append(Usage(at: at, context: context, output: last["output_tokens"] as? Int ?? 0)) }
                }
                if payload["type"] as? String == "thread_name_updated" || payload["type"] as? String == "thread_renamed",
                   let name = (payload["thread_name"] ?? payload["name"]) as? String { session.title = name }
            case "response_item":
                switch payload["type"] as? String {
                case "message":
                    let role = payload["role"] as? String ?? ""
                    let words = (payload["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
                    if role == "user", typed(words) { session.pieces.append(Piece(ref: ref, role: .person, text: words, at: at)) }
                    if role == "assistant", !words.isEmpty { session.pieces.append(Piece(ref: ref, role: .model, text: words, at: at)) }
                case "function_call", "custom_tool_call", "local_shell_call":
                    let input = (payload["arguments"] ?? payload["input"] ?? payload["action"]).map { value -> String in
                        if let text = value as? String, let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) { return compactInput(object) }
                        return (value as? String) ?? compactInput(value)
                    } ?? ""
                    session.pieces.append(Piece(ref: ref, role: .call, text: input, tool: payload["name"] as? String ?? "shell", at: at))
                case "function_call_output", "custom_tool_call_output", "local_shell_call_output":
                    var output = payload["output"]
                    if let text = output as? String, let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        output = object["output"] ?? text
                    }
                    session.pieces.append(Piece(ref: ref, role: .result, text: (output as? String) ?? resultText(output), at: at))
                default: break
                }
            default: break
            }
        }
        if let lastCompaction { for index in 0..<lastCompaction { session.pieces[index].compacted = true } }
        return session
    }

    /// The session as Claude Code transcript lines, so what folds a Claude Code session (Fold.make) folds any program's.
    public func asClaudeTranscript() -> String {
        var lines: [String] = []
        var number = 0
        for piece in pieces {
            number += 1
            let uuid = String(format: "%@-%08d", piece.ref.padding(toLength: 8, withPad: "0", startingAt: 0), number)
            var entry: [String: Any] = ["uuid": uuid, "sessionId": id]
            if let at = piece.at { entry["timestamp"] = Self.stamp.string(from: at) }
            switch piece.role {
            case .person: entry["type"] = "user"; entry["message"] = ["role": "user", "content": piece.text]
            case .model: entry["type"] = "assistant"; entry["message"] = ["role": "assistant", "content": [["type": "text", "text": piece.text]]]
            case .call:
                entry["type"] = "assistant"
                let key = piece.tool == "Read" ? "file_path" : "command"
                entry["message"] = ["role": "assistant", "content": [["type": "tool_use", "id": "t\(number)", "name": piece.tool ?? "shell", "input": [key: piece.text]]]]
            case .result: entry["type"] = "user"; entry["message"] = ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t\(number - 1)", "content": piece.text]]]
            }
            if let data = try? JSONSerialization.data(withJSONObject: entry, options: [.withoutEscapingSlashes]), let text = String(data: data, encoding: .utf8) { lines.append(text) }
        }
        return lines.joined(separator: "\n")
    }
}

/// Finding the exact words that match a question, by the words they share, weighted so a rare word (a port number, an
/// error code, a function name) counts for more than a common one (BM25). No model and no embedding: it runs inside a hook
/// that Claude Code waits for, on every message (D-116).
public enum WordMatch {
    static let stop: Set<String> = ["the", "and", "for", "that", "this", "with", "you", "are", "was", "what", "which", "when", "where", "how",
                                    "did", "does", "can", "could", "would", "should", "have", "has", "had", "not", "but", "from", "they",
                                    "them", "then", "there", "their", "will", "just", "about", "into", "your", "our", "its", "it's", "all",
                                    "any", "one", "now", "use", "using", "used", "make", "made", "also", "let", "lets", "please", "again",
                                    "earlier", "before", "said", "tell", "told", "ask", "asked", "remember", "session", "were", "been", "being",
                                    "some", "more", "most", "very", "who", "why", "yes", "out", "get", "got", "want", "need", "like", "see"]

    /// Lower-case words of three or more characters, and every word with a digit, dot, underscore or capital inside it,
    /// as written (a code name, a version, a port).
    public static func terms(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-") }) {
            let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
            let lower = word.lowercased()
            guard lower.count >= 3 || word.contains(where: \.isNumber), !stop.contains(lower) else { continue }
            out.append(lower)
        }
        return out
    }

    /// A word a person would only type if they meant that exact thing.
    /// A short number is not: "46" is a route, a row count and a millisecond figure in the same log (the first proof run
    /// handed back a log line for "route 46"). A number of four digits or more, a code name with digits in it (0x5f3a,
    /// tkt00042), a dotted or underscored name and a long word are.
    static func isSpecific(_ term: String) -> Bool {
        let digits = term.filter(\.isNumber).count
        let letters = term.filter(\.isLetter).count
        if digits > 0 { return digits >= 4 || letters > 0 }
        return term.contains("_") || term.contains(".") || term.count >= 9
    }

    public struct Hit: Sendable {
        public var index: Int
        public var score: Double
        public var matched: Set<String>
    }

    /// The documents that match `query` best, best first. A document needs two of the query's words, or one specific
    /// word, to count: one common word in common is noise, and handing back noise costs context on every message.
    public static func rank(_ query: String, documents: [String], top: Int = 3) -> [Hit] {
        let wanted = Array(Set(terms(query)))
        guard !wanted.isEmpty, !documents.isEmpty else { return [] }
        let docs = documents.map { terms($0) }
        let average = Double(docs.reduce(0) { $0 + $1.count }) / Double(max(1, docs.count))
        var frequency: [String: Int] = [:]
        for doc in docs { for term in Set(doc) where wanted.contains(term) { frequency[term, default: 0] += 1 } }
        var hits: [Hit] = []
        for (index, doc) in docs.enumerated() {
            var counts: [String: Int] = [:]
            for term in doc where frequency[term] != nil { counts[term, default: 0] += 1 }
            guard !counts.isEmpty else { continue }
            let matched = Set(counts.keys)
            guard matched.count >= 2 || matched.contains(where: isSpecific) else { continue }
            var score = 0.0
            for (term, count) in counts {
                let n = Double(frequency[term] ?? 1)
                let idf = log(1 + (Double(docs.count) - n + 0.5) / (n + 0.5))
                let tf = Double(count) * 2.2 / (Double(count) + 1.2 * (0.25 + 0.75 * Double(doc.count) / max(1, average)))
                score += idf * tf * (isSpecific(term) ? 1.5 : 1)
            }
            hits.append(Hit(index: index, score: score, matched: matched))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(top))
    }

    /// The part of `text` around its first matching word, at most `characters` long.
    public static func window(_ text: String, around matched: Set<String>, characters: Int) -> String {
        guard text.count > characters else { return text }
        let lower = text.lowercased()
        let first = matched.compactMap { lower.range(of: $0)?.lowerBound }.min() ?? lower.startIndex
        let offset = lower.distance(from: lower.startIndex, to: first)
        let start = max(0, offset - characters / 3)
        let from = text.index(text.startIndex, offsetBy: min(start, text.count))
        let to = text.index(from, offsetBy: min(characters, text.distance(from: from, to: text.endIndex)))
        return (start > 0 ? "…" : "") + String(text[from..<to]) + (to < text.endIndex ? "…" : "")
    }
}
