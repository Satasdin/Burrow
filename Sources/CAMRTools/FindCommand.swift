import CAMRCore
import Foundation

/// What `camr find` prints. It lives here, not in the command, so a test can run it with an embedder that fails.
public enum FindCommand {
    /// The one line printed when meaning search was skipped (D-122).
    public static let wordsOnly = "Meaning search was skipped because the local model service could not embed the question, so these are ranked by words only."

    /// Searches, falling back to words when the question can't be embedded, and returns the text to print.
    public static func output(_ vault: Vault, _ question: String, mode: Mode, embedder: Embedder?, json: Bool) async throws -> String {
        let (found, failure) = try await vault.retrieveFallingBackToWords(question, mode: mode, embedder: embedder)
        if json {
            var value: [String: Any] = ["seconds": found.seconds, "characters": found.characters, "excerpts": describe(found)]
            if failure != nil { value["meaningSkipped"] = wordsOnly }
            return String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self)
        }
        var lines = found.excerpts.map { "\($0.path):\($0.startLine)-\($0.endLine)   [\($0.reason.label)]" }
        lines.append(String(format: "\n%d characters in %.3f s", found.characters, found.seconds))
        if failure != nil { lines.append(wordsOnly) }
        return lines.joined(separator: "\n")
    }

    /// The excerpts as `--json` shows them.
    public static func describe(_ found: Retrieved) -> [[String: Any]] {
        found.excerpts.map {
            ["path": $0.path, "start": $0.startLine, "end": $0.endLine, "reason": $0.reason.label, "note": $0.isNote]
        }
    }
}
