import Foundation

/// A stretch of a file a model was given, to check what its answer names against.
public struct ShownLines: Sendable, Equatable {
    public let path: String
    public let startLine: Int
    public let endLine: Int

    public init(path: String, startLine: Int, endLine: Int) {
        self.path = path
        self.startLine = startLine
        self.endLine = endLine
    }

    public init(_ excerpt: Excerpt) { self.init(path: excerpt.path, startLine: excerpt.startLine, endLine: excerpt.endLine) }

    /// The same test `Engine.citations` uses: the path as given, its tail, or its file name, and a line inside the stretch.
    func covers(_ cited: String, line: Int) -> Bool {
        (path == cited || path.hasSuffix("/" + cited) || (path as NSString).lastPathComponent == (cited as NSString).lastPathComponent)
            && line >= startLine && line <= endLine
    }
}

/// An answer whose citations were checked against what the model was given (D-91).
public struct CheckedAnswer: Sendable, Equatable {
    /// The answer, with every place it named but was not given taken out where it stood in brackets, and marked where it
    /// was part of a sentence, so no such place reads as a source.
    public let text: String
    /// Those places, as named: "notes/plan.md:12", "Ledger 20261114-065345-a355".
    public let unverified: [String]
    /// The Ledger commits it named that it was given, by id.
    public let ledgerCited: [String]
}

/// Holds streamed words until a line ends, then lets the line out with its citations checked (D-91). `camr chat` and
/// `camr ask` both print through this (D-96).
public final class CheckedStream: @unchecked Sendable {
    private var pending = ""
    private let emit: (String) -> Void
    public var shown: [ShownLines] = []
    public var ledger: Set<String> = []

    public init(emit: @escaping (String) -> Void) { self.emit = emit }

    public func add(_ words: String) {
        pending += words
        while let newline = pending.firstIndex(of: "\n") {
            let line = String(pending[...newline])
            pending.removeSubrange(...newline)
            emit(Citations.check(line, shown: shown, ledger: ledger).text)
        }
    }

    public func finish() {
        guard !pending.isEmpty else { return }
        emit(Citations.check(pending, shown: shown, ledger: ledger).text)
        pending = ""
    }
}

/// Checks an answer's citations: files and lines against the excerpts a model read, Ledger ids against the commits it
/// was handed. One check for the app's Ask, `camr chat`, `camr ask` and `vault_ask` (D-91, D-96).
public enum Citations {
    /// A Ledger commit id: `20261114-065345-a355`, or a team's, which ends with who kept it and their Mac's tag:
    /// `20261114-065345-a355-wanjiru-kamau-7939` (D-109). A team id was once matched only up to its fourth group, so a
    /// whole one was never found among those handed over and was marked in the middle.
    static let ledgerID = try! NSRegularExpression(pattern: #"(?<![0-9A-Za-z])\d{8}-\d{6}-[0-9a-f]{4}(?:-[a-z0-9]+)*(?![0-9A-Za-z])"#)

    /// What a model says around a citation in brackets that carries no fact of its own: "(from notes/plan.md:12)".
    private static let filler: Set<String> = [
        "from", "see", "source", "sources", "in", "the", "a", "note", "notes", "file", "files", "line", "lines", "at", "on",
        "ledger", "decision", "commit", "and", "per", "cf", "according", "to", "as",
    ]

    /// Said after a citation that is part of a sentence and can't be taken out without breaking it.
    public static let notReadMark = " (not among what it read)"

    /// Every Ledger id in a text, in order, once each.
    public static func ledgerIDs(in text: String) -> [String] {
        let ns = text as NSString
        var out: [String] = []
        for match in ledgerID.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let id = ns.substring(with: match.range)
            if !out.contains(id) { out.append(id) }
        }
        return out
    }

    public static func check(_ answer: String, shown: [ShownLines], ledger given: Set<String> = []) -> CheckedAnswer {
        let text = answer as NSString
        let whole = NSRange(location: 0, length: text.length)
        var unverified: [String] = []
        var cited: [String] = []
        var wrong: [NSRange] = []
        for match in Engine.cited.matches(in: answer, range: whole) {
            let path = text.substring(with: match.range(at: 1))
            guard let line = Int(text.substring(with: match.range(at: 2))) else { continue }
            if shown.contains(where: { $0.covers(path, line: line) }) { continue }
            let place = "\(path):\(line)"
            if !unverified.contains(place) { unverified.append(place) }
            wrong.append(widened(match.range, in: text, lineRange: true))
        }
        for match in ledgerID.matches(in: answer, range: whole) {
            let id = text.substring(with: match.range)
            if given.contains(id) {
                if !cited.contains(id) { cited.append(id) }
                continue
            }
            let place = "Ledger \(id)"
            if !unverified.contains(place) { unverified.append(place) }
            wrong.append(widened(match.range, in: text, lineRange: false))
        }
        // Every edit is worked out on the answer as the model wrote it, then the answer is rebuilt in one pass. Editing
        // in place let a later edit use a range an earlier one had cut away, and NSString threw on what a model wrote.
        var kept: [NSRange] = []
        for range in wrong.sorted(by: { $0.location < $1.location }) where !kept.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
            kept.append(range)
        }
        // The other places being taken out read as nothing when a bracket is checked for words that say something, so
        // "(notes/a.md:1, notes/b.md:2)" goes whole when neither was given.
        let masked = NSMutableString(string: answer)
        for range in kept { masked.replaceCharacters(in: range, with: String(repeating: " ", count: range.length)) }
        let edits = kept.map { edit(for: $0, in: masked) }
        return CheckedAnswer(text: apply(edits, to: text), unverified: unverified, ledgerCited: cited)
    }

    /// A stretch of the answer to replace: a cut has empty `with`, a mark an empty `range`.
    struct Edit: Equatable {
        let range: NSRange
        let with: String
    }

    /// The answer with the edits made, front to back in one pass over the original. Overlapping cuts join, a mark inside
    /// a cut is dropped, and every range is held inside the text, so no answer can make this throw.
    static func apply(_ edits: [Edit], to text: NSString) -> String {
        let length = text.length
        var out = ""
        var cursor = 0
        for edit in edits.sorted(by: { ($0.range.location, $0.range.length) < ($1.range.location, $1.range.length) }) {
            let start = min(max(edit.range.location, 0), length)
            let end = min(max(start + max(edit.range.length, 0), start), length)
            if start < cursor {
                // Inside what an earlier cut took: a cut carries on to its own end; a mark goes with the text it followed.
                if edit.with.isEmpty { cursor = max(cursor, end) }
                continue
            }
            out += text.substring(with: NSRange(location: cursor, length: start - cursor))
            out += edit.with
            cursor = end
        }
        if cursor < length { out += text.substring(from: cursor) }
        return out
    }

    /// The citation with the quote marks around it, a line range after it ("13-18"), and a "Ledger " before an id.
    private static func widened(_ range: NSRange, in text: NSString, lineRange: Bool) -> NSRange {
        let marks = Set("`'\"*")
        var start = range.location, end = range.location + range.length
        func char(_ at: Int) -> Character? { at >= 0 && at < text.length ? Character(UnicodeScalar(text.character(at: at)) ?? " ") : nil }
        if lineRange, let dash = char(end), dash == "-" || dash == "\u{2013}", let digit = char(end + 1), digit.isNumber {
            end += 1
            while let next = char(end), next.isNumber { end += 1 }
        }
        if !lineRange {
            for word in ["ledger decision ", "ledger commit ", "ledger ", "decision ", "commit "] {
                let length = word.count
                if start - length >= 0, text.substring(with: NSRange(location: start - length, length: length)).lowercased() == word {
                    start -= length
                    break
                }
            }
        }
        while let previous = char(start - 1), marks.contains(previous) { start -= 1 }
        while let next = char(end), marks.contains(next) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    /// How a citation comes out of the answer. In brackets with nothing else that says something, the brackets go too;
    /// one of a list in brackets goes with its comma; one inside a sentence is marked, since cutting it would change what
    /// the sentence says. `text` is the answer with every place being taken out blanked to spaces; nothing is changed here.
    static func edit(for range: NSRange, in text: NSString) -> Edit {
        let length = text.length
        guard range.location >= 0, range.length >= 0, range.location + range.length <= length else {
            return Edit(range: NSRange(location: min(max(range.location, 0), length), length: 0), with: "")
        }
        let line = text.lineRange(for: range)
        var lineEnd = line.location + line.length
        while lineEnd > line.location, let last = UnicodeScalar(text.character(at: lineEnd - 1)), CharacterSet.newlines.contains(last) { lineEnd -= 1 }
        func char(_ at: Int) -> Character { at >= 0 && at < length ? Character(UnicodeScalar(text.character(at: at)) ?? " ") : " " }
        let end = range.location + range.length

        var open = range.location - 1
        while open >= line.location, !"([)]".contains(char(open)) { open -= 1 }
        var close = end
        while close < lineEnd, !"([)]".contains(char(close)) { close += 1 }
        let bracketed = open >= line.location && "([".contains(char(open)) && close < lineEnd && ")]".contains(char(close))

        if bracketed {
            let inside = text.substring(with: NSRange(location: open + 1, length: close - open - 1))
            let words = inside.lowercased().split { !$0.isLetter }.map(String.init)
            if words.allSatisfy(filler.contains) {
                var from = open
                while from > line.location, char(from - 1) == " " { from -= 1 }
                return Edit(range: NSRange(location: from, length: close + 1 - from), with: "")
            }
            // One of a list: "(Home/Lease.md:7, notes/plan.md:12)".
            var next = end
            while next < close, char(next) == " " { next += 1 }
            if next < close, ",;".contains(char(next)) {
                next += 1
                while next < close, char(next) == " " { next += 1 }
                return Edit(range: NSRange(location: range.location, length: next - range.location), with: "")
            }
            var previous = range.location - 1
            while previous > open, char(previous) == " " { previous -= 1 }
            if previous > open, ",;".contains(char(previous)) {
                return Edit(range: NSRange(location: previous, length: end - previous), with: "")
            }
        }
        return Edit(range: NSRange(location: end, length: 0), with: notReadMark)
    }
}
