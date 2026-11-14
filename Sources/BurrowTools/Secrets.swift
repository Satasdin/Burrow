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

    /// A name that says its value is a secret: OPENAI_API_KEY, db_password, access_token, client-secret, X-Api-Key.
    /// Not "tokens" or "tokenizer": max_tokens and the like are settings.
    /// Not an exception's name (InvalidTokenError: …): an error line stays as printed.
    private static let secretName =
        #"(?:[A-Za-z0-9_.-]{0,64}(?i:token(?!s|izer)|secret|passw(?:or)?d|passphrase|credentials?|(?:api|access|private|signing|encryption|master|license|account|client|secret)[_-]?key|apikey)[A-Za-z0-9_.-]{0,64}|[A-Z0-9_]{0,64}_KEY)(?<!Error)(?<!Exception)(?<!Warning)"#

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
        // NAME=value with a secret's name: OPENAI_API_KEY=..., export DB_PASSWORD="...", ?access_token=...
        (#"("# + secretName + #")(\s*=\s*)"# + notMarker + notNumber + #"(?!\$)("[^"]*"|'[^']*'|[^\s"'&;,)]+)"#, "$1$2" + marker),
        // "name": value with a secret's name, as JSON, YAML or a header writes it. Unquoted, the value must be 8 or more
        // characters, so "Invalid token: expired" in an error line stays as printed.
        (#"(["']?)("# + secretName + #")\1(\s*:\s*)"# + notMarker + notNumber + #"("[^"]+"|'[^']+'|[^\s"',}]{8,})"#, "$1$2$1$3" + marker),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    /// The text with every secret Burrow can recognise replaced by the marker. Names are bounded (64 characters each
    /// side), and the name rules run on pieces of at most `piece` characters, so no line, however long, makes a pattern
    /// backtrack for long (D-106). Nothing is skipped for being long: a piece that can't be cut safely and has a secret's
    /// word in it is replaced whole (fails closed).
    public static func redacted(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var out = text
        for (rule, template) in rules.dropLast(named) {
            out = rule.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: template)
        }
        guard nameWords.contains(where: out.lowercased().contains) else { return out }
        return pieces(of: out).map { piece -> String in
            guard nameWords.contains(where: piece.text.lowercased().contains) else { return piece.text }
            guard piece.safe else { return marker }
            var kept = piece.text
            for (rule, template) in rules.suffix(named) {
                kept = rule.stringByReplacingMatches(in: kept, range: NSRange(kept.startIndex..., in: kept), withTemplate: template)
            }
            return kept
        }.joined()
    }

    /// Longest piece the name rules run on.
    static let piece = 2_000

    /// The text cut into consecutive pieces of at most `piece` characters that join back to it exactly. A cut is made only
    /// at a space, a line break or one of & ; , outside quotes and not next to = or :, so a name and its value are never
    /// split. A stretch with no such place is one piece, marked not safe.
    static func pieces(of text: String) -> [(text: String, safe: Bool)] {
        let chars = Array(text)
        guard chars.count > piece else { return [(text, true)] }
        var result: [(text: String, safe: Bool)] = []
        var start = 0, lastCut: Int? = nil, quote: Character? = nil
        func isCut(_ i: Int) -> Bool {
            guard quote == nil, " \t\n\r&;,".contains(chars[i]) else { return false }
            var before = i - 1
            while before >= start, chars[before] == " " { before -= 1 }
            var after = i + 1
            while after < chars.count, chars[after] == " " { after += 1 }
            let near: Set<Character> = ["=", ":"]
            return !(before >= start && near.contains(chars[before])) && !(after < chars.count && near.contains(chars[after]))
        }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" || c == "'" { quote = quote == nil ? c : (quote == c ? nil : quote) }
            if isCut(i) { lastCut = i }
            if i - start + 1 >= piece {
                if let cut = lastCut, cut >= start {
                    result.append((String(chars[start...cut]), true)); start = cut + 1
                } else {
                    // No safe place: run on to the next one, and mark the whole stretch not safe.
                    var j = i + 1
                    while j < chars.count, !(" \t\n\r".contains(chars[j])) { j += 1 }
                    let stop = j - 1   // the stretch up to, not including, the space that ends it
                    result.append((String(chars[start...stop]), false)); start = stop + 1; i = stop
                }
                lastCut = nil
            }
            i += 1
        }
        if start < chars.count { result.append((String(chars[start...]), true)) }
        return result
    }

    /// The text cut to `limit` characters, before secrets are taken out, at a space so no secret is cut in half and left
    /// partly unrecognised. A text with no space in its last 200 characters is cut there whole (D-106).
    public static func cutForRedaction(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        if let space = head.lastIndex(where: { $0 == " " || $0 == "\n" || $0 == "\t" }),
           head.distance(from: space, to: head.endIndex) <= 200 {
            return String(head[..<space])
        }
        return String(head.dropLast(200))
    }

    /// How many of `rules`, at the end, match by a secret's name.
    private static let named = 2
    /// A secret's name always has one of these in it (lowercased), so a line without one can't match by name.
    private static let nameWords = ["token", "secret", "passw", "passphrase", "credential", "key"]
}
