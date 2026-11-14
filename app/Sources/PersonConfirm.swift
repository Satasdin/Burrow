import AppKit
import BurrowCore
import BurrowTools

/// The app is the person's own UI, so it takes the steps only the person may take directly, each with its own native
/// question (D-113). It listens on no port and receives nothing from burrow: the one-time codes burrow asks for in a
/// terminal are shown only as notifications, since an ad-hoc signed app can't prove to burrow that it is the app.
@MainActor
enum PersonConfirm {
    /// Before a decision's check is confirmed: exactly what runs, where, its time limit, and that a program proposed it.
    static func confirmCheck(_ check: DecisionCheck, decision: String, folder: String?) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Confirm this check for \(decision)?"
        let runs = check.kind == .command
            ? "Burrow will run this whenever a change touches the decision, in \(Printable.clean(folder ?? "no linked folder (it would be held as unable to run)")), with no shell, stopped after \(check.timeout) seconds:\n\n\(check.shown)"
            : "Any change adding a line that matches this will be held as breaking the decision:\n\n\(check.shown)"
        alert.informativeText = runs + "\n\nProposed by \(Printable.clean(check.by)), not by you."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Confirm Check")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
