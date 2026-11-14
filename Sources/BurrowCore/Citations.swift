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

/// Checks an answer's citations: files and lines against the excerpts a model read, Ledger ids against the commits it
/// was handed. One check for the app's Ask and `burrow chat` (D-91).
public enum Citations {
    /// A Ledger commit id: `20261114-065345-a355`.
    static let ledgerID = try! NSRegularExpression(pattern: #"(?<![0-9A-Za-z])\d{8}-\d{6}-[0-9a-f]{4}(?![0-9A-Za-z])"#)

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
        let out = NSMutableString(string: answer)
        var done: [NSRange] = []
        for range in wrong.sorted(by: { $0.location > $1.location }) where !done.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
            done.append(range)
            takeOut(range, from: out)
        }
        return CheckedAnswer(text: out as String, unverified: unverified, ledgerCited: cited)
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

    /// Takes a citation out of the answer. In brackets with nothing else that says something, the brackets go too; one
    /// of a list in brackets goes with its comma; one inside a sentence is marked, since cutting it would change what the
    /// sentence says.
    private static func takeOut(_ range: NSRange, from out: NSMutableString) {
        let line = out.lineRange(for: range)
        var lineEnd = line.location + line.length
        while lineEnd > line.location, let last = UnicodeScalar(out.character(at: lineEnd - 1)), CharacterSet.newlines.contains(last) { lineEnd -= 1 }
        func char(_ at: Int) -> Character { Character(UnicodeScalar(out.character(at: at)) ?? " ") }

        var open = range.location - 1
        while open >= line.location, !"([)]".contains(char(open)) { open -= 1 }
        var close = range.location + range.length
        while close < lineEnd, !"([)]".contains(char(close)) { close += 1 }
        let bracketed = open >= line.location && "([".contains(char(open)) && close < lineEnd && ")]".contains(char(close))

        if bracketed {
            let before = out.substring(with: NSRange(location: open + 1, length: range.location - open - 1))
            let after = out.substring(with: NSRange(location: range.location + range.length, length: close - range.location - range.length))
            let words = (before + " " + after).lowercased().split { !$0.isLetter }.map(String.init)
            if words.allSatisfy(filler.contains) {
                var from = open
                while from > line.location, char(from - 1) == " " { from -= 1 }
                out.deleteCharacters(in: NSRange(location: from, length: close + 1 - from))
                return
            }
            // One of a list: "(Home/Lease.md:7, notes/plan.md:12)".
            var next = range.location + range.length
            while next < close, char(next) == " " { next += 1 }
            if next < close, ",;".contains(char(next)) {
                next += 1
                while next < close, char(next) == " " { next += 1 }
                out.deleteCharacters(in: NSRange(location: range.location, length: next - range.location))
                return
            }
            var previous = range.location - 1
            while previous > open, char(previous) == " " { previous -= 1 }
            if previous > open, ",;".contains(char(previous)) {
                out.deleteCharacters(in: NSRange(location: previous, length: range.location + range.length - previous))
                return
            }
        }
        out.insert(notReadMark, at: range.location + range.length)
    }
}
