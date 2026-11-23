import CAMRCore
import CAMRTools
import SwiftUI

/// A decision's check as the app holds it (D-107).
struct DecisionCheckState: Sendable, Equatable {
    /// Confirmed by the person on this Mac: runs whenever a change touches the decision.
    var confirmed: DecisionCheck?
    /// Proposed by a program (or carried by a shared vault): shown, never run until confirmed.
    var proposed: DecisionCheck?
    /// The linked folder a command would run in, or nil when none of the decision's files is in one.
    var folder: String?
}

/// The check under a decision in the Ledger: what it runs, and, for one a program proposed, a Confirm button. The app is
/// the person, so confirming here is the same yes as typing it in their own terminal, and it shows the same things the
/// terminal's question does: the whole command, where it runs, its time limit, and that a program proposed it.
struct DecisionCheckRow: View {
    let workspace: Workspace
    let commit: LedgerCommit

    private var state: DecisionCheckState? { workspace.ledger.checks[commit.id] }
    private static let green = Color(red: 0.42, green: 0.92, blue: 0.66)

    var body: some View {
        if let state {
            VStack(alignment: .leading, spacing: 6) {
                if let check = state.confirmed {
                    Label(check.kind == .forbid ? "Check: no added line may match" : "Check: runs on every change that touches this",
                          systemImage: "checkmark.seal").font(.system(size: 11, weight: .semibold)).foregroundStyle(Self.green)
                    code(check.shown)
                }
                if let check = state.proposed {
                    Label("Proposed check, not run. A program proposed it, not you: \(Printable.clean(check.by))", systemImage: "questionmark.diamond")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(WatchPanel.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    code(check.shown)
                    if check.kind == .command {
                        Text("Runs in \(Printable.clean(state.folder ?? "no linked folder: none of this decision's files is in one, so it would be held as unable to run")), with no shell, stopped after \(check.timeout) seconds. If it fails or can't run, the change is held as breaking this decision.")
                            .font(.system(size: 11)).foregroundStyle(Night.dim).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    } else {
                        Text("If confirmed, a change adding a line that matches is held as breaking this decision.")
                            .font(.system(size: 11)).foregroundStyle(Night.dim).fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        // The app is the person's own UI: its own question, then the check is confirmed (D-113).
                        guard PersonConfirm.confirmCheck(check, decision: commit.id, folder: state.folder) else { return }
                        Task { await workspace.confirmCheck(commit.id, check) }
                    } label: { Label("Confirm Check", systemImage: "checkmark.circle") }
                        .controlSize(.small)
                        .help("Run this check whenever a change touches this decision. Only you can confirm it.")
                }
            }
            .padding(8)
            .background((state.proposed == nil ? Self.green : WatchPanel.amber).opacity(0.07), in: .rect(cornerRadius: 8))
        }
    }

    /// The whole command, never cut: what is shown is exactly what runs.
    private func code(_ text: String) -> some View {
        Text(text).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Night.note.opacity(0.85)).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
