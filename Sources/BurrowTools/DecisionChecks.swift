import BurrowCore
import CryptoKit
import Foundation

/// A check a decision carries (D-107): a command that tests it (a test file, a test suite), or a pattern that no added
/// line in the files it rests on may match. When a change touches the decision, `burrow check` runs it, and a failure
/// means the change breaks the decision (exit 3), which seeing it does not clear.
public struct DecisionCheck: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case command, forbid }
    public var kind: Kind
    /// For a command: the program and its arguments, run as they are, with no shell.
    public var argv: [String]
    /// For a forbidden pattern: a regular expression no added line may match.
    public var pattern: String?
    /// Seconds a command may run before it is stopped and counted as not run.
    public var timeout: Int
    /// As it was written: `python3 -m pytest -q tests/test_rules.py`, or `forbid: \.phone\s*==`.
    public var written: String
    /// Who proposed it, or who confirmed it once confirmed: a program's name, or "you" for the person.
    public var by: String
    public var at: Date

    public static let defaultTimeout = 120

    /// `forbid: <regex>` is a forbidden pattern; anything else is a command, split into words the way a shell would split
    /// them (quotes and backslashes), with nothing expanded: no variables, no globs, no `~`, no pipes.
    public static func parse(_ spec: String, timeout: Int = defaultTimeout, by given: String, at: Date = Date()) throws -> DecisionCheck {
        // Who proposed it is a program's own name: shown, so kept to plain visible characters.
        var visible = String.UnicodeScalarView()
        visible.append(contentsOf: given.unicodeScalars.filter { $0 == " " || !unseen($0) })
        let by = String(String(visible).prefix(120))
        let written = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty else { throw LedgerProblem("A check needs a command to run, or forbid: and a pattern.") }
        guard !written.unicodeScalars.contains(where: { $0 == "\0" || $0 == "\n" || $0 == "\r" }) else {
            throw LedgerProblem("A check is one line: a command, or forbid: and a pattern.")
        }
        // What the person is shown must be exactly what runs, so nothing that can't be seen, or that changes how the
        // rest is shown, is allowed: control characters, bidi marks, zero-width and other format characters, and any
        // space other than a plain space or tab.
        guard !written.unicodeScalars.contains(where: unseen) else {
            throw LedgerProblem("A check can't hold control characters, invisible characters or unusual spaces: what you are shown has to be exactly what runs.")
        }
        guard (1...3_600).contains(timeout) else { throw LedgerProblem("A check's time limit is 1 to 3,600 seconds.") }
        if written.lowercased().hasPrefix("forbid:") {
            let pattern = String(written.dropFirst("forbid:".count)).trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty else { throw LedgerProblem("forbid: needs a pattern after it.") }
            guard (try? NSRegularExpression(pattern: pattern)) != nil else { throw LedgerProblem("forbid: \(pattern) is not a pattern Burrow can read (a regular expression).") }
            guard pattern.count <= 500 else { throw LedgerProblem("A forbidden pattern holds 500 characters.") }
            return DecisionCheck(kind: .forbid, argv: [], pattern: pattern, timeout: timeout, written: written, by: by, at: at)
        }
        let words = try split(written)
        guard !words.isEmpty else { throw LedgerProblem("A check needs a command to run.") }
        guard written.count <= 2_000 else { throw LedgerProblem("A check's command holds 2,000 characters.") }
        return DecisionCheck(kind: .command, argv: words, pattern: nil, timeout: timeout, written: written, by: by, at: at)
    }

    /// True for a character a person can't see, or that changes how what follows is shown (D-107).
    public static func unseen(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == " " { return false }
        if scalar == "\t" { return false }
        if Printable.isControl(scalar) { return true }
        switch scalar.properties.generalCategory {
        case .format, .control, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator, .spaceSeparator, .nonspacingMark, .enclosingMark: return true
        default: break
        }
        // Variation selectors, the Hangul fillers and the braille blank look like nothing.
        switch scalar.value {
        case 0xFE00...0xFE0F, 0xE0100...0xE01EF, 0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800: return true
        default: return scalar.properties.isWhitespace || scalar.properties.isDefaultIgnorableCodePoint
        }
    }

    /// This check if it is exactly what its own words say and nothing hides in it, else nil. A check read from a file
    /// (a vault someone shared can carry any JSON) is taken only when its words parse back to the same thing (D-107).
    public func validated() -> DecisionCheck? {
        guard let again = try? Self.parse(written, timeout: timeout, by: "check", at: at),
              again.kind == kind, again.argv == argv, again.pattern == pattern,
              !by.unicodeScalars.contains(where: Self.unseen), by.count <= 120 else { return nil }
        return self
    }

    /// Words as a shell splits them, with nothing expanded.
    static func split(_ text: String) throws -> [String] {
        var words: [String] = []
        var word = ""
        var started = false
        var quote: Character?
        var escaped = false
        for character in text {
            if escaped { word.append(character); escaped = false; started = true; continue }
            if let open = quote {
                if character == open { quote = nil }
                else if character == "\\", open == "\"" { escaped = true }
                else { word.append(character) }
                continue
            }
            switch character {
            case "\\": escaped = true; started = true
            case "'", "\"": quote = character; started = true
            case " ", "\t":
                if started { words.append(word); word = ""; started = false }
            default: word.append(character); started = true
            }
        }
        guard quote == nil, !escaped else { throw LedgerProblem("The check's command has a quote or backslash that is not closed.") }
        if started { words.append(word) }
        return words
    }

    /// What the person is shown, exactly what would run: each word quoted when it is not plain.
    public var shown: String {
        switch kind {
        case .command: return argv.map(Printable.shellWord).joined(separator: " ")
        case .forbid: return "forbid: " + Printable.clean(pattern ?? "")
        }
    }

    /// The same check whoever wrote it and whenever: what is compared when a confirmation is looked up.
    public var key: String {
        let text = [kind.rawValue, argv.joined(separator: "\u{1}"), pattern ?? "", String(timeout)].joined(separator: "\u{2}")
        return SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// The same check, standing as the person's.
    public func confirmed(by person: String = "you", at date: Date = Date()) -> DecisionCheck {
        var copy = self
        copy.by = person
        copy.at = date
        return copy
    }
}

/// What running a decision's check found.
public struct CheckRun: Sendable, Equatable {
    public enum Status: String, Sendable { case passed, failed, couldNotRun = "could_not_run" }
    public let status: Status
    /// The command's exit status, when it ran to the end.
    public let exitStatus: Int32?
    /// The end of what it printed (or the lines a pattern matched), cleaned of control characters.
    public let output: String
    public let seconds: Double
}

/// Where a decision's check lives (D-107). A check proposed by a program (over MCP, or `burrow` run without a terminal)
/// is kept in the vault as proposed, shown and never run. Only the person confirms one, in their own terminal with a
/// typed yes or in the app, and a confirmed check is kept in Burrow's own folder on this Mac, never in the vault: a vault
/// someone shares can carry a proposal, never a command that runs (the rule D-101 set for linked folders).
public enum DecisionChecks {
    struct Confirmed: Codable {
        /// Vault (real path) → decision id → the check.
        var vaults: [String: [String: DecisionCheck]] = [:]
        /// Vault → "fingerprint decision" → when the person let that exact change through despite a failed check.
        var overrides: [String: [String: Date]] = [:]
    }

    static func vaultKey(_ vault: Vault) -> String { vault.root.standardizedFileURL.resolvingSymlinksInPath().path }
    static func proposalsFile(_ vault: Vault) -> URL { vault.store.appendingPathComponent("decision-checks.json") }
    static func confirmedFile(_ vault: Vault) -> URL { vault.stateFolder.appendingPathComponent("decision-checks.json") }

    static func coder() -> (JSONEncoder, JSONDecoder) {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }

    static func loadConfirmed(_ vault: Vault) throws -> Confirmed {
        let url = confirmedFile(vault)
        guard FileManager.default.fileExists(atPath: url.path) else { return Confirmed() }
        do { return try coder().1.decode(Confirmed.self, from: Data(contentsOf: url)) }
        catch { throw LedgerProblem("Burrow's list of confirmed checks (\(url.path)) can't be read, so it was left as it is: \(error.localizedDescription)") }
    }

    static func saveConfirmed(_ saved: Confirmed, _ vault: Vault) throws {
        try FileManager.default.createDirectory(at: vault.stateFolder, withIntermediateDirectories: true)
        try coder().0.encode(saved).write(to: confirmedFile(vault), options: .atomic)
    }

    /// Checks proposed and not confirmed, by decision id. A file that can't be read proposes nothing.
    public static func proposed(_ vault: Vault) -> [String: DecisionCheck] {
        guard let data = try? Data(contentsOf: proposalsFile(vault)),
              let all = try? coder().1.decode([String: DecisionCheck].self, from: data) else { return [:] }
        return all.compactMapValues { $0.validated() }
    }

    /// Checks the person confirmed for this vault on this Mac: the only ones that run.
    public static func confirmed(_ vault: Vault) -> [String: DecisionCheck] {
        (((try? loadConfirmed(vault))?.vaults[vaultKey(vault)]) ?? [:]).compactMapValues { $0.validated() }
    }

    /// Keeps a check as proposed: shown beside the decision, never run. A confirmed check is left as it is.
    public static func propose(_ check: DecisionCheck, for decision: String, vault: Vault) throws {
        guard check.validated() != nil else { throw LedgerProblem("That check can't be kept: its words don't say exactly what it runs.") }
        var all = proposed(vault)
        all[decision] = check
        try FileManager.default.createDirectory(at: vault.store, withIntermediateDirectories: true)
        try coder().0.encode(all).write(to: proposalsFile(vault), options: .atomic)
    }

    /// The person's yes: the check runs from now on. Call only after the person was shown `check.shown` and said yes.
    public static func confirm(_ check: DecisionCheck, for decision: String, vault: Vault, by person: String = "you") throws {
        guard check.validated() != nil else { throw LedgerProblem("That check can't be confirmed: its words don't say exactly what it runs.") }
        var saved = try loadConfirmed(vault)
        saved.vaults[vaultKey(vault), default: [:]][decision] = check.confirmed(by: person)
        try saveConfirmed(saved, vault)
        var all = proposed(vault)
        if all.removeValue(forKey: decision) != nil {
            try coder().0.encode(all).write(to: proposalsFile(vault), options: .atomic)
        }
    }

    /// Takes a decision's check away, confirmed and proposed. Only the person: a check gone is a check that no longer holds.
    public static func clear(for decision: String, vault: Vault) throws {
        var saved = try loadConfirmed(vault)
        saved.vaults[vaultKey(vault)]?.removeValue(forKey: decision)
        try saveConfirmed(saved, vault)
        var all = proposed(vault)
        if all.removeValue(forKey: decision) != nil {
            try coder().0.encode(all).write(to: proposalsFile(vault), options: .atomic)
        }
    }

    /// The person lets this exact change through although the decision's check fails. Any further edit is checked again.
    public static func override(_ decision: String, fingerprint: String, vault: Vault) throws {
        var saved = try loadConfirmed(vault)
        saved.overrides[vaultKey(vault), default: [:]][fingerprint + " " + decision] = Date()
        try saveConfirmed(saved, vault)
    }

    public static func overridden(_ decision: String, fingerprint: String?, vault: Vault) -> Bool {
        guard let fingerprint else { return false }
        return ((try? loadConfirmed(vault))?.overrides[vaultKey(vault)]?[fingerprint + " " + decision]) != nil
    }

    // MARK: Running

    /// Runs a confirmed check. A command runs in `folder` with its arguments as they are (no shell), stdin closed, and is
    /// stopped after its time limit; a forbidden pattern is matched against `added`, the lines the change adds, by file.
    public static func run(_ check: DecisionCheck, in folder: URL, added: [String: [String]]) -> CheckRun {
        let started = Date()
        switch check.kind {
        case .forbid:
            guard let pattern = check.pattern, let expression = try? NSRegularExpression(pattern: pattern) else {
                return CheckRun(status: .couldNotRun, exitStatus: nil, output: "the pattern can't be read", seconds: 0)
            }
            var hits: [String] = []
            for (path, lines) in added.sorted(by: { $0.key < $1.key }) {
                for line in lines where expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    hits.append("\(Printable.clean(path)): +\(Printable.clean(String(line.prefix(300))))")
                }
            }
            let shown = hits.prefix(12).joined(separator: "\n") + (hits.count > 12 ? "\n… and \(hits.count - 12) more" : "")
            return CheckRun(status: hits.isEmpty ? .passed : .failed, exitStatus: nil,
                            output: hits.isEmpty ? "no added line matches" : shown, seconds: Date().timeIntervalSince(started))
        case .command:
            return execute(check.argv, in: folder, timeout: check.timeout)
        }
    }

    /// The program a command names: a path (relative to the folder) or a name looked up on PATH, never through a shell.
    static func program(_ name: String, in folder: URL) -> URL? {
        if name.contains("/") {
            let url = name.hasPrefix("/") ? URL(fileURLWithPath: name) : folder.appendingPathComponent(name)
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        for place in path.split(separator: ":") where !place.isEmpty {
            let url = URL(fileURLWithPath: String(place)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    static func execute(_ argv: [String], in folder: URL, timeout: Int) -> CheckRun {
        let started = Date()
        guard let name = argv.first, let executable = program(name, in: folder) else {
            return CheckRun(status: .couldNotRun, exitStatus: nil, output: "\(Printable.clean(argv.first ?? "")) was not found", seconds: 0)
        }
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("burrow-check-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: log.path, contents: nil), let handle = try? FileHandle(forWritingTo: log) else {
            return CheckRun(status: .couldNotRun, exitStatus: nil, output: "could not make a file for its output", seconds: 0)
        }
        defer { try? handle.close(); try? FileManager.default.removeItem(at: log) }
        let process = Process()
        process.executableURL = executable
        process.arguments = Array(argv.dropFirst())
        process.currentDirectoryURL = folder
        var environment = ProcessInfo.processInfo.environment
        // A test run leaves no __pycache__ in the person's code.
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        do { try process.run() } catch {
            return CheckRun(status: .couldNotRun, exitStatus: nil, output: "could not start: \(error.localizedDescription)", seconds: 0)
        }
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while process.isRunning, Date() < deadline { usleep(20_000) }
        var timedOut = false
        if process.isRunning {
            timedOut = true
            process.terminate()
            let grace = Date().addingTimeInterval(2)
            while process.isRunning, Date() < grace { usleep(20_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        let output = tail(text)
        let seconds = Date().timeIntervalSince(started)
        if timedOut {
            return CheckRun(status: .couldNotRun, exitStatus: nil, output: "stopped after \(timeout) seconds\n" + output, seconds: seconds)
        }
        let status = process.terminationStatus
        return CheckRun(status: status == 0 ? .passed : .failed, exitStatus: status, output: output, seconds: seconds)
    }

    /// The last 40 lines, at most 3,000 characters, each cleaned of control characters (D-104).
    static func tail(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n").map { Printable.clean($0) }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        var kept = Array(lines.suffix(40))
        var joined = kept.joined(separator: "\n")
        while joined.count > 3_000, kept.count > 1 { kept.removeFirst(); joined = kept.joined(separator: "\n") }
        if joined.count > 3_000 { joined = String(joined.suffix(3_000)) }
        return (lines.count > kept.count ? "[\(lines.count - kept.count) earlier lines left out]\n" : "") + joined
    }
}
