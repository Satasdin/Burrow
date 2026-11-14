import Foundation

/// Secrets taken out of what Burrow keeps from a session (D-105). A fold keeps what the person typed, the commands run and
/// the error lines exactly as printed, and any of those can carry an API key, a token, a password in a URL or a private
/// key. Each is replaced with a plain marker and everything around it stays word for word, so an error line keeps its
/// exact value wherever that value is not a secret. Applied when a fold is made, to every field it keeps, and again
/// whenever a fold is shown, handed back or its original messages are read.
public enum Secrets {
    public static let marker = "[secret removed]"

    /// Not at a marker already there, so taking secrets out twice changes nothing.
    private static let notMarker = #"(?!\[secret removed\])"#
    /// A value that is only digits is a count, a port or a size (max_tokens=4096), not a secret.
    private static let notNumber = #"(?![0-9]+(?![A-Za-z0-9_-]))"#

    private static let rules: [(NSRegularExpression, String)] = [
        // A private key block, whole; one cut short by a clip runs to the end of the text.
        (#"-----BEGIN [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?-----[\s\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY(?: BLOCK)?-----|\z)"#, marker),
        // A password in a URL: scheme://user:password@host keeps the user and the host.
        (#"\b([A-Za-z][A-Za-z0-9+.-]*://[^\s:/@'"]+):"# + notMarker + #"[^\s/@'"]+@"#, "$1:" + marker + "@"),
        // An Authorization header, its scheme kept: "Authorization: Bearer [secret removed]". Not a backslash, so a quote
        // escaped in JSON (a tool call read back from the transcript) keeps its escape.
        (#"(?i)\b((?:proxy-)?authorization["']?\s*[:=]\s*["']?)((?:bearer|basic|token|digest|negotiate)\s+)?"# + notMarker + #"[^\s"',\\]{8,}"#,
         "$1$2" + marker),
        // A bearer token on its own, as in a log line.
        (#"(?i)\b(bearer\s+)"# + notMarker + #"[A-Za-z0-9._~+/-]{16,}=*"#, "$1" + marker),
        // Token shapes that are secrets wherever they appear.
        (#"\bsk-(?:ant-|proj-|live-|test-)?[A-Za-z0-9_-]{16,}"#, marker),                       // OpenAI, Anthropic
        (#"\b(?:sk|rk|pk)_(?:live|test)_[A-Za-z0-9]{16,}"#, marker),                              // Stripe
        (#"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}|\bgithub_pat_[A-Za-z0-9_]{20,}"#, marker),     // GitHub
        (#"\bglpat-[A-Za-z0-9_-]{20,}"#, marker),                                                   // GitLab
        (#"\bxox[abposr]-[A-Za-z0-9-]{10,}"#, marker),                                              // Slack
        (#"https://hooks\.slack\.com/services/[A-Za-z0-9/]+"#, marker),
        (#"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b"#, marker),                                                // AWS access key id
        (#"\bAIza[0-9A-Za-z_-]{35}"#, marker),                                                      // Google
        (#"\bhf_[A-Za-z0-9]{30,}"#, marker),                                                        // Hugging Face
        (#"\bnpm_[A-Za-z0-9]{36}"#, marker),                                                        // npm
        (#"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#, marker),              // a JWT
        // A command-line flag that takes a secret: --password hunter2, --api-key=..., --token "...".
        (#"(?i)(--?(?:password|passwd|token|api[-_]?key|secret|client[-_]?secret|access[-_]?key|auth[-_]?token)(?:\s+|=))"# + notMarker
            + #"("[^"]*"|'[^']*'|[^\s"'-][^\s"']*)"#, "$1" + marker),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    /// The text with every secret Burrow can recognise replaced by the marker.
    public static func redacted(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var out = text
        for (rule, template) in rules {
            out = rule.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: template)
        }
        return namedValuesRemoved(out)
    }

    // MARK: A secret's name, then its value (D-106)

    /// NAME=value and "name": value where the name says the value is a secret (OPENAI_API_KEY=..., export
    /// DB_PASSWORD="...", ?access_token=..., "api_key": "...", X-Api-Key: ...). Found by reading the text once: each place
    /// a secret's word appears, the whole name around it, then `=` or `:`, then the value. No pattern tries a name at every
    /// position, so a long line costs no more than reading it, and nothing is skipped for being long. A quoted value that
    /// never closes is removed to the end of its line (fails closed).
    static func namedValuesRemoved(_ text: String) -> String {
        let chars = Array(text)
        // Lowercased one character at a time, so positions line up even where a letter's lowercase is longer.
        let lower = chars.map { c -> Character in let l = String(c).lowercased(); return l.count == 1 ? Character(l) : c }
        var cuts: [Range<Int>] = []
        var seen = Set<Int>()
        var i = 0
        while i < lower.count {
            guard let word = nameWords.first(where: { matches($0, in: lower, at: i) }) else { i += 1; continue }
            // The whole name around the word: letters, digits, _ . -
            var from = i, to = i + word.count
            while from > 0, isNameChar(chars[from - 1]) { from -= 1 }
            while to < chars.count, isNameChar(chars[to]) { to += 1 }
            i = to
            guard seen.insert(from).inserted, isSecretName(String(chars[from..<to])) else { continue }
            if let value = value(after: to, nameFrom: from, in: chars) { cuts.append(value) }
        }
        guard !cuts.isEmpty else { return text }
        var out = chars
        for cut in cuts.sorted(by: { $0.lowerBound > $1.lowerBound }) { out.replaceSubrange(cut, with: Array(marker)) }
        return String(out)
    }

    /// The words a secret's name has in it, lowercased.
    private static let nameWords = ["passphrase", "password", "passwd", "credential", "secret", "token", "apikey", "key"]

    private static func matches(_ word: String, in lower: [Character], at i: Int) -> Bool {
        let w = Array(word)
        guard i + w.count <= lower.count else { return false }
        for k in 0..<w.count where lower[i + k] != w[k] { return false }
        return true
    }

    private static func isNameChar(_ c: Character) -> Bool {
        c == "_" || c == "." || c == "-" || (c.isASCII && (c.isLetter || c.isNumber))
    }

    /// Whether a whole name says its value is a secret. "tokens" and "tokenizer" are settings (max_tokens); a name that
    /// ends like an exception (InvalidTokenError) is part of an error line and stays as printed.
    static func isSecretName(_ name: String) -> Bool {
        if name.hasSuffix("Error") || name.hasSuffix("Exception") || name.hasSuffix("Warning") { return false }
        if name.hasSuffix("_KEY") { return true }
        let lower = name.lowercased()
        for word in ["secret", "passphrase", "credential", "apikey", "password", "passwd"] where lower.contains(word) { return true }
        var rest = lower[...]
        while let hit = rest.range(of: "token") {
            let after = rest[hit.upperBound...]
            if !after.hasPrefix("s"), !after.hasPrefix("izer") { return true }
            rest = after
        }
        for prefix in ["api", "access", "private", "signing", "encryption", "master", "license", "account", "client", "secret"] {
            for joiner in ["", "_", "-"] where lower.contains(prefix + joiner + "key") { return true }
        }
        return false
    }

    /// The range of the value after a secret's name that ends at `to`, or nil when what follows is not `=` or `:` and a
    /// value. Mirrors the old patterns: NAME = value, or a name (quoted alike on both sides, or not) then `:` and a value.
    private static func value(after to: Int, nameFrom from: Int, in chars: [Character]) -> Range<Int>? {
        var j = to
        // "name": the same quote after the name as before it.
        var quoted: Character? = nil
        if from > 0, chars[from - 1] == "\"" || chars[from - 1] == "'", j < chars.count, chars[j] == chars[from - 1] {
            quoted = chars[j]; j += 1
        }
        while j < chars.count, chars[j].isWhitespace { j += 1 }
        guard j < chars.count, chars[j] == "=" || chars[j] == ":" else { return nil }
        let colon = chars[j] == ":"
        if quoted != nil, !colon { return nil }
        j += 1
        while j < chars.count, chars[j].isWhitespace { j += 1 }
        guard j < chars.count else { return nil }
        // Already removed, a shell variable, or only digits (a count, a port, a size): leave it.
        if String(chars[j..<min(chars.count, j + marker.count)]) == marker { return nil }
        if !colon, chars[j] == "$" { return nil }
        var digits = j
        while digits < chars.count, chars[digits].isASCII, chars[digits].isNumber { digits += 1 }
        if digits > j, digits == chars.count || !(isNameChar(chars[digits]) && chars[digits] != "." ) { return nil }
        if chars[j] == "\"" || chars[j] == "'" {
            let q = chars[j]
            var k = j + 1
            while k < chars.count, chars[k] != q { k += 1 }
            if k < chars.count {
                if colon, k == j + 1 { return nil }   // "name": "" holds nothing
                return j..<(k + 1)
            }
            // Never closed: everything to the end of the line goes.
            var end = j
            while end < chars.count, chars[end] != "\n" { end += 1 }
            return j..<end
        }
        let stops: Set<Character> = colon ? [" ", "\t", "\n", "\r", "\"", "'", ",", "}"] : [" ", "\t", "\n", "\r", "\"", "'", "&", ";", ",", ")"]
        var k = j
        while k < chars.count, !stops.contains(chars[k]) { k += 1 }
        if k == j { return nil }
        // Unquoted after a colon, the value must be 8 or more characters: "Invalid token: expired" stays as printed.
        if colon, k - j < 8 { return nil }
        return j..<k
    }

    /// The text cut before secrets are taken out, generously: taking secrets out reads a text once, so this only bounds
    /// the work. The cut sits far past any length a caller keeps (`limit` × 20, at least 20,000 characters), so a secret
    /// it splits can never be pulled back into what is kept (D-106).
    public static func cutForRedaction(_ text: String, _ limit: Int) -> String {
        let room = max(limit * 20, 20_000)
        return text.count > room ? String(text.prefix(room)) : text
    }
}
