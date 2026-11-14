import BurrowCore
import BurrowTools
import Foundation

let ledgerUsage = """
  burrow commit <vault> "message" [--kind decision|fact|correction|plan|handoff] [--files a,b] [--branch B] [--author NAME]
  burrow log    <vault> [--branch B] [--file PATH] [--limit N]      what AIs understood, newest first
  burrow resume <vault> [branch]                                    where the work stopped, for any model to carry on
  burrow blame  <vault> <path>                                      which sessions explained or changed a file
  burrow diff   <vault> --since <commit>                            files that changed since a model last understood them
  burrow revert <vault> <commit> "what is right"                    marks a commit wrong; nothing is deleted
  burrow confirm <vault> <commit> ["note"]                         says a commit still holds after a file it cites changed
  burrow branch <vault> [name]                                      show the branches, or switch to one
  burrow check  <vault> [--staged] [--json]                         the decisions your change rests on, beside it; exit 2 until shown once
  burrow hook claude <vault> [--gate]                               for Claude Code's SessionStart, PreCompact, SessionEnd and Stop hooks
  burrow hook git <vault>                                           for git's post-commit hook, run inside the repository
  burrow hook install claude|git|git-gate <vault>                   prints the Claude Code settings, or writes .git/hooks/post-commit or pre-commit
"""

/// The Ledger's commands. Returns false when the command is not one of them.
func runLedgerCommand(_ arguments: [String]) async throws -> Bool {
    guard let command = arguments.first, ["commit", "log", "resume", "blame", "diff", "revert", "confirm", "branch", "hook", "check"].contains(command) else { return false }
    var words = Array(arguments.dropFirst())
    var values: [String: String] = [:]
    let takesValue: Set<String> = ["--kind", "--files", "--branch", "--author", "--file", "--limit", "--since", "--store"]
    var index = 0
    var positional: [String] = []
    while index < words.count {
        if takesValue.contains(words[index]), index + 1 < words.count { values[words[index]] = words[index + 1]; index += 2 } else { positional.append(words[index]); index += 1 }
    }
    // Switches without a value: only `check` and `hook` take any.
    let switches = Set(positional.filter { ["--staged", "--json", "--gate"].contains($0) })
    words = positional.filter { !switches.contains($0) }

    if command == "hook" {
        guard words.count >= 2 else { throw Failure(ledgerUsage) }
        if words[0] == "install" {
            guard words.count >= 3 else { throw Failure("hook install needs claude, git or git-gate, and the vault") }
            try installHook(words[1], vault: words[2], store: values["--store"])
        } else {
            let vault = try openVault(words[1], store: values["--store"])
            try runHook(words[0], vault: vault, gateOnly: switches.contains("--gate"))
        }
        return true
    }

    if command == "check" {
        guard let folder = words.first else { throw Failure("check needs the vault") }
        let vault = try openVault(folder, store: values["--store"])
        let staged = switches.contains("--staged")
        // Staged, from inside a linked repository (git's pre-commit hook), it keeps to that repository's next commit.
        let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let only = staged ? Hooks.place(for: here, vaultRoot: vault.root, linked: vault.linkedFolders()).flatMap { $0.prefix.isEmpty ? nil : $0.prefix } : nil
        let outcome = Gate.check(vault: vault, staged: staged, only: only, by: staged ? "burrow check --staged" : "burrow check")
        if switches.contains("--json") {
            print(try jsonLine(Gate.json(outcome)))
        } else {
            // Standard output is burrow_check's own words; what they mean for the gate goes to standard error.
            print(outcome.text)
            fflush(stdout)
            let count = outcome.report.rules.count
            if outcome.holds {
                logToStandardError("held: this change rests on \(count) decision\(count == 1 ? "" : "s") kept in the Ledger and had not been shown. It has been now, so the same change passes next time.")
            } else if outcome.fingerprint != nil {
                logToStandardError("this exact change was shown before, so it passes.")
            }
        }
        fflush(stdout)
        exit(outcome.exitCode)
    }

    guard let folder = words.first else { throw Failure(ledgerUsage) }
    let vault = try openVault(folder, store: values["--store"])
    let ledger = Ledger(vault: vault)
    let rest = Array(words.dropFirst())
    let author = values["--author"] ?? "person"

    switch command {
    case "commit":
        guard let message = rest.first else { throw Failure("commit needs a message") }
        let kindName = values["--kind"] ?? "fact"
        guard let kind = LedgerCommit.Kind(rawValue: kindName) else { throw Failure("unknown kind \(kindName)") }
        let files = (values["--files"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let made = try ledger.commit(kind, message, files: files, author: author, client: "terminal", branch: values["--branch"])
        print("[\(made.branch) \(made.id)] \(made.kind.rawValue): \(made.message)")
    case "log":
        let commits = ledger.log(branch: values["--branch"], file: values["--file"], limit: Int(values["--limit"] ?? "") ?? 30)
        if commits.isEmpty { print("The Ledger is empty here.") }
        let wrong = ledger.reverted(), stale = ledger.staleness()
        for commit in commits { print(describe(commit, stale: stale(commit), wrong: wrong)) }
    case "resume":
        print(ledger.resume(branch: rest.first))
    case "blame":
        guard let path = rest.first else { throw Failure("blame needs a vault path") }
        let commits = ledger.blame(path)
        if commits.isEmpty { print("No commit cites \(path) yet.") }
        let wrong = ledger.reverted(), stale = ledger.staleness()
        for commit in commits { print(describe(commit, stale: stale(commit), wrong: wrong)) }
    case "diff":
        guard let since = values["--since"] ?? rest.first else { throw Failure("diff needs --since <commit>") }
        let found = try ledger.diff(since: since)
        if found.changed.isEmpty && found.touched.isEmpty { print("Nothing cited since \(since) has changed.") }
        for path in found.changed { print("changed   \(path)") }
        for path in found.touched { print("touched   \(path)") }
    case "revert":
        guard rest.count >= 2 else { throw Failure("revert needs a commit and what is right instead") }
        let made = try ledger.revert(rest[0], why: rest[1], author: author, client: "terminal")
        print("[\(made.branch) \(made.id)] correction: \(made.message)")
    case "confirm":
        guard let id = rest.first else { throw Failure("confirm needs a commit id") }
        let made = try ledger.confirm(id, author: author, client: "terminal", note: rest.dropFirst().joined(separator: " "))
        print("[\(made.branch) \(made.id)] confirmation: \(made.message)")
    case "branch":
        if let name = rest.first {
            try ledger.switchTo(name)
            print("Now on \(ledger.current).")
        } else {
            let all = Set(ledger.branches()).union([ledger.current]).sorted()
            for name in all { print((name == ledger.current ? "* " : "  ") + name) }
        }
    default:
        return false
    }
    return true
}

private func describe(_ commit: LedgerCommit, stale: [String], wrong: Set<String>) -> String {
    var line = "\(commit.id)  \(commit.branch)  \(commit.kind.rawValue)  \(commit.byline)\n    \(commit.message)"
    if let because = commit.because { line += "\n    because: \(because)" }
    if wrong.contains(commit.id) { line += "\n    marked wrong" }
    if !stale.isEmpty { line += "\n    check again: \(stale.joined(separator: ", ")) changed since" }
    if !commit.cites.isEmpty { line += "\n    cites \(commit.cites.keys.sorted().prefix(5).joined(separator: ", "))" }
    return line
}

/// A hook must never get in the way: any failure is written to standard error and the hook still exits cleanly.
private func runHook(_ kind: String, vault: Vault, gateOnly: Bool = false) throws {
    let ledger = Ledger(vault: vault)
    switch kind {
    case "claude":
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let event = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
        // Stop: the gate first (D-93), over every linked folder, wherever Claude Code runs. When it holds the reply the
        // work goes on, so no handoff is written yet. With --gate (the Stop entry `hook install claude` prints) that is
        // all it does, so a handoff is not written at the end of every turn.
        if event["hook_event_name"] as? String == "Stop", let block = Gate.stop(event: event, vault: vault) {
            print(block)
            return
        }
        if gateOnly { return }
        let directory = URL(fileURLWithPath: event["cwd"] as? String ?? FileManager.default.currentDirectoryPath)
        guard let place = Hooks.place(for: directory, vaultRoot: vault.root, linked: vault.linkedFolders()) else {
            logToStandardError("hook: \(directory.path) is not in the vault or a linked folder; nothing kept")
            return
        }
        switch event["hook_event_name"] as? String ?? "" {
        case "SessionStart":
            print(Hooks.sessionStart(ledger: ledger, place: place))
        case let name where name == "PreCompact" || name == "SessionEnd" || name == "Stop":
            guard let path = event["transcript_path"] as? String, let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
            let transcript = Hooks.readTranscript(text)
            if let named = Hooks.nameConversation(SessionStore(vault: vault), transcript: transcript) { logToStandardError("named conversation \(named)") }
            let made = try Hooks.checkpoint(ledger: ledger, place: place, transcript: transcript,
                                            session: event["session_id"] as? String ?? "unknown", event: name)
            for commit in made { logToStandardError("kept \(commit.kind.rawValue) \(commit.id) on \(commit.branch)") }
        default:
            return
        }
    case "git":
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        guard let place = Hooks.place(for: directory, vaultRoot: vault.root, linked: vault.linkedFolders()) else { return }
        let sha = git(["rev-parse", "HEAD"], in: directory)
        let subject = git(["log", "-1", "--format=%s"], in: directory)
        // git names files from the top of the repository, which need not be the linked folder's root.
        let top = URL(fileURLWithPath: git(["rev-parse", "--show-toplevel"], in: directory))
        let files = git(["diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD"], in: directory)
            .split(separator: "\n").map { top.appendingPathComponent(String($0)).path }
        if let made = try Hooks.gitCommit(ledger: ledger, place: place, sha: sha, subject: subject, files: files) {
            logToStandardError("linked \(sha.prefix(10)) as \(made.id) on \(made.branch)")
        }
    default:
        throw Failure("hook takes claude or git")
    }
}

private func git(_ arguments: [String], in directory: URL) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

/// Claude Code's settings are the person's own file, so Burrow prints what to add rather than editing it.
/// The git hook is written only into the repository this is run in, and an existing hook is never replaced.
private func installHook(_ kind: String, vault folder: String, store: String? = nil) throws {
    func shellQuoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    let quoted = shellQuoted(URL(fileURLWithPath: folder).standardizedFileURL.resolvingSymlinksInPath().path)
    // The running executable itself, resolved to a real absolute path, so the hook never runs whatever `burrow` a PATH finds.
    guard let running = Bundle.main.executablePath, running.hasPrefix("/") else { throw Failure("could not tell where this burrow binary is") }
    let burrow = shellQuoted(URL(fileURLWithPath: running).resolvingSymlinksInPath().path)
    switch kind {
    case "claude":
        let command = "\(burrow) hook claude \(quoted)"
        let entry: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 10]]]
        // Stop runs the gate only (D-93): a handoff at the end of every turn would bury the Ledger.
        let stop: [String: Any] = ["hooks": [["type": "command", "command": command + " --gate", "timeout": 30]]]
        let settings: [String: Any] = ["hooks": ["SessionStart": [entry], "PreCompact": [entry], "SessionEnd": [entry], "Stop": [stop]]]
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        print("Add this to ~/.claude/settings.json (or the project's .claude/settings.json), merged with any hooks already there:\n")
        print(String(data: data, encoding: .utf8) ?? "")
    case "git":
        let top = git(["rev-parse", "--show-toplevel"], in: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        guard !top.isEmpty else { throw Failure("run this inside a git repository") }
        let hook = URL(fileURLWithPath: top).appendingPathComponent(".git/hooks/post-commit")
        guard !FileManager.default.fileExists(atPath: hook.path) else {
            throw Failure("\(hook.path) already exists. Add this line to it: \(burrow) hook git \(quoted) || true")
        }
        try "#!/bin/sh\n# Burrow: link each commit to the AI's Ledger. Never blocks a commit.\n\(burrow) hook git \(quoted) >/dev/null 2>&1 || true\n"
            .write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        print("Wrote \(hook.path).")
    case "git-gate":
        let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let top = git(["rev-parse", "--show-toplevel"], in: here)
        guard !top.isEmpty else { throw Failure("run this inside a git repository") }
        // Only a repository linked into this vault: elsewhere the check would see nothing, and the gate would be a pretence.
        let vault = try openVault(folder, store: store)
        guard Hooks.place(for: URL(fileURLWithPath: top), vaultRoot: vault.root, linked: vault.linkedFolders()).map({ !$0.prefix.isEmpty }) == true else {
            throw Failure("\(top) is not a folder linked into \(folder). Link it first: burrow link \(folder) \(top)")
        }
        // git's own answer, so a worktree or core.hooksPath is respected.
        let path = git(["rev-parse", "--git-path", "hooks/pre-commit"], in: URL(fileURLWithPath: top))
        let hook = URL(fileURLWithPath: path.hasPrefix("/") ? path : top + "/" + path)
        guard !FileManager.default.fileExists(atPath: hook.path) else {
            throw Failure("\(hook.path) already exists. Add this to it; exit status 2 means a decision was not shown yet: \(burrow) check \(quoted) --staged")
        }
        try FileManager.default.createDirectory(at: hook.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Gate.preCommitScript(burrow: burrow, vault: quoted).write(to: hook, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
        print("Wrote \(hook.path). A commit that touches a decision in the Ledger is refused once, with the decisions shown; the same change commits on the next try.")
    default:
        throw Failure("hook install takes claude, git or git-gate")
    }
}
