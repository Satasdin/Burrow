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

        /// Each decision judged (D-107). Empty when the check was not judged.
        public var verdicts: [DecisionVerdict] { report.verdicts }
        /// A decision's check failed and the person has not let this exact change through: it breaks the decision.
        /// Seeing it does not clear this; fixing the change, or the person overriding it, does (D-107).
        public var breaks: Bool { verdicts.contains(where: \.breaks) }
        /// A decision rests on the change, the change touched what it rests on (or that can't be told), and this exact
        /// change had not been shown. A change that leaves every decision's parts alone is not held (D-107).
        public var holds: Bool { fingerprint != nil && !shownBefore && (verdicts.isEmpty || verdicts.contains(where: \.needsLook)) }
        /// `burrow check`'s exit code: 0 nothing to hold, 2 held until shown once, 3 breaks a decision. Errors are 1.
        public var exitCode: Int32 { breaks ? 3 : holds ? 2 : 0 }
        /// One word for the whole change: breaks, affected, unprovable, unaffected, or nothing (no decision touched).
        public var verdict: String {
            guard fingerprint != nil else { return "nothing" }
            if breaks { return "breaks" }
            if verdicts.isEmpty || verdicts.contains(where: { $0.kind == .affected || ($0.kind == .breaks && $0.overridden) }) { return "affected" }
            if verdicts.contains(where: { $0.kind == .unprovable }) { return "unprovable" }
            return "unaffected"
        }
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

    /// Runs the check, judges each decision (running the person's checks, D-107), says whether this exact change had
    /// been shown, and records it as shown now.
    /// `record: false` judges without counting the change as shown.
    public static func check(vault: Vault, staged: Bool = false, only: String? = nil, by: String, record keep: Bool = true) -> Outcome {
        var report = VaultTools.checkReport(vault: vault, ledger: Ledger(vault: vault), staged: staged, only: only)
        let print = fingerprint(report)
        report.verdicts = Verdicts.judge(vault: vault, report: report, staged: staged, fingerprint: print)
        let before = print.map { wasShown($0, vault: vault) } ?? false
        if keep { record(report, vault: vault, by: by) }
        return Outcome(report: report, text: VaultTools.checkText(report).text, fingerprint: print, shownBefore: before)
    }

    /// What the Stop hook adds after the check's own words.
    public static let stopNote = "Burrow held your reply: this change rests on a decision kept in the Ledger, and it had not been checked against it. In your reply, tell the person which decision this change touches and whether it goes against it, in plain words."

    /// What the Stop hook adds when the change breaks a decision (D-107).
    public static let breakNote = "Burrow held your reply: your change breaks a decision kept in the Ledger: the check the person set for it failed or could not run (its output is above). Change your work so the check passes, or undo that part. If the person asked for this knowing the decision, stop and tell them which decision it breaks; only they can let it through, in their own terminal."

    /// How many times the Stop hook holds the same breaking change before it lets Claude stop and tell the person.
    public static let breakHolds = 3

    /// Claude Code's Stop event: the block reply when the change breaks a decision (always, up to `breakHolds` times for
    /// the same change), or touches one that was not shown (once), else nil. When Claude is already continuing because
    /// of a stop hook (`stop_hook_active`), only a break is held again, so a change that was only shown cannot loop.
    public static func stop(event: [String: Any], vault: Vault) -> String? {
        let again = event["stop_hook_active"] as? Bool == true
        // Continuing because of a stop hook, only a break can hold, so nothing else is counted as shown there.
        let outcome = check(vault: vault, by: "Claude Code's Stop hook", record: !again)
        let note: String
        if outcome.breaks, let print = outcome.fingerprint {
            // The same breaking change held this many times already: Claude is told, and the person sees it, but a
            // model that cannot fix it is not kept going round.
            let counter = folder(vault).appendingPathComponent(print + ".breaks")
            let held = Int((try? String(contentsOf: counter, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
            guard held < breakHolds else { return nil }
            try? FileManager.default.createDirectory(at: folder(vault), withIntermediateDirectories: true)
            try? String(held + 1).write(to: counter, atomically: true, encoding: .utf8)
            note = breakNote
        } else {
            guard !again, outcome.holds else { return nil }
            note = stopNote
        }
        let reply: [String: Any] = ["decision": "block", "reason": outcome.text + "\n\n" + note]
        guard let data = try? JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// `burrow check --json`.
    public static func json(_ outcome: Outcome) -> [String: Any] {
        [
            "exit": Int(outcome.exitCode),
            "held": outcome.holds,
            "breaks": outcome.breaks,
            "verdict": outcome.verdict,
            "verdicts": outcome.verdicts.map(\.json),
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
        if [ "$status" -eq 3 ]; then
          printf '%s\\n\\n' "$out" 1>&2
          echo "burrow: commit refused. This change breaks a decision: the check set for it failed or could not run (above). Seeing it does not let it through: fix the change. Only you can override it, in your own terminal: \(burrow) decision override \(vault) <decision id>" 1>&2
          exit 1
        fi
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
