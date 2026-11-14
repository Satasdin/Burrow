import BurrowCore
import CryptoKit
import Foundation

/// A change that goes against a decision is held until the decision has been shown beside it (D-93). burrow_check runs
/// only when the model calls it (Claude 9 of 9, Gemma 0 of 4, and Gemma broke the decision without a word), so the same
/// check also runs from outside the model: `burrow check`, Claude Code's Stop hook, and git's pre-commit hook.
///
/// "Shown" is kept per change: a fingerprint of the decisions shown and the exact content of the changed files they rest
/// on. Once any of the four has shown it, the same change passes; a different change to those files is held again.
public enum Gate {
    /// What one check found and what it means for the gate.
    public struct Outcome: Sendable {
        public let report: CheckReport
        /// The words burrow_check would give for this report (`VaultTools.checkText`).
        public let text: String
        /// Nil when no decision rests on the change.
        public let fingerprint: String?
        /// Whether this exact change had been shown before this check.
        public let shownBefore: Bool

        /// A decision rests on the change and this exact change had not been shown.
        public var holds: Bool { fingerprint != nil && !shownBefore }
        /// `burrow check`'s exit code: 0 nothing to hold, 2 held. Errors are 1, from the command itself.
        public var exitCode: Int32 { holds ? 2 : 0 }
    }

    /// The fingerprint of a report's change, or nil when no decision rests on it: the ids of the decisions shown and each
    /// resting file with its git blob id, so the working tree and the index agree on the same content.
    public static func fingerprint(_ report: CheckReport) -> String? {
        guard !report.rules.isEmpty else { return nil }
        var text = "decisions " + report.rules.map(\.id).sorted().joined(separator: ",") + "\n"
        for path in report.resting.sorted() { text += path + "\t" + (report.hashes[path] ?? "unknown") + "\n" }
        return SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    static func folder(_ vault: Vault) -> URL { vault.store.appendingPathComponent("checks") }

    public static func wasShown(_ fingerprint: String, vault: Vault) -> Bool {
        FileManager.default.fileExists(atPath: folder(vault).appendingPathComponent(fingerprint + ".json").path)
    }

    /// Keeps that this change was shown, and by what. Nothing when no decision rests on it. Never throws: a check that
    /// cannot write still shows the decisions, it only means the same change is held again next time.
    public static func record(_ report: CheckReport, vault: Vault, by: String, now: Date = Date()) {
        guard let fingerprint = fingerprint(report) else { return }
        let entry: [String: Any] = [
            "shown_by": by,
            "at": ISO8601DateFormatter().string(from: now),
            "decisions": report.rules.map(\.id),
            "files": report.resting.map { [$0, report.hashes[$0] ?? "unknown"] },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
        try? FileManager.default.createDirectory(at: folder(vault), withIntermediateDirectories: true)
        try? data.write(to: folder(vault).appendingPathComponent(fingerprint + ".json"), options: .atomic)
    }

    /// Runs the check, says whether this exact change had been shown, and records it as shown now.
    public static func check(vault: Vault, staged: Bool = false, only: String? = nil, by: String) -> Outcome {
        let report = VaultTools.checkReport(vault: vault, ledger: Ledger(vault: vault), staged: staged, only: only)
        let print = fingerprint(report)
        let before = print.map { wasShown($0, vault: vault) } ?? false
        record(report, vault: vault, by: by)
        return Outcome(report: report, text: VaultTools.checkText(report).text, fingerprint: print, shownBefore: before)
    }

    /// What the Stop hook adds after the check's own words.
    public static let stopNote = "Burrow held your reply: this change rests on a decision kept in the Ledger, and it had not been checked against it. In your reply, tell the person which decision this change touches and whether it goes against it, in plain words."

    /// Claude Code's Stop event: the block reply when the change touches a decision that was not shown, else nil.
    /// When Claude is already continuing because of a stop hook (`stop_hook_active`), it never holds again, so it cannot loop.
    public static func stop(event: [String: Any], vault: Vault) -> String? {
        if event["stop_hook_active"] as? Bool == true { return nil }
        let outcome = check(vault: vault, by: "Claude Code's Stop hook")
        guard outcome.holds else { return nil }
        let reply: [String: Any] = ["decision": "block", "reason": outcome.text + "\n\n" + stopNote]
        guard let data = try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// `burrow check --json`.
    public static func json(_ outcome: Outcome) -> [String: Any] {
        [
            "exit": Int(outcome.exitCode),
            "held": outcome.holds,
            "shown_before": outcome.shownBefore,
            "fingerprint": outcome.fingerprint ?? NSNull(),
            "changed": outcome.report.changed,
            "build_output": outcome.report.buildOutput,
            "resting": outcome.report.resting,
            "decisions": outcome.report.rules.map { rule -> [String: Any] in
                ["id": rule.id, "kind": rule.kind.rawValue, "message": rule.message, "because": rule.because ?? NSNull(),
                 "rejected": rule.rejected ?? NSNull(), "files": rule.cites.keys.sorted(), "by": rule.byline]
            },
            "text": outcome.text,
        ]
    }

    /// git's pre-commit hook: refuses a commit whose staged change touches a decision until it has been shown once.
    /// `burrow` and `vault` come shell-quoted. A Burrow error never blocks a commit; it is only reported.
    public static func preCommitScript(burrow: String, vault: String) -> String {
        """
        #!/bin/sh
        # Burrow's git gate (D-93): a commit whose staged change touches a decision kept in the Ledger is refused once,
        # with the decisions printed. Seeing them is the acknowledgement: the same change commits on the next try.
        # A different change to those files is held again. git commit --no-verify skips this, as for any hook.
        out=$(\(burrow) check \(vault) --staged 2>&1)
        status=$?
        if [ "$status" -eq 2 ]; then
          printf '%s\\n\\n' "$out" 1>&2
          echo "burrow: commit refused. This change touches the decision(s) above. Read them; if the change still stands, commit again and it goes through." 1>&2
          exit 1
        fi
        if [ "$status" -ne 0 ]; then
          printf '%s\\n' "$out" 1>&2
          echo "burrow: the decision check could not run (status $status); committing anyway." 1>&2
          exit 0
        fi
        # Passing: only Burrow's own one-line note, if any ("this exact change was shown before").
        printf '%s\\n' "$out" | grep '^burrow: ' 1>&2
        exit 0

        """
    }
}
