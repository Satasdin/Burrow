import CAMRCore
import Foundation

/// What `camr check` says about one decision a change touches (D-107): not only "this change touches a decision, look
/// first" (D-93), but whether it breaks it, touched what it rests on, left that alone, or can't be told.
public struct DecisionVerdict: Sendable {
    public enum Kind: String, Sendable {
        /// The check the person set for the decision failed, or could not run: CAMR can't say the change keeps to it.
        case breaks
        /// The change touched the functions, classes or blocks the decision rests on.
        case affected
        /// It changed the decision's files, but not the parts the decision rests on.
        case unaffected
        /// CAMR can't tell: no parts are known for the decision, or a file did not parse.
        case unprovable
    }

    /// Whether the decision has a check, and what became of it.
    public enum Check: Sendable {
        case none
        /// Proposed by a program and not confirmed by the person: shown, never run.
        case proposed(DecisionCheck)
        case ran(DecisionCheck, CheckRun)
    }

    public let decision: String
    public var kind: Kind
    /// The parts the change touched, as "name (file)".
    public var touched: [String] = []
    /// The parts the decision rests on, as "name (file)": the ones named or kept with it, then what they call.
    public var restsOn: [String] = []
    /// Where those came from: "kept with the decision", "named in the decision", or empty when none are known.
    public var restsOnFrom = ""
    /// Parts of the decision's files the change did touch, outside what it rests on.
    public var elsewhere: [String] = []
    /// Why it can't be told, for unprovable.
    public var why = ""
    /// A part kept with the decision whose body had already changed in an earlier commit.
    public var movedSinceKept: [String] = []
    public var check: Check = .none
    /// The person let this exact change through although its check failed.
    public var overridden = false

    /// True when this verdict holds the change: a failed check the person has not overridden.
    public var breaks: Bool { kind == .breaks && !overridden }
    /// True when the change should be looked at once (exit 2 until shown).
    public var needsLook: Bool { kind == .affected || kind == .unprovable || (kind == .breaks && overridden) }

    /// One line in plain words.
    public var line: String {
        var text: String
        switch kind {
        case .breaks:
            if case let .ran(check, run) = check, run.status == .couldNotRun {
                let why = run.output.components(separatedBy: "\n").first ?? ""
                text = overridden
                    ? "\(decision): its check could not run (\(check.shown): \(why)), but the person let this exact change through."
                    : "\(decision): your change is held as breaking it, because the check set for this decision could not run (\(check.shown): \(why)), so CAMR can't say your change keeps to it. Fix what stops the check running, or ask the person; only they can let this change through."
            } else if case let .ran(check, run) = check {
                let status = run.exitStatus.map { ", exit \($0)" } ?? ""
                text = overridden
                    ? "\(decision): its check failed (\(check.shown)\(status)), but the person let this exact change through."
                    : "\(decision): your change BREAKS it. The check set for this decision failed (\(check.shown)\(status)). Fix the change so the check passes, or undo it."
            } else {
                text = "\(decision): your change BREAKS it."
            }
        case .affected:
            text = "\(decision): your change touches what it rests on: \(Self.list(touched)). Read your change against it."
        case .unaffected:
            text = "\(decision): your change leaves what it rests on as it was (\(Self.list(restsOn)))"
                + (elsewhere.isEmpty ? "." : "; it changed only \(Self.list(elsewhere)).")
        case .unprovable:
            text = "\(decision): CAMR can't tell whether your change touches what it rests on: \(why). Read your change against it."
        }
        switch check {
        case .none: break
        case let .proposed(check): text += " A check was proposed for it (\(check.shown)) but the person has not confirmed it, so it was not run."
        case let .ran(check, run):
            if run.status == .passed { text += " Its check passed (\(check.shown))." }
        }
        if !movedSinceKept.isEmpty, kind != .breaks {
            text += " Already changed in an earlier commit since the decision was kept: \(Self.list(movedSinceKept))."
        }
        return text
    }

    static func list(_ items: [String]) -> String {
        items.count > 6 ? items.prefix(6).joined(separator: ", ") + " and \(items.count - 6) more" : items.joined(separator: ", ")
    }

    public var json: [String: Any] {
        var out: [String: Any] = [
            "decision": decision, "verdict": kind.rawValue, "touched": touched, "rests_on": restsOn, "rests_on_from": restsOnFrom,
            "elsewhere": elsewhere, "overridden": overridden, "line": line,
        ]
        if !why.isEmpty { out["why"] = why }
        if !movedSinceKept.isEmpty { out["moved_since_kept"] = movedSinceKept }
        switch check {
        case .none: out["check"] = NSNull()
        case let .proposed(check): out["check"] = ["status": "proposed", "runs": check.shown]
        case let .ran(check, run):
            var shown: [String: Any] = ["status": run.status.rawValue, "runs": check.shown, "output": run.output, "seconds": (run.seconds * 10).rounded() / 10]
            if let status = run.exitStatus { shown["exit_status"] = Int(status) }
            out["check"] = shown
        }
        return out
    }
}

/// Places a change against the decisions it touches (D-107), each layer saying only what it knows: the decision's check,
/// when the person set one, says whether the change breaks it; the symbols it rests on say whether the change touched
/// them, left them alone, or can't be told.
public enum Verdicts {
    /// A vault path in a linked git folder: the folder and the path inside it.
    struct Place { let folder: URL; let path: String }

    static func place(_ vaultPath: String, _ folders: [LinkedFolder]) -> Place? {
        for folder in folders where vaultPath.hasPrefix(folder.name + "/") {
            return Place(folder: URL(fileURLWithPath: folder.path), path: String(vaultPath.dropFirst(folder.name.count + 1)))
        }
        return nil
    }

    /// A file before the change (its last git commit) and after it (the working tree, or the index when `staged`).
    /// Nil where it does not exist. A file outside the linked folders is the same on both sides.
    static func versions(_ vaultPath: String, vault: Vault, folders: [LinkedFolder], staged: Bool, changed: Bool) -> (before: String?, after: String?) {
        guard let place = place(vaultPath, folders) else { let text = vault.text(of: vaultPath); return (text, text) }
        let disk = try? String(contentsOf: place.folder.appendingPathComponent(place.path), encoding: .utf8)
        guard changed else { return (disk, disk) }
        let before = VaultTools.git(place.folder, ["show", "HEAD:" + place.path])
        let after = staged ? VaultTools.git(place.folder, ["show", ":" + place.path]) : disk
        return (before, after)
    }

    /// The lines a change adds to a file: from git's diff, or the whole file when git does not track it yet.
    static func added(_ vaultPath: String, folders: [LinkedFolder], staged: Bool) -> [String] {
        guard let place = place(vaultPath, folders) else { return [] }
        let against = staged ? ["diff", "--cached"] : ["diff", "HEAD"]
        let diff = VaultTools.git(place.folder, against + ["--no-color", "--no-ext-diff", "--no-textconv", "-U0", "--", place.path]) ?? ""
        if diff.isEmpty, !staged, VaultTools.git(place.folder, ["ls-files", "--error-unmatch", "--", place.path]) == nil {
            let text = (try? String(contentsOf: place.folder.appendingPathComponent(place.path), encoding: .utf8)) ?? ""
            return text.components(separatedBy: "\n")
        }
        return diff.components(separatedBy: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.map { String($0.dropFirst()) }
    }

    static func short(_ path: String) -> String { (path as NSString).lastPathComponent }

    static let backticked = try! NSRegularExpression(pattern: "`([A-Za-z_][A-Za-z0-9_.]*)(?:\\(\\))?`")
    static let called = try! NSRegularExpression(pattern: #"([A-Za-z_][A-Za-z0-9_]*)\(\)"#)

    /// The words in a decision that name code: in backticks, written as a call (`name()`), or shaped like an identifier
    /// (snake_case, camelCase). Plain words are left out, so "a statement line" never anchors a function called `line`.
    public static func codeNames(in text: String) -> Set<String> {
        var names = Outline.identifiers(in: text).filter { word in
            word.contains("_") || zip(word, word.dropFirst()).contains { $0.isLowercase && $1.isUppercase }
        }
        let range = NSRange(text.startIndex..., in: text)
        for pattern in [backticked, called] {
            for match in pattern.matches(in: text, range: range) {
                guard let found = Range(match.range(at: 1), in: text) else { continue }
                names.insert(String(text[found].split(separator: ".").last ?? ""))
            }
        }
        return names.subtracting([""])
    }

    // MARK: When a decision is kept

    /// The parts of a decision's cited files it is about, with a hash of each one's body as it is now: those its words
    /// name, or, when it names none in a file, those the session changed there since the last git commit. A file whose
    /// language CAMR can't outline gets none, and a decision with none is placed as before (D-93).
    public static func anchors(vault: Vault, text: String, files: [String]) -> [String: [String: String]] {
        let words = codeNames(in: text)
        let folders = vault.linkedFolders()
        var out: [String: [String: String]] = [:]
        for file in files {
            guard let path = Ledger.vaultPath(file), Outline.understands(path) else { continue }
            let (before, after) = versions(path, vault: vault, folders: folders, staged: false, changed: true)
            guard let now = after ?? vault.text(of: path), let outline = Outline.of(now, path: path) else { continue }
            var kept: [String: String] = [:]
            for symbol in outline.symbols where words.contains(symbol.name) { kept[symbol.qualified] = symbol.hash }
            if kept.isEmpty, let before, let old = Outline.of(before, path: path) {
                let earlier = Dictionary(old.symbols.map { ($0.qualified, $0.hash) }, uniquingKeysWith: { first, _ in first })
                for symbol in outline.symbols where earlier[symbol.qualified] != symbol.hash { kept[symbol.qualified] = symbol.hash }
                // Only the innermost: a method changed means its class changed too, and the class is not what was decided.
                let names = Set(kept.keys)
                for name in names where names.contains(where: { $0 != name && $0.hasPrefix(name + ".") }) { kept.removeValue(forKey: name) }
            }
            if !kept.isEmpty { out[path] = kept }
        }
        return out
    }

    // MARK: When a change is checked

    /// Each decision in the report, judged. Confirmed checks run here, so this is for `camr check`, the hooks and
    /// camr_check, not for a view that refreshes.
    public static func judge(vault: Vault, report: CheckReport, staged: Bool, fingerprint: String?) -> [DecisionVerdict] {
        guard !report.rules.isEmpty else { return [] }
        let folders = vault.linkedFolders()
        let confirmed = DecisionChecks.confirmed(vault), proposed = DecisionChecks.proposed(vault)
        let changed = Set(report.changed)
        var outlines: [String: (before: FileOutline?, after: FileOutline?, failed: Bool)] = [:]
        func outline(_ path: String) -> (before: FileOutline?, after: FileOutline?, failed: Bool) {
            if let known = outlines[path] { return known }
            let (before, after) = versions(path, vault: vault, folders: folders, staged: staged, changed: changed.contains(path))
            let one = before.map { Outline.of($0, path: path) } ?? nil
            let two = after.map { Outline.of($0, path: path) } ?? nil
            let failed = (before != nil && one == nil) || (after != nil && two == nil)
            outlines[path] = (one, two, failed)
            return (one, two, failed)
        }
        var addedLines: [String: [String]] = [:]

        return report.rules.map { rule in
            let cited = Set(rule.cites.keys)
            // The changed files this decision rests on: cited, or one import step from a cited file (D-75).
            let resting = report.changed.filter { cited.contains($0) || !report.near[$0, default: []].isDisjoint(with: cited) }
            var verdict = symbols(rule, cited: cited, resting: resting, outline: outline)

            // The check, when the decision has one.
            if let check = confirmed[rule.id] {
                let folder = rule.cites.keys.sorted().compactMap { place($0, folders)?.folder }.first
                    ?? resting.compactMap { place($0, folders)?.folder }.first
                if let folder {
                    var added: [String: [String]] = [:]
                    if check.kind == .forbid {
                        for path in resting {
                            if addedLines[path] == nil { addedLines[path] = Self.added(path, folders: folders, staged: staged) }
                            added[path] = addedLines[path]
                        }
                    }
                    let run = DecisionChecks.run(check, in: folder, added: added)
                    verdict.check = .ran(check, run)
                    // A check that could not run (stopped at its time limit, not found, would not start) fails closed:
                    // held as breaking, which only fixing it or the person's override clears.
                    if run.status != .passed {
                        verdict.kind = .breaks
                        verdict.overridden = DecisionChecks.overridden(rule.id, fingerprint: fingerprint, vault: vault)
                    }
                } else {
                    verdict.check = .ran(check, CheckRun(status: .couldNotRun, exitStatus: nil, output: "none of its files is in a linked folder", seconds: 0))
                    verdict.kind = .breaks
                    verdict.overridden = DecisionChecks.overridden(rule.id, fingerprint: fingerprint, vault: vault)
                }
            } else if let check = proposed[rule.id] {
                verdict.check = .proposed(check)
            }
            return verdict
        }
    }

    /// The symbol layer: did the change touch the parts the decision rests on?
    static func symbols(_ rule: LedgerCommit, cited: Set<String>, resting: [String],
                        outline: (String) -> (before: FileOutline?, after: FileOutline?, failed: Bool)) -> DecisionVerdict {
        var verdict = DecisionVerdict(decision: rule.id, kind: .unprovable)
        let files = Array(cited.union(resting)).sorted()
        // Every version of every file in play, and what each defines.
        var defined: [String: Set<String>] = [:]  // name → files
        for file in files {
            let (before, after, _) = outline(file)
            for symbol in (before?.symbols ?? []) + (after?.symbols ?? []) { defined[symbol.name, default: []].insert(file) }
        }

        // What the decision rests on: kept with it, else the names its own words give.
        var start: Set<String> = []
        if let kept = rule.anchors, !kept.isEmpty {
            for (_, names) in kept { for name in names.keys { start.insert(name.split(separator: ".").last.map(String.init) ?? name) } }
            verdict.restsOnFrom = "kept with the decision"
            for (path, names) in kept.sorted(by: { $0.key < $1.key }) {
                guard let before = outline(path).before else { continue }
                for (name, hash) in names.sorted(by: { $0.key < $1.key }) {
                    if let now = before.symbols.first(where: { $0.qualified == name }), now.hash != hash { verdict.movedSinceKept.append("\(name) (\(short(path)))") }
                }
            }
        } else {
            // Only names defined in the files it cites: a word in a decision is about its own files.
            let words = codeNames(in: rule.message + " " + rule.body)
            start = words.filter { !(defined[$0] ?? []).isDisjoint(with: cited) }
            if !start.isEmpty { verdict.restsOnFrom = "named in the decision" }
        }
        let known = start.filter { defined[$0] != nil }
        guard !known.isEmpty else {
            let languages = files.contains(where: Outline.understands)
            verdict.why = start.isEmpty
                ? (languages ? "the decision names no function, class or block in its files, and none was kept with it" : "its files are not code CAMR can outline")
                : "the parts it rests on (\(start.sorted().joined(separator: ", "))) are no longer in its files"
            return verdict
        }

        // What they call, in these files, followed until nothing new turns up: a decision about reconcile_statement rests
        // on ticket_for_line too, when reconcile_statement calls it.
        var reach = known
        for _ in 0..<8 {
            var more: Set<String> = []
            for file in files {
                let (before, after, _) = outline(file)
                for symbol in (before?.symbols ?? []) + (after?.symbols ?? []) where reach.contains(symbol.name) {
                    more.formUnion(symbol.calls.filter { defined[$0] != nil })
                }
            }
            if more.isSubset(of: reach) { break }
            reach.formUnion(more)
        }
        var restsOn: [String] = []
        for name in reach.sorted() { for file in defined[name, default: []].sorted() { restsOn.append("\(name) (\(short(file)))") } }
        verdict.restsOn = restsOn

        // What the change did to each changed file the decision rests on.
        var touched: [String] = [], elsewhere: [String] = [], unreadable: [String] = []
        for file in resting {
            let (before, after, failed) = outline(file)
            if failed || (before == nil && after == nil) {
                if Outline.understands(file) || cited.contains(file) { unreadable.append(short(file)) }
                continue
            }
            let one = Dictionary((before?.symbols ?? []).map { ($0.qualified, $0) }, uniquingKeysWith: { first, _ in first })
            let two = Dictionary((after?.symbols ?? []).map { ($0.qualified, $0) }, uniquingKeysWith: { first, _ in first })
            var mine: Set<String> = []  // names in this file the decision rests on
            for symbol in Array(one.values) + Array(two.values) where reach.contains(symbol.name) { mine.insert(symbol.qualified) }
            for name in Set(one.keys).union(two.keys).sorted() where one[name]?.hash != two[name]?.hash {
                let parts = name.split(separator: ".").map(String.init)
                // A change inside a method of a class it rests on, or to a part itself: touched. Only the innermost is named.
                let inner = Set(one.keys).union(two.keys).contains { $0 != name && $0.hasPrefix(name + ".") && one[$0]?.hash != two[$0]?.hash }
                if parts.contains(where: reach.contains) { if !inner || reach.contains(parts.last!) { touched.append("\(name) (\(short(file)))") } }
                else if !inner { elsewhere.append("\(name) (\(short(file)))") }
            }
            // Module level: a name whose binding changed, used by a part it rests on; or other top-level code changed in a
            // file holding such a part.
            // (A part whose own body changed is named already; this is for one that reads a name changed elsewhere.)
            let uses = (Array(one.values) + Array(two.values)).filter { reach.contains($0.name) && one[$0.qualified]?.hash == two[$0.qualified]?.hash }
                .reduce(into: Set<String>()) { $0.formUnion($1.uses) }
            let bound = (before?.bindings ?? [:]), now = (after?.bindings ?? [:])
            for name in Set(bound.keys).union(now.keys).sorted() where bound[name] != now[name] {
                if uses.contains(name) { touched.append("\(name), as \(short(file)) imports or sets it") }
                else if !mine.contains(where: { one[$0]?.uses.contains(name) == true || two[$0]?.uses.contains(name) == true }) { elsewhere.append("\(name) (\(short(file)))") }
            }
            if (before?.moduleCode ?? "") != (after?.moduleCode ?? "") {
                if !mine.isEmpty { touched.append("top-level code in \(short(file))") } else { elsewhere.append("top-level code in \(short(file))") }
            }
        }
        verdict.touched = touched
        verdict.elsewhere = elsewhere
        if !touched.isEmpty { verdict.kind = .affected }
        else if !unreadable.isEmpty {
            verdict.kind = .unprovable
            verdict.why = "CAMR could not outline \(unreadable.joined(separator: ", "))"
        } else { verdict.kind = .unaffected }
        return verdict
    }
}
