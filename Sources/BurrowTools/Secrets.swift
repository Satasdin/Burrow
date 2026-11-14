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
        #"(?:[A-Za-z0-9_.-]*(?i:token(?!s|izer)|secret|passw(?:or)?d|passphrase|credentials?|(?:api|access|private|signing|encryption|master|license|account|client|secret)[_-]?key|apikey)[A-Za-z0-9_.-]*|[A-Z0-9_]*_KEY)(?<!Error)(?<!Exception)(?<!Warning)"#

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
        (#"\b("# + secretName + #")(\s*=\s*)"# + notMarker + notNumber + #"(?!\$)("[^"]*"|'[^']*'|[^\s"'&;,)]+)"#, "$1$2" + marker),
        // "name": value with a secret's name, as JSON, YAML or a header writes it. Unquoted, the value must be 8 or more
        // characters, so "Invalid token: expired" in an error line stays as printed.
        (#"(["']?)\b("# + secretName + #")\1(\s*:\s*)"# + notMarker + notNumber + #"("[^"]+"|'[^']+'|[^\s"',}]{8,})"#, "$1$2$1$3" + marker),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    /// The text with every secret Burrow can recognise replaced by the marker.
    public static func redacted(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var out = text
        for (rule, template) in rules {
            out = rule.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: template)
        }
        return out
    }
}
