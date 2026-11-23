import CAMRCore
import CryptoKit
import Foundation

/// What CAMR does to a live session's context, each part switched on or off by the person (D-116). Kept in
/// `session-context.json` in CAMR's own folder, never in a vault: a vault can come from someone else, and these change
/// what a program shows its model.
public struct SessionSettings: Codable, Sendable, Equatable {
    /// Large Bash and Grep output is kept by CAMR and the model sees its head, tail, error lines and a handle.
    public var leanBash = true
    public var leanGrep = true
    /// A whole-file Read of a long file shows its first lines and outline, and says to read a range.
    public var leanRead = true
    /// Output longer than this many characters is kept and shortened.
    public var leanCharacters = 6_000
    /// A whole-file Read longer than this many lines is shortened.
    public var leanReadLines = 1_500
    /// On each message, the exact words that have left the context and match it are handed back.
    public var recall = true
    /// Before compacting, the summary is told what to keep word for word.
    public var steer = true
    /// Every session is kept in the archive, so any program can resume it later.
    public var archive = true
    /// Where the archive lives: nil for CAMR's own folder, or a folder the person chose (an external drive).
    public var archiveFolder: String?

    public init() {}

    public static func file(in folder: URL = CAMRPlaces.stateFolder) -> URL { folder.appendingPathComponent("session-context.json") }

    /// The person's settings, or the defaults when none were saved or the file can't be read.
    public static func load(from folder: URL = CAMRPlaces.stateFolder) -> SessionSettings {
        guard let data = try? Data(contentsOf: file(in: folder)) else { return SessionSettings() }
        return (try? JSONDecoder().decode(SessionSettings.self, from: data)) ?? SessionSettings()
    }

    public func save(to folder: URL = CAMRPlaces.stateFolder) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: Self.file(in: folder), options: .atomic)
    }

    // Decoding fills what an older file leaves out with the defaults, so a setting added later is on, not missing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SessionSettings()
        leanBash = try c.decodeIfPresent(Bool.self, forKey: .leanBash) ?? d.leanBash
        leanGrep = try c.decodeIfPresent(Bool.self, forKey: .leanGrep) ?? d.leanGrep
        leanRead = try c.decodeIfPresent(Bool.self, forKey: .leanRead) ?? d.leanRead
        leanCharacters = try c.decodeIfPresent(Int.self, forKey: .leanCharacters) ?? d.leanCharacters
        leanReadLines = try c.decodeIfPresent(Int.self, forKey: .leanReadLines) ?? d.leanReadLines
        recall = try c.decodeIfPresent(Bool.self, forKey: .recall) ?? d.recall
        steer = try c.decodeIfPresent(Bool.self, forKey: .steer) ?? d.steer
        archive = try c.decodeIfPresent(Bool.self, forKey: .archive) ?? d.archive
        archiveFolder = try c.decodeIfPresent(String.self, forKey: .archiveFolder)
    }
}

/// One thing CAMR did in a live session, written as it happens so the app's Session panel can show it (D-116).
public struct MeterEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case kept, shortened, recalled, steered, compacted, folded, archived, resumed, expanded }
    public var at: Date
    public var kind: Kind
    /// The tool or hook it came from: Bash, Read, Grep, UserPromptSubmit, PreCompact.
    public var tool: String
    /// Characters the model would have seen, and characters it saw instead. Recall: 0 and what was handed back.
    public var original: Int
    public var shown: Int
    public var handle: String?
    /// The command, the file, the first words of the message.
    public var label: String?

    public init(at: Date = Date(), kind: Kind, tool: String, original: Int = 0, shown: Int = 0, handle: String? = nil, label: String? = nil) {
        self.at = at; self.kind = kind; self.tool = tool; self.original = original; self.shown = shown; self.handle = handle; self.label = label
    }

    /// Characters kept out of the context.
    public var saved: Int { max(0, original - shown) }
}

/// Each session's events, one JSON line each, in CAMR's own folder: `meter/<session>.jsonl`.
public struct SessionMeter: Sendable {
    public let folder: URL

    public init(folder: URL = CAMRPlaces.stateFolder.appendingPathComponent("meter", isDirectory: true)) { self.folder = folder }

    func file(_ session: String) -> URL { folder.appendingPathComponent(FoldStore.safe(session) + ".jsonl") }

    public func record(_ event: MeterEvent, session: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var line = try? encoder.encode(event) else { return }
        line.append(0x0A)
        let url = file(session)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    public func events(session: String) -> [MeterEvent] {
        guard let text = try? String(contentsOf: file(session), encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(MeterEvent.self, from: Data($0.utf8)) }
    }

    /// Sessions with events, newest first.
    public func sessions() -> [(id: String, updated: Date)] {
        let names = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return names.filter { $0.pathExtension == "jsonl" }.map {
            ($0.deletingPathExtension().lastPathComponent, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }.sorted { $0.updated > $1.updated }
    }
}

/// Large tool output CAMR kept whole while the model saw a short form, by handle (D-116). In CAMR's own folder,
/// `kept/<session>/<handle>.txt`, readable only by this account, as Claude Code's own transcripts are.
public struct KeptStore: Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public var handle: String
        public var session: String
        public var tool: String
        public var label: String
        public var characters: Int
        public var lines: Int
        public var at: Date
    }

    public let folder: URL

    public init(folder: URL = CAMRPlaces.stateFolder.appendingPathComponent("kept", isDirectory: true)) { self.folder = folder }

    func sessionFolder(_ session: String) -> URL { folder.appendingPathComponent(FoldStore.safe(session), isDirectory: true) }

    /// Keeps `text` and returns its handle: "k" and six hex characters, short enough to type, unique within the session.
    public func keep(_ text: String, session: String, tool: String, label: String, at: Date = Date()) throws -> Entry {
        let place = sessionFolder(session)
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var seed = "\(session)\n\(tool)\n\(label)\n\(at.timeIntervalSince1970)\n" + text.prefix(4_000)
        var handle = ""
        repeat {
            handle = "k" + SHA256.hash(data: Data(seed.utf8)).prefix(3).map { String(format: "%02x", $0) }.joined()
            seed += "+"
        } while FileManager.default.fileExists(atPath: place.appendingPathComponent(handle + ".txt").path)
        let url = place.appendingPathComponent(handle + ".txt")
        try text.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let entry = Entry(handle: handle, session: session, tool: tool, label: String(label.prefix(300)), characters: text.count,
                          lines: text.split(separator: "\n", omittingEmptySubsequences: false).count, at: at)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entry).write(to: place.appendingPathComponent(handle + ".json"), options: .atomic)
        return entry
    }

    public func entries(session: String) -> [Entry] {
        let place = sessionFolder(session)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: place.path)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return names.filter { $0.hasSuffix(".json") }.compactMap {
            try? decoder.decode(Entry.self, from: Data(contentsOf: place.appendingPathComponent($0)))
        }.sorted { $0.at < $1.at }
    }

    /// The session a handle belongs to, searching every session when none is given.
    public func find(_ handle: String, session: String? = nil) -> Entry? {
        let clean = handle.trimmingCharacters(in: .whitespaces).lowercased()
        guard clean.range(of: #"^k[0-9a-f]{6}$"#, options: .regularExpression) != nil else { return nil }
        if let session, let entry = entries(session: session).first(where: { $0.handle == clean }) { return entry }
        let sessions = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in sessions {
            if let entry = entries(session: name).first(where: { $0.handle == clean }) { return entry }
        }
        return nil
    }

    public func text(_ entry: Entry) -> String? {
        try? String(contentsOf: sessionFolder(entry.session).appendingPathComponent(entry.handle + ".txt"), encoding: .utf8)
    }
}

/// Shortening one tool result for the model, after the tool has run, through Claude Code's PostToolUse hook and its
/// `updatedToolOutput` (D-116). The whole output is kept by handle first; when keeping fails, nothing is shortened.
public enum Lean {
    /// Lines kept from the start and the end of a long output.
    static let headLines = 30
    static let tailLines = 30
    /// Lines a long whole-file read keeps from the top.
    static let readHead = 120
    static let lineLimit = 400

    public struct Outcome {
        /// The PostToolUse reply for Claude Code, as JSON text.
        public let reply: String
        public let event: MeterEvent
    }

    /// The PostToolUse reply for this event, or nil to leave the output as it is.
    public static func shorten(event: [String: Any], settings: SessionSettings, store: KeptStore, now: Date = Date()) -> Outcome? {
        guard let tool = event["tool_name"] as? String, let session = event["session_id"] as? String else { return nil }
        let input = event["tool_input"] as? [String: Any] ?? [:]
        let response = event["tool_response"] as? [String: Any] ?? [:]
        switch tool {
        case "Bash" where settings.leanBash:
            // A command left running in the background reports its own handle; it is not ours to shorten.
            guard input["run_in_background"] as? Bool != true, response["isImage"] as? Bool != true else { return nil }
            let stdout = response["stdout"] as? String ?? ""
            let stderr = response["stderr"] as? String ?? ""
            let whole = stderr.isEmpty ? stdout : stdout + (stdout.isEmpty ? "" : "\n") + "[stderr]\n" + stderr
            guard whole.count > settings.leanCharacters else { return nil }
            let label = String((input["command"] as? String ?? "").prefix(300))
            guard let entry = try? store.keep(whole, session: session, tool: tool, label: label, at: now) else { return nil }
            let short = shortForm(whole, entry: entry)
            var output: [String: Any] = ["stdout": short, "stderr": "", "interrupted": response["interrupted"] as? Bool ?? false, "isImage": false]
            if let flag = response["noOutputExpected"] as? Bool { output["noOutputExpected"] = flag }
            return Outcome(reply: reply(output), event: MeterEvent(at: now, kind: .kept, tool: tool, original: whole.count, shown: short.count, handle: entry.handle, label: label))
        case "Grep" where settings.leanGrep:
            // Only the content mode prints lines; file lists and counts are short already.
            guard let content = response["content"] as? String, content.count > settings.leanCharacters else { return nil }
            let label = "grep " + (input["pattern"] as? String ?? "") + ((input["path"] as? String).map { " in " + $0 } ?? "")
            guard let entry = try? store.keep(content, session: session, tool: tool, label: label, at: now) else { return nil }
            let short = shortForm(content, entry: entry)
            var output = response
            output["content"] = short
            output["numLines"] = short.split(separator: "\n", omittingEmptySubsequences: false).count
            return Outcome(reply: reply(output), event: MeterEvent(at: now, kind: .kept, tool: tool, original: content.count, shown: short.count, handle: entry.handle, label: label))
        case "Read" where settings.leanRead:
            // A read that asked for a range got what it asked for; only a whole-file read of a long file is shortened.
            guard input["offset"] == nil, input["limit"] == nil, response["type"] as? String == "text",
                  let file = response["file"] as? [String: Any], let content = file["content"] as? String,
                  let path = file["filePath"] as? String else { return nil }
            let total = file["totalLines"] as? Int ?? 0
            guard total > settings.leanReadLines else { return nil }
            let lines = content.components(separatedBy: "\n")
            let head = lines.prefix(readHead).joined(separator: "\n")
            var newFile = file
            newFile["content"] = head
            newFile["numLines"] = min(readHead, lines.count)
            let note = readNote(path: path, total: total, shownLines: min(readHead, lines.count))
            let output: [String: Any] = ["type": "text", "file": newFile]
            return Outcome(reply: reply(output, context: note),
                           event: MeterEvent(at: now, kind: .shortened, tool: tool, original: content.count, shown: head.count + note.count, label: path))
        default:
            return nil
        }
    }

    /// Head, the error lines from the middle, tail, and where the rest is. Long lines are clipped.
    static func shortForm(_ text: String, entry: KeptStore.Entry) -> String {
        let lines = text.components(separatedBy: "\n")
        func clip(_ line: String) -> String { line.count > lineLimit ? String(line.prefix(lineLimit)) + "… (line cut)" : line }
        guard lines.count > headLines + tailLines else {
            // Few lines, but very long ones: the start and the end of the text.
            let start = String(text.prefix(2_500)), end = String(text.suffix(1_500))
            return start + "\n… [\(text.count - 4_000) characters in the middle kept by CAMR] …\n" + end + "\n" + footer(entry)
        }
        let middle = lines[headLines..<(lines.count - tailLines)].joined(separator: "\n")
        let errors = Fold.errorLines(middle, failed: false)
        var out = lines.prefix(headLines).map(clip)
        out.append("… [lines \(headLines + 1)–\(lines.count - tailLines) of \(lines.count) kept by CAMR, not shown] …")
        if !errors.isEmpty {
            out.append("Error lines among them, exactly as printed:")
            out += errors.map { "  " + $0 }
        }
        out += lines.suffix(tailLines).map(clip)
        out.append(footer(entry))
        return out.joined(separator: "\n")
    }

    /// Claude Code cuts Bash output at 30,000 characters (BASH_MAX_OUTPUT_LENGTH) before any hook sees it.
    static let claudeCodeCut = 29_900

    static func footer(_ entry: KeptStore.Entry) -> String {
        let cut = entry.tool == "Bash" && entry.characters >= claudeCodeCut
            ? " Claude Code had already cut this output at about 30,000 characters before CAMR got it: nothing after that was kept. Filter the command (grep, tail, head) for the rest."
            : ""
        return "[CAMR kept this whole output (\(entry.lines) lines, \(entry.characters) characters) as \(entry.handle), to keep your context small. "
            + "It is the real output, shortened, not a summary. For any part of it: camr_expand with handle \(entry.handle) and lines (e.g. 200-260) or find (words to match).\(cut)]"
    }

    static func readNote(path: String, total: Int, shownLines: Int) -> String {
        var note = "CAMR showed only the first \(shownLines) of \(total) lines of \(path), to keep your context small. Read the part you need with offset and limit before editing it."
        if Outline.understands(path), let text = try? String(contentsOfFile: path, encoding: .utf8), let outline = Outline.of(text, path: path), !outline.symbols.isEmpty {
            let listed = outline.symbols.prefix(80).map { "\($0.qualified) \($0.startLine)-\($0.endLine)" }
            note += " Its outline (name, first and last line): " + listed.joined(separator: "; ") + (outline.symbols.count > 80 ? "; and \(outline.symbols.count - 80) more." : ".")
        }
        return note
    }

    static func reply(_ output: [String: Any], context: String? = nil) -> String {
        var specific: [String: Any] = ["hookEventName": "PostToolUse", "updatedToolOutput": output]
        if let context { specific["additionalContext"] = context }
        let data = (try? JSONSerialization.data(withJSONObject: ["hookSpecificOutput": specific], options: [.withoutEscapingSlashes])) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// What camr_expand gives back: lines by number, lines matching words with two lines around each, or the start.
    public static func expand(_ entry: KeptStore.Entry, text: String, lines range: String?, find: String?, characters: Int = 12_000) -> String {
        let all = text.components(separatedBy: "\n")
        var picked: [(Int, String)] = []
        if let range, let parts = Optional(range.split(whereSeparator: { $0 == "-" || $0 == ":" || $0 == "," }).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }), !parts.isEmpty {
            let start = max(1, parts[0]), end = min(all.count, parts.count > 1 ? parts[1] : parts[0] + 60)
            if start <= end { picked = (start...end).map { ($0, all[$0 - 1]) } }
        } else if let find, !find.trimmingCharacters(in: .whitespaces).isEmpty {
            let words = find.lowercased().split(separator: " ").map(String.init)
            var keep = Set<Int>()
            for (index, line) in all.enumerated() where words.allSatisfy(line.lowercased().contains) {
                for near in max(0, index - 2)...min(all.count - 1, index + 2) { keep.insert(near) }
            }
            picked = keep.sorted().map { ($0 + 1, all[$0]) }
            if picked.isEmpty { return "No line of \(entry.handle) holds \"\(find)\". It has \(all.count) lines; ask for lines instead." }
        } else {
            picked = all.prefix(200).enumerated().map { ($0.offset + 1, $0.element) }
        }
        var out = "Output \(entry.handle) (\(entry.tool): \(entry.label)), \(all.count) lines in all:\n"
        var previous = 0
        for (number, line) in picked {
            if previous != 0, number != previous + 1 { out += "…\n" }
            out += "\(number)\t\(line)\n"
            previous = number
            if out.count > characters { out += "… (cut at \(characters) characters; ask for a smaller range)\n"; break }
        }
        return out
    }
}
