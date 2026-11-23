import CAMRCore
import CAMRTools
import Foundation

let decisionUsage = """
  camr decision check <vault> <decision> [--set "command" | --set "forbid: pattern"] [--timeout SECONDS]
                                           [--confirm] [--clear]          a decision's check: shown, set, confirmed or taken away
  camr decision override <vault> <decision>                             let this exact change through although its check fails
"""

/// Said when a step only the person may take is run without a terminal (D-104, D-107).
let checksNeedThePerson = "only you can confirm, change or override a decision's check: do it in the CAMR app, or run this in your own terminal. It can't be done through a pipe or by a program you've connected to CAMR."

/// Shows the person what they are about to allow and waits for a typed yes. False for anything else. Confirming,
/// clearing or overriding a check defeats the gate a connected program is held by, so each also needs the one-time code
/// CAMR shows outside the terminal, typed before the yes (D-113); a wrong or missing code is said and allows nothing.
func personSaysYes(_ lines: [String], code action: String) -> Bool {
    do { try askThePerson(lines, code: action) } catch {
        logToStandardError("\(error)")
        return false
    }
    return true
}

/// What the person is shown before a check runs on this Mac: exactly what would run, where, and for how long.
func checkQuestion(_ check: DecisionCheck, decision: LedgerCommit, folder: String?) -> [String] {
    var lines = ["Decision \(decision.id): \(Printable.clean(String(decision.message.prefix(200))))"]
    switch check.kind {
    case .command:
        lines.append("Run this whenever camr check finds a change touching it (no shell, stopped after \(check.timeout) seconds):")
        lines.append("  \(check.shown)")
        lines.append("  in \(Printable.clean(folder ?? "the linked folder its files are in"))")
        lines.append("If it fails, the change is held as breaking the decision, and seeing it does not let it through.")
    case .forbid:
        lines.append("Hold any change that adds a line matching this pattern to the files it rests on:")
        lines.append("  \(check.shown)")
    }
    if check.by != "you" { lines.append("Proposed by \(Printable.clean(check.by)), not by you.") }
    return lines
}

/// The linked folder a decision's check runs in, for the question.
func checkFolder(_ vault: Vault, _ decision: LedgerCommit) -> String? {
    let folders = vault.linkedFolders()
    for path in decision.cites.keys.sorted() {
        if let folder = folders.first(where: { path.hasPrefix($0.name + "/") }) { return folder.path }
    }
    return nil
}

/// Keeps a check for a decision: confirmed when the person is at their own terminal and types yes, else proposed, shown
/// and never run (D-107). Returns the line to print.
func keepCheck(_ check: DecisionCheck, for decision: LedgerCommit, vault: Vault) throws -> String {
    if inPersonsTerminal(), personSaysYes(checkQuestion(check, decision: decision, folder: checkFolder(vault, decision)), code: "confirm the check for decision \(decision.id)") {
        try DecisionChecks.confirm(check, for: decision.id, vault: vault)
        return "    check confirmed: \(check.shown). camr check runs it whenever a change touches this decision." + tryNow(check, decision, vault)
    }
    try DecisionChecks.propose(check, for: decision.id, vault: vault)
    return "    check proposed, not run: \(check.shown). Only you can confirm it: in the CAMR app, or in your own terminal with camr decision check \(Printable.shellWord(vault.root.path)) \(decision.id) --confirm"
}

/// A command check, run once on the code as it is, so the person knows straight away whether it holds now: one that
/// fails already would hold every change touching the decision as breaking it.
func tryNow(_ check: DecisionCheck, _ decision: LedgerCommit, _ vault: Vault) -> String {
    guard check.kind == .command, let folder = checkFolder(vault, decision) else { return "" }
    let run = DecisionChecks.run(check, in: URL(fileURLWithPath: folder), added: [:])
    switch run.status {
    case .passed: return "\n    It passes on the code as it is now (\(String(format: "%.1f", run.seconds)) s)."
    case .failed: return "\n    It FAILS on the code as it is now (exit \(run.exitStatus ?? -1)): every change touching \(decision.id) will be held as breaking it until it passes.\n" + run.output.components(separatedBy: "\n").suffix(8).map { "      " + $0 }.joined(separator: "\n")
    case .couldNotRun: return "\n    It could not run on the code as it is now: \(run.output.components(separatedBy: "\n").first ?? "")"
    }
}

/// `camr decision …`. Returns false when the command is not this one.
func runDecisionCommand(_ arguments: [String]) async throws -> Bool {
    guard arguments.first == "decision" else { return false }
    var positional: [String] = [], values: [String: String] = [:], switches: Set<String> = []
    var index = 1
    while index < arguments.count {
        let word = arguments[index]
        if ["--set", "--timeout", "--store"].contains(word), index + 1 < arguments.count { values[word] = arguments[index + 1]; index += 2 }
        else if ["--confirm", "--clear"].contains(word) { switches.insert(word); index += 1 }
        else { positional.append(word); index += 1 }
    }
    guard positional.count >= 3, ["check", "override"].contains(positional[0]) else { throw Failure(decisionUsage) }
    let action = positional[0]
    // Changing what runs, or letting a breaking change through, needs the person in their own terminal (D-104), checked
    // before anything is opened. Setting a check without one only proposes it.
    if action == "override" || switches.contains("--confirm") || switches.contains("--clear") { try requireThePerson(checksNeedThePerson) }
    let vault = try openVault(positional[1], store: values["--store"])
    let ledger = Ledger(vault: vault)
    guard let decision = ledger.find(positional[2]), [.decision, .correction].contains(decision.kind) else {
        throw Failure("there is no decision \(Printable.clean(positional[2]))")
    }
    let confirmed = DecisionChecks.confirmed(vault)[decision.id], proposed = DecisionChecks.proposed(vault)[decision.id]

    if action == "override" {
        let outcome = Gate.check(vault: vault, by: "camr decision override")
        guard let verdict = outcome.verdicts.first(where: { $0.decision == decision.id }), verdict.kind == .breaks,
              let changeID = outcome.fingerprint else {
            print("Nothing to override: the change now does not fail \(decision.id)'s check.")
            return true
        }
        if verdict.overridden { print("This exact change was already let through for \(decision.id)."); return true }
        var lines = ["Decision \(decision.id): \(Printable.clean(String(decision.message.prefix(200))))", "Your change breaks it: " + Printable.clean(verdict.line)]
        if case let .ran(_, run) = verdict.check { lines.append(run.output.components(separatedBy: "\n").suffix(12).map { "  " + $0 }.joined(separator: "\n")) }
        lines.append("Let this exact change through? Any further edit to these files is checked again.")
        guard personSaysYes(lines, code: "let a change through although it breaks decision \(decision.id)") else { throw Failure("nothing was let through") }
        try DecisionChecks.override(decision.id, fingerprint: changeID, vault: vault)
        print("let through: this exact change, for \(decision.id). Any further edit to these files is checked again.")
        return true
    }

    if switches.contains("--clear") {
        guard confirmed != nil || proposed != nil else { print("\(decision.id) has no check."); return true }
        guard personSaysYes(["Take away the check for \(decision.id) (\((confirmed ?? proposed)!.shown))? Changes are then no longer tested against it."],
                            code: "take away the check for decision \(decision.id)") else {
            throw Failure("nothing was changed")
        }
        try DecisionChecks.clear(for: decision.id, vault: vault)
        print("\(decision.id) has no check now.")
        return true
    }
    if let spec = values["--set"] {
        let timeout = Int(values["--timeout"] ?? "") ?? DecisionCheck.defaultTimeout
        let check: DecisionCheck
        do { check = try DecisionCheck.parse(spec, timeout: timeout, by: inPersonsTerminal() ? "you" : "terminal (no person)") }
        catch let problem as LedgerProblem { throw Failure(problem.description) }
        print(try keepCheck(check, for: decision, vault: vault).trimmingCharacters(in: .whitespaces))
        return true
    }
    if switches.contains("--confirm") {
        guard let check = proposed else {
            print(confirmed.map { "\(decision.id)'s check is already confirmed: \($0.shown)" } ?? "\(decision.id) has no proposed check to confirm.")
            return true
        }
        guard personSaysYes(checkQuestion(check, decision: decision, folder: checkFolder(vault, decision)), code: "confirm the check for decision \(decision.id)") else {
            throw Failure("nothing was confirmed")
        }
        try DecisionChecks.confirm(check, for: decision.id, vault: vault)
        print("check confirmed: \(check.shown). camr check runs it whenever a change touches \(decision.id)." + tryNow(check, decision, vault))
        return true
    }
    // Just show it.
    if let confirmed { print("\(decision.id) check, confirmed by \(Printable.clean(confirmed.by)) on this Mac: \(confirmed.shown)") }
    if let proposed { print("\(decision.id) check proposed by \(Printable.clean(proposed.by)), not run until you confirm it: \(proposed.shown)") }
    if confirmed == nil, proposed == nil { print("\(decision.id) has no check. Set one with: camr decision check <vault> \(decision.id) --set \"command\"") }
    if let anchors = decision.anchors, !anchors.isEmpty {
        print("rests on: " + anchors.sorted { $0.key < $1.key }.map { path, names in names.keys.sorted().joined(separator: ", ") + " (\(Printable.clean(path)))" }.joined(separator: "; "))
    }
    return true
}
