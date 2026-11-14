import AppKit
import BurrowCore
import BurrowTools

/// The app's side of D-113's one-time code: when `burrow` in a terminal asks to override a breaking change, or to
/// confirm or take away a decision's check, it sends the code here (a local Mach port named for this Mac's Burrow
/// folder) and the app shows it in a small sheet. The code is never in the terminal, so a program driving that terminal
/// can't read it; the person reads it here and types it there. The sheet closes itself when the code expires.
@MainActor
enum PersonCodeSheet {
    private static var open: [NSAlert] = []

    static func start() {
        let listening = PersonCodeInbox.listen(state: BurrowPlaces.stateFolder) { request in
            MainActor.assumeIsolated { show(request) }
        }
        if !listening {
            // Another process holds the port name: say so, since codes will then come only as notifications.
            let alert = NSAlert()
            alert.messageText = "Burrow can't show terminal codes here"
            alert.informativeText = "Something else on this Mac took the channel burrow uses to send codes to this app. Codes for overriding or confirming a decision's check will come as notifications instead. If you didn't expect this, quit the other program and reopen Burrow."
            alert.runModal()
        }
    }

    private static func show(_ request: PersonCodeInbox.Request) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Burrow code  \(request.code.prefix(3)) \(request.code.suffix(3))"
        alert.informativeText = "burrow in a terminal asks to \(Printable.clean(request.action)).\n\nType this code there only if you asked for this yourself. Never give it to a program or paste it into a chat. It works once, until \(request.expires.formatted(date: .omitted, time: .shortened))."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Done")
        open.append(alert)
        let close = { [weak alert] in
            guard let alert else { return }
            if let window = alert.window.sheetParent { window.endSheet(alert.window) } else { alert.window.close() }
            open.removeAll { $0 === alert }
        }
        if let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
            alert.beginSheetModal(for: window) { _ in open.removeAll { $0 === alert } }
        } else {
            alert.window.level = .floating
            alert.window.makeKeyAndOrderFront(nil)
            alert.buttons.first?.target = alert.window
            alert.buttons.first?.action = #selector(NSWindow.close)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, request.expires.timeIntervalSinceNow)) { close() }
    }

    /// The app is the person's own UI, so it confirms a decision's check directly, with its own native question first
    /// (D-113): exactly what runs, where, and that a program proposed it.
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
