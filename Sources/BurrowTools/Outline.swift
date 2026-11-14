import CryptoKit
import Foundation

/// One function, class or block in a code file, with a hash of its body, so a change can be placed: did it touch the
/// parts a decision rests on, or only the rest of the file (D-107)?
public struct OutlineSymbol: Sendable, Equatable {
    /// The plain name: `ticket_for_line`.
    public let name: String
    /// With what holds it: `Store.get` for a method.
    public let qualified: String
    /// 1-based, inclusive, decorators included.
    public let startLine: Int
    public let endLine: Int
    /// The body with blank lines, comment-only lines and trailing spaces taken out, so a comment or spacing change is not
    /// a change to what the code does.
    public let hash: String
    /// Names the body calls: an identifier followed by `(`.
    public let calls: Set<String>
    /// Every identifier the body uses, for module-level names (a constant, an import) it may rest on.
    public let uses: Set<String>
}

/// A file cut into its symbols, and what lies outside them (imports, constants, top-level code).
public struct FileOutline: Sendable, Equatable {
    public let symbols: [OutlineSymbol]
    /// Module-level names and what each is bound to, as written: `TICKET_ISSUED` → `..models.TICKET_ISSUED`. A name whose
    /// binding differs between two versions changed. Python only; empty for the brace languages.
    public let bindings: [String: String]
    /// The top-level lines that bind no name, normalised and joined: any difference is a change to module code.
    public let moduleCode: String
}

/// A small, robust outline per language: Python by indentation, and Swift, JavaScript, TypeScript, Go, Rust, Java,
/// Kotlin, C-family and C# by braces. No model, no compiler: what a person would see scanning the file. Nil when the
/// language is not one of these or the file does not parse (an unclosed brace, a string that never ends), so the caller
/// can say it cannot tell rather than guess (D-107).
public enum Outline {
    static let python: Set<String> = ["py", "pyi"]
    static let braces: Set<String> = ["swift", "js", "jsx", "mjs", "cjs", "ts", "tsx", "go", "rs", "java", "kt", "kts", "c", "h", "cc", "cpp", "hpp", "m", "mm", "cs", "scala", "dart", "php"]

    public static func understands(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return python.contains(ext) || braces.contains(ext)
    }

    public static func of(_ text: String, path: String) -> FileOutline? {
        guard text.utf8.count <= 1_000_000 else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        if python.contains(ext) { return Python.outline(text) }
        if braces.contains(ext) { return Braces.outline(text) }
        return nil
    }

    static func hash(_ lines: [String]) -> String {
        let text = lines.joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static let callPattern = try! NSRegularExpression(pattern: #"([A-Za-z_][A-Za-z0-9_]*)\s*\("#)
    static let identifierPattern = try! NSRegularExpression(pattern: #"[A-Za-z_][A-Za-z0-9_]*"#)

    static func calls(in text: String) -> Set<String> {
        let range = NSRange(text.startIndex..., in: text)
        return Set(callPattern.matches(in: text, range: range).compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } })
    }

    public static func identifiers(in text: String) -> Set<String> {
        let range = NSRange(text.startIndex..., in: text)
        return Set(identifierPattern.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } })
    }

    // MARK: Python

    enum Python {
        /// One logical line: where it starts, its indent, and its text with continuation lines joined.
        struct Logical {
            let first: Int  // 0-based index of its first physical line
            let last: Int
            let indent: Int
            let text: String
            /// A line that is only a comment, or blank.
            let empty: Bool
        }

        static let header = try! NSRegularExpression(pattern: #"^(?:async\s+)?(def|class)\s+([A-Za-z_][A-Za-z0-9_]*)"#)

        static func indent(_ line: Substring) -> Int {
            var count = 0
            for character in line {
                if character == " " { count += 1 } else if character == "\t" { count += 8 - count % 8 } else { break }
            }
            return count
        }

        /// Logical lines, following brackets and strings (triple-quoted ones too) across physical lines. Nil when a
        /// string or bracket never closes.
        static func logical(_ lines: [Substring]) -> [Logical]? {
            var out: [Logical] = []
            var index = 0
            while index < lines.count {
                let start = index
                var depth = 0
                var open: String?  // the quote a string spanning lines was opened with
                var text = ""
                repeat {
                    let line = lines[index]
                    text += (text.isEmpty ? "" : "\n") + line
                    var chars = Array(line)
                    var position = 0
                    var continued = false
                    while position < chars.count {
                        let character = chars[position]
                        if let quote = open {
                            if character == "\\" { position += 2; continue }
                            let q = Array(quote)
                            if position + q.count <= chars.count, Array(chars[position..<position + q.count]) == q { open = nil; position += q.count; continue }
                            position += 1
                            continue
                        }
                        switch character {
                        case "#": position = chars.count; continue
                        case "\"", "'":
                            let triple = position + 2 < chars.count && chars[position + 1] == character && chars[position + 2] == character
                            open = triple ? String(repeating: String(character), count: 3) : String(character)
                            position += triple ? 3 : 1
                            continue
                        case "(", "[", "{": depth += 1
                        case ")", "]", "}": depth = max(0, depth - 1)
                        case "\\" where position == chars.count - 1: continued = true
                        default: break
                        }
                        position += 1
                    }
                    // A one-quote string never runs past its line.
                    if let quote = open, quote.count == 1 { open = nil }
                    chars = []
                    index += 1
                    if open == nil, depth == 0, !continued { break }
                } while index < lines.count
                if open != nil || depth > 0 { if index >= lines.count { return nil } }
                let firstLine = lines[start]
                let stripped = firstLine.trimmingCharacters(in: .whitespaces)
                out.append(Logical(first: start, last: index - 1, indent: indent(firstLine), text: text,
                                   empty: stripped.isEmpty || stripped.hasPrefix("#")))
            }
            return out
        }

        /// The body as hashed: the original text of each statement, string contents and all, with only the comment-only
        /// and blank lines between statements left out, and spaces at the end of a statement. Lines inside a statement
        /// (a string, a bracket spanning lines) are kept exactly, so a change inside a string is a change (D-107).
        static func normalised(_ logical: ArraySlice<Logical>, _ lines: [Substring]) -> [String] {
            logical.compactMap { line in
                if line.empty { return nil }
                var kept = lines[line.first...line.last].joined(separator: "\n")
                while kept.last == " " || kept.last == "\t" { kept.removeLast() }
                return kept
            }
        }

        static func outline(_ text: String) -> FileOutline? {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.hasSuffix("\r") ? $0.dropLast() : $0 }
            guard let logical = logical(lines) else { return nil }
            var symbols: [OutlineSymbol] = []
            var covered = Set<Int>()  // logical line indexes inside a top-level symbol
            func scan(from: Int, to: Int, parent: String) {
                var position = from
                while position < to {
                    let line = logical[position]
                    let stripped = line.text.trimmingCharacters(in: .whitespaces)
                    let range = NSRange(stripped.startIndex..., in: stripped)
                    guard !line.empty, let match = header.firstMatch(in: stripped, range: range),
                          let nameRange = Range(match.range(at: 2), in: stripped) else { position += 1; continue }
                    let name = String(stripped[nameRange])
                    // The block runs to the next non-empty logical line indented no deeper than the header.
                    var end = position + 1
                    while end < to, logical[end].empty || logical[end].indent > line.indent { end += 1 }
                    // Trailing comments and blank lines belong to what follows.
                    var lastBody = end - 1
                    while lastBody > position, logical[lastBody].empty { lastBody -= 1 }
                    // Decorators directly above, at the same indent.
                    var first = position
                    while first > from, !logical[first - 1].empty, logical[first - 1].indent == line.indent,
                          logical[first - 1].text.trimmingCharacters(in: .whitespaces).hasPrefix("@") { first -= 1 }
                    let physical = lines[logical[first].first...logical[lastBody].last]
                    let body = physical.joined(separator: "\n")
                    let qualified = parent.isEmpty ? name : parent + "." + name
                    symbols.append(OutlineSymbol(name: name, qualified: qualified, startLine: logical[first].first + 1, endLine: logical[lastBody].last + 1,
                                                 hash: Outline.hash(normalised(logical[first...lastBody], lines)), calls: Outline.calls(in: body).subtracting([name]),
                                                 uses: Outline.identifiers(in: body)))
                    if parent.isEmpty { for index in first...lastBody { covered.insert(index) } }
                    scan(from: position + 1, to: lastBody + 1, parent: qualified)
                    position = end
                }
            }
            scan(from: 0, to: logical.count, parent: "")

            // Module level: what each top-level statement binds, and the code that binds nothing.
            var bindings: [String: String] = [:]
            var code: [String] = []
            // Indented ones too: an import under `try:` or `if TYPE_CHECKING:` binds a name all the same.
            for (index, line) in logical.enumerated() where !covered.contains(index) && !line.empty {
                // Parsed from the statement with its lines trimmed and joined, but compared as written: an assignment's value
                // and code that binds nothing keep their string contents exactly (D-107). A module docstring counts as code
                // too: it can be read, so a change to it is not assumed harmless.
                let statement = line.text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
                var written = line.text
                while written.last == " " || written.last == "\t" { written.removeLast() }
                let bound = binds(statement)
                if bound.isEmpty { code.append(written) }
                let assigned = !statement.hasPrefix("import ") && !statement.hasPrefix("from ")
                for (name, value) in bound { bindings[name] = (bindings[name].map { $0 + " | " } ?? "") + (assigned ? written : value) }
            }
            return FileOutline(symbols: symbols, bindings: bindings, moduleCode: code.joined(separator: "\n"))
        }

        static let fromImport = try! NSRegularExpression(pattern: #"^from\s+([.\w]+)\s+import\s+(.+)$"#, options: [.dotMatchesLineSeparators])
        static let plainImport = try! NSRegularExpression(pattern: #"^import\s+(.+)$"#)
        static let assignment = try! NSRegularExpression(pattern: #"^([A-Za-z_][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)\s*(?::[^=]+)?=(?!=)(.*)$"#, options: [.dotMatchesLineSeparators])

        /// The names one top-level statement binds, each with what it is bound to.
        static func binds(_ statement: String) -> [(String, String)] {
            let range = NSRange(statement.startIndex..., in: statement)
            func group(_ match: NSTextCheckingResult, _ number: Int) -> String {
                Range(match.range(at: number), in: statement).map { String(statement[$0]) } ?? ""
            }
            if let match = fromImport.firstMatch(in: statement, range: range) {
                let module = group(match, 1)
                let names = group(match, 2).trimmingCharacters(in: CharacterSet(charactersIn: "() \\"))
                return names.split(separator: ",").compactMap { part in
                    let words = part.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init).filter { $0 != "(" && $0 != ")" && $0 != "\\" }
                    guard let original = words.first, !original.isEmpty else { return nil }
                    let local = words.count >= 3 && words[1] == "as" ? words[2] : original
                    return (local, module + "." + original)
                }
            }
            if let match = plainImport.firstMatch(in: statement, range: range) {
                return group(match, 1).split(separator: ",").compactMap { part in
                    let words = part.split(separator: " ").map(String.init)
                    guard let module = words.first else { return nil }
                    let local = words.count >= 3 && words[1] == "as" ? words[2] : String(module.split(separator: ".").first ?? "")
                    return (local, "import " + module)
                }
            }
            if let match = assignment.firstMatch(in: statement, range: range) {
                let value = group(match, 2).trimmingCharacters(in: .whitespaces)
                return group(match, 1).split(separator: ",").map { ($0.trimmingCharacters(in: .whitespaces), value) }
            }
            return []
        }
    }

    // MARK: Braces

    enum Braces {
        static let modifiers = #"(?:(?:export|default|public|private|fileprivate|internal|open|final|static|abstract|async|pub(?:\([a-z]+\))?|override|indirect|mutating|nonmutating|convenience|required|@\w+(?:\([^)]*\))?|protected|virtual|inline|unsafe|extern|const)\s+)*"#
        static let declaration = try! NSRegularExpression(pattern: #"^\s*"# + modifiers + #"(?:func|function\*?|fn|def|class|struct|enum|protocol|interface|trait|impl|extension|actor|object|init|deinit|subscript)\b\s*([A-Za-z_][A-Za-z0-9_.<>]*)?"#)
        static let arrow = try! NSRegularExpression(pattern: #"^\s*"# + modifiers + #"(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=]+)?=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*(?::[^=]+)?=>|[A-Za-z_][A-Za-z0-9_]*\s*=>)"#)
        static let goMethod = try! NSRegularExpression(pattern: #"^\s*func\s+\([^)]*\)\s+([A-Za-z_][A-Za-z0-9_]*)"#)
        /// A method in a class body (JS/TS/Java/C#): a name, its parameters, and the brace.
        static let method = try! NSRegularExpression(pattern: #"^\s*"# + modifiers + #"(?:get\s+|set\s+|[A-Za-z_<>\[\],.?]+\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^>]*>)?\s*\([^;]*\)\s*(?::[^{]+)?(?:throws\s+[^{]+)?\{\s*$"#)
        static let notMethods: Set<String> = ["if", "for", "while", "switch", "catch", "return", "guard", "else", "do", "with", "when", "match", "repeat", "foreach", "using", "lock", "synchronized", "sizeof", "typeof", "function"]

        /// Each line's brace depth at its start and end, counted with strings and comments skipped; `code` is the line so
        /// stripped (for finding declarations and calls), `kept` the line with only its comments taken out, strings whole
        /// (what is hashed, D-107). Nil when they never close.
        static func depths(_ lines: [Substring]) -> [(start: Int, end: Int, code: String, kept: String)]? {
            var out: [(Int, Int, String, String)] = []
            var depth = 0
            var block = false  // inside /* */
            var template = false  // inside a JS template literal or a Swift """ string
            for line in lines {
                let start = depth
                let chars = Array(line)
                var code = ""
                var kept = ""
                let startsInString = template
                var position = 0
                while position < chars.count {
                    let character = chars[position]
                    let next: Character? = position + 1 < chars.count ? chars[position + 1] : nil
                    if block {
                        if character == "*", next == "/" { block = false; position += 2 } else { position += 1 }
                        continue
                    }
                    if template {
                        if character == "\\" { kept.append(character); if let next { kept.append(next) }; position += 2; continue }
                        if character == "`" { template = false }
                        if character == "\"", next == "\"", position + 2 < chars.count, chars[position + 2] == "\"" { template = false; kept += "\"\"\""; position += 3; continue }
                        kept.append(character)
                        position += 1
                        continue
                    }
                    if character == "/", next == "/" { break }
                    if character == "/", next == "*" { block = true; position += 2; continue }
                    if character == "`" { template = true; kept.append(character); position += 1; continue }
                    if character == "\"", next == "\"", position + 2 < chars.count, chars[position + 2] == "\"" { template = true; kept += "\"\"\""; position += 3; continue }
                    if character == "\"" || character == "'" {
                        // A Rust lifetime ('a) or a char: a quote with no partner on the line is left as it is.
                        var end = position + 1
                        while end < chars.count, chars[end] != character { end += chars[end] == "\\" ? 2 : 1 }
                        if end < chars.count { code += "\"\""; kept += String(chars[position...end]); position = end + 1; continue }
                        kept.append(character)
                        position += 1
                        continue
                    }
                    if character == "{" { depth += 1 } else if character == "}" { depth -= 1; if depth < 0 { return nil } }
                    code.append(character)
                    kept.append(character)
                    position += 1
                }
                // Spaces are trimmed only where they are not inside a string that runs across lines.
                if !startsInString { kept = String(kept.drop(while: { $0 == " " || $0 == "\t" })) }
                if !template { while kept.last == " " || kept.last == "\t" { kept.removeLast() } }
                // A blank line inside such a string is content: kept as a mark, so adding one is a change.
                if kept.isEmpty, startsInString || template { kept = "\u{1}" }
                out.append((start, depth, code, kept))
            }
            guard depth == 0, !block, !template else { return nil }
            return out
        }

        static func outline(_ text: String) -> FileOutline? {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.hasSuffix("\r") ? $0.dropLast() : $0 }
            guard let depth = depths(lines) else { return nil }
            var symbols: [OutlineSymbol] = []
            var covered = Set<Int>()
            var holders: [(name: String, close: Int)] = []  // enclosing symbols, by the depth their body closes at
            for (index, line) in lines.enumerated() {
                while let last = holders.last, depth[index].start <= last.close { holders.removeLast() }
                let code = depth[index].code
                let range = NSRange(code.startIndex..., in: code)
                var name: String?
                for pattern in [goMethod, arrow, declaration] {
                    if let match = pattern.firstMatch(in: code, range: range) {
                        let found = Range(match.range(at: 1), in: code).map { String(code[$0]) } ?? ""
                        name = found.isEmpty ? (code.contains("init") ? "init" : nil) : found
                        if name != nil { break }
                    }
                }
                if name == nil, !holders.isEmpty, let match = method.firstMatch(in: code, range: range),
                   let found = Range(match.range(at: 1), in: code).map({ String(code[$0]) }), !notMethods.contains(found) {
                    name = found
                }
                guard let plain = name?.split(separator: "<").first.map(String.init), !plain.isEmpty else { continue }
                // The body opens on this line or within the next three; a declaration with no body (a prototype, a
                // protocol requirement) is not a symbol.
                let base = depth[index].start
                var open: Int?
                for ahead in index..<min(lines.count, index + 4) {
                    if depth[ahead].code.contains("{") { open = ahead; break }
                    if depth[ahead].code.contains(";") { break }
                }
                guard let opened = open else { continue }
                var close = opened
                while close < lines.count, depth[close].end > base { close += 1 }
                guard close < lines.count else { return nil }
                // Attributes and annotations directly above (@MainActor, @Test, #[derive]).
                var first = index
                while first > 0, lines[first - 1].trimmingCharacters(in: .whitespaces).hasPrefix("@") || lines[first - 1].trimmingCharacters(in: .whitespaces).hasPrefix("#[") { first -= 1 }
                let shortName = plain.split(separator: ".").last.map(String.init) ?? plain
                let qualified = (holders.map(\.name) + [shortName]).joined(separator: ".")
                let normal = depth[first...close].map(\.kept).filter { !$0.isEmpty }
                let joined = depth[first...close].map(\.code).joined(separator: "\n")
                symbols.append(OutlineSymbol(name: shortName, qualified: qualified, startLine: first + 1, endLine: close + 1,
                                             hash: Outline.hash(normal), calls: Outline.calls(in: joined).subtracting(["if", "for", "while", "switch", "catch", "return", "guard"]),
                                             uses: Outline.identifiers(in: joined)))
                if holders.isEmpty { for line in first...close { covered.insert(line) } }
                holders.append((shortName, base))
            }
            let code = lines.indices.filter { !covered.contains($0) }.map { depth[$0].kept }.filter { !$0.isEmpty }
            return FileOutline(symbols: symbols, bindings: [:], moduleCode: code.joined(separator: "\n"))
        }
    }
}
