import CAMRCore
import CAMRTools
import Foundation

let teamUsage = """
Sharing with a team, or with your own other Macs (D-109):
  camr team join  <vault> <team-folder> [--name N] [--as "Your Name"]   join a folder your team shares (a git clone or a synced
                                                                  folder), in your own terminal, typing yes
  camr team list  <vault>                                       the teams this vault reads, and the name you sign with
  camr team log   <vault> [--limit N]                           what the team shared, newest first, with who kept each
  camr team revert <vault> <commit> "what is right"             marks a team decision wrong; their file is never touched
  camr team leave <vault> <name>                                stop reading a team; nothing in its folder is touched
  camr team pending <vault>                                     what your programs asked to share, waiting for you (D-111)
  camr team approve <vault> <share> | --all                     share them, in your own terminal, typing yes
  camr team discard <vault> <share> | --all                     drop them; nothing reaches the team
  camr commit <vault> "message" --team[=Name] [--kind K] [--because WHY] [--rejected WHAT] [--files a,b] [--supersedes <commit>]
                                                                  keep it in the team's shared Ledger instead of your own; typed in
                                                                  your own terminal it is shared at once, run by a program it waits
"""

/// `team …`, and `commit … --team`. Returns false for any other command.
func runTeamCommand(_ arguments: [String]) async throws -> Bool {
    guard let command = arguments.first else { return false }
    if command == "commit", arguments.contains(where: { $0 == "--team" || $0.hasPrefix("--team=") }) {
        try teamCommit(Array(arguments.dropFirst()))
        return true
    }
    guard command == "team" else { return false }
    let words = Array(arguments.dropFirst())
    guard let action = words.first else { throw Failure(teamUsage) }
    let (positional, values) = try teamOptions(Array(words.dropFirst()), takingValue: ["--name", "--as", "--limit"])
    switch action {
    case "join": try await join(positional, values)
    case "list": try list(positional)
    case "log": try log(positional, values)
    case "leave": try leave(positional)
    case "revert": try revert(positional)
    case "pending": try pending(positional)
    case "approve": try approve(positional, all: values["--all"] != nil)
    case "discard": try discard(positional, all: values["--all"] != nil)
    default: throw Failure(teamUsage)
    }
    return true
}

private func teamOptions(_ words: [String], takingValue: Set<String>) throws -> (positional: [String], values: [String: String]) {
    var positional: [String] = []
    var values: [String: String] = [:]
    var index = 0
    while index < words.count {
        let word = words[index]
        if takingValue.contains(word) {
            guard index + 1 < words.count else { throw Failure("\(word) needs a value") }
            values[word] = words[index + 1]
            index += 2
        } else if word.hasPrefix("--"), let equals = word.firstIndex(of: "=") {
            values[String(word[..<equals])] = String(word[word.index(after: equals)...])
            index += 1
        } else {
            if word.hasPrefix("--") { values[word] = "" } else { positional.append(word) }
            index += 1
        }
    }
    return (positional, values)
}

private func teamVault(_ path: String?, _ what: String) throws -> Vault {
    guard let path else { throw Failure("\(what) needs your vault folder. Run camr help for every command.") }
    return try openVault(path, store: nil)
}

/// Joining reads a folder on this Mac into what every connected program can search, and publishes what the person
/// shares into it, so only the person does it, in their own terminal, as with linking a folder (D-104).
private func join(_ positional: [String], _ values: [String: String]) async throws {
    guard positional.count >= 2 else { throw Failure("team join needs your vault and the team folder: camr team join <vault> <team-folder> [--name N] [--as \"Your Name\"]") }
    guard inPersonsTerminal() else {
        throw Failure("only you can join a team: run this in your own terminal. It can't be done through a pipe or by a program you've connected to CAMR.")
    }
    let vault = try teamVault(positional[0], "team join")
    let folder = URL(fileURLWithPath: positional[1]).standardizedFileURL
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else { throw Failure("\(folder.path) is not a folder") }
    let real = folder.resolvingSymlinksInPath().path
    let signing = values["--as"].map(Vault.cleanPersonName) ?? vault.teamMember?.name ?? Vault.defaultPersonName(for: folder)
    try askThePerson([
        "Join the team folder \(Printable.clean(real)) from \(Printable.clean(vault.root.path))?",
        "  Its notes become searchable by every program connected to this vault, labelled with the team's name, and its",
        "  shared decisions are handed to them, as your teammates' notes. Its own linked folders, bridges and checks are never followed or run.",
        "  Decisions you share go into \(Printable.clean(real))/.camr/ledger/, signed \"\(Printable.clean(signing))\" with the program you use.",
    ])
    let team: Team
    do {
        team = try vault.joinTeam(folder, name: values["--name"], person: values["--as"] ?? (vault.teamMember == nil ? signing : nil))
    } catch let problem as NoteProblem {
        throw Failure(problem.description)
    }
    KnownVaults.remember(vault)
    let ollama = Ollama()
    var how = "by words and meaning"
    var problems: [String]
    if (try? vault.stats().vectors) ?? 0 > 0 {
        problems = await vault.refreshTeams(embedder: ollama.embedder())
        if !problems.isEmpty {
            problems = await vault.refreshTeams(embedder: nil)
            how = "by words only (Ollama could not be reached)"
        }
    } else {
        problems = await vault.refreshTeams(embedder: nil)
        how = "by words only, as this vault is"
    }
    for problem in problems { logToStandardError(problem) }
    let files = vault.bridgedShelves().first { $0.bridge.name == team.name }?.files.count ?? 0
    let shared = TeamLedger.all(vault: vault).filter { $0.team.name == team.name }.count
    print("joined \(team.path) as \(team.name): \(files) files searchable \(how), \(shared) shared commit\(shared == 1 ? "" : "s") in its Ledger.")
    print("You sign as \(vault.teamMember?.name ?? signing); change it with --as. Paths from it read like \"\(team.name)\(Bridge.separator)notes/plan.md\".")
    print("Share a decision with: camr commit \(vault.root.path) \"…\" --kind decision --because \"…\" --team, or camr_commit with share: team.")
}

private func list(_ positional: [String]) throws {
    let vault = try teamVault(positional.first, "team list")
    let teams = vault.teams()
    guard !teams.isEmpty else {
        print("\(vault.root.path) has joined no team. Join one in your own terminal: camr team join \(vault.root.path) <team-folder>")
        return
    }
    print("You sign team decisions as \(vault.teamMember?.name ?? "(no name yet)")\(vault.teamMember.map { ", from this Mac's folder \($0.folder)" } ?? "").")
    let all = TeamLedger.all(vault: vault)
    for team in teams {
        let shelf = vault.bridgedShelves().first { $0.bridge.name == team.name }
        let state = shelf?.problem ?? "\(shelf?.files.count ?? 0) files"
        let commits = all.filter { $0.team.name == team.name }
        let people = Set(commits.compactMap(\.commit.person)).sorted()
        print("\(team.name)   \(team.path)   \(state), \(commits.count) shared commit\(commits.count == 1 ? "" : "s")\(people.isEmpty ? "" : " by " + people.joined(separator: ", "))")
    }
}

private func log(_ positional: [String], _ values: [String: String]) throws {
    let vault = try teamVault(positional.first, "team log")
    let limit = Int(values["--limit"] ?? "") ?? 30
    let all = TeamLedger.all(vault: vault, limit: limit)
    guard !all.isEmpty else {
        print(vault.teams().isEmpty ? "This vault has joined no team." : "Nothing has been shared with the team yet.")
        return
    }
    var retired: [String: [String: LedgerCommit]] = [:]
    for team in vault.teams() { retired[team.name] = TeamLedger.retirements(TeamLedger.commits(team)) }
    for team in vault.teams() {
        for line in TeamLedger.scan(team).skipped { print(Printable.clean("\(team.name): not read: \(line)")) }
    }
    // Everything in it was written on other Macs: printed clean of anything that could rewrite the terminal (D-104).
    for (team, commit) in all {
        var line = "\(team.name) \(commit.id) [\(commit.kind.rawValue)] \(commit.stated(within: 400)) (\(commit.byline), \(Ledger.when(commit.at)))"
        if let by = retired[team.name]?[commit.id] { line += " " + Ledger.retiredNote(by) }
        if TeamLedger.carriesCheck(commit, team: team) { line += " [carries a check: proposed, not run]" }
        if TeamLedger.isSteering(commit) { line += " [written to steer an AI: never handed to a program]" }
        print(Printable.clean(line))
    }
}

private func leave(_ positional: [String]) throws {
    guard positional.count >= 2 else { throw Failure("team leave needs your vault and the team's name: camr team leave <vault> <name>") }
    let vault = try teamVault(positional[0], "team leave")
    do {
        let gone = try vault.leaveTeam(positional[1])
        print("left \(gone.name) (\(gone.path)). Nothing in the team folder was changed; CAMR's own index of it on this Mac was removed.")
    } catch let problem as NoteProblem {
        throw Failure(problem.description)
    }
}

private func revert(_ positional: [String]) throws {
    guard positional.count >= 3 else { throw Failure("team revert needs your vault, the commit and what is right: camr team revert <vault> <commit> \"what is right\"") }
    let vault = try teamVault(positional[0], "team revert")
    guard let team = TeamLedger.holding(positional[1], vault: vault), let old = TeamLedger.find(positional[1], in: team) else {
        throw Failure("no team this vault reads has a commit \(positional[1])")
    }
    let why = positional[2].trimmingCharacters(in: .whitespacesAndNewlines)
    guard !why.isEmpty else { throw Failure("say what is right instead") }
    let message = "Wrong: \"\(String(old.message.prefix(160)))\". \(why)"
    // Run through a pipe, as a connected program runs it, the correction waits for the person like a share (D-112).
    guard inPersonsTerminal() else {
        do {
            let waiting = try TeamPending.add(vault: vault, team: team, kind: .correction, message: message, body: "", files: Array(old.cites.keys),
                                              author: "person", client: "terminal", session: nil, modelSaid: nil, reverts: old.id)
            print("Not marked wrong yet: waiting for \(vault.teamMember?.name ?? "the person")'s approval before it goes to \(team.name), as \(waiting.id).")
            print("    Run from a pipe or a program, a team correction waits. Approve it in your own terminal: camr team approve \(vault.root.path) \(waiting.id)")
        } catch let problem as LedgerProblem {
            throw Failure(problem.description)
        }
        return
    }
    try askThePerson(["Mark this team decision wrong for everyone in \(team.name)?"] + TeamPending.commitLines(old, team: team)
                     + ["Your correction, signed \"\(Printable.clean(vault.teamMember?.name ?? "you"))\" in the terminal:", "  " + Printable.clean(Secrets.redacted(message))])
    do {
        let made = try TeamLedger.revert(vault: vault, team: team, id: old.id, why: why, author: "person", client: "terminal")
        print("[\(team.name) \(made.id)] correction: \(made.message)")
        print("    \(positional[1]) now shows as wrong for the whole team; the file it is in was not touched.")
    } catch let problem as LedgerProblem {
        throw Failure(problem.description)
    }
}

/// `camr commit <vault> "message" --team[=Name] …`: the same words as `camr commit`, kept in the team's Ledger.
private func teamCommit(_ words: [String]) throws {
    let (positional, values) = try teamOptions(words, takingValue: ["--kind", "--files", "--author", "--because", "--rejected", "--supersedes", "--store"])
    guard positional.count >= 2 else { throw Failure("commit needs your vault and a message: camr commit <vault> \"message\" --team") }
    let vault = try openVault(positional[0], store: values["--store"])
    let team: Team
    do { team = try vault.team(named: values["--team"]) } catch let problem as NoteProblem { throw Failure(problem.description) }
    let kindName = values["--kind"] ?? "fact"
    guard let kind = LedgerCommit.Kind(rawValue: kindName) else { throw Failure("unknown kind \(kindName)") }
    let files = (values["--files"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    func oneLine(_ key: String) -> String {
        (values[key] ?? "").components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
    let because = oneLine("--because"), rejected = oneLine("--rejected")
    let body = [rejected.isEmpty ? nil : "Rejected: " + String(rejected.prefix(600)), because.isEmpty ? nil : "Because: " + String(because.prefix(600))].compactMap { $0 }
    var replaced: LedgerCommit?
    if let id = values["--supersedes"] {
        guard let old = TeamLedger.find(id, in: team) else { throw Failure("there is no team commit \(id) to supersede") }
        replaced = old
    }
    // Typed by the person in their own terminal, it is shared at once. Run through a pipe, as a connected program runs it,
    // it waits for the person like a program's camr_commit with share (D-111).
    guard inPersonsTerminal() else {
        do {
            let waiting = try TeamPending.add(vault: vault, team: team, kind: kind, message: positional[1], body: body.joined(separator: "\n"), files: files,
                                              author: values["--author"] ?? "person", client: "terminal", session: nil, modelSaid: nil, reverts: replaced?.id)
            print("Not shared yet: waiting for \(vault.teamMember?.name ?? "the person")'s approval before it goes to \(team.name), as \(waiting.id).")
            print("    Run from a pipe or a program, a team share waits. Approve it in your own terminal: camr team approve \(vault.root.path) \(waiting.id)")
        } catch let problem as LedgerProblem {
            throw Failure(problem.description)
        }
        return
    }
    var shown = ["Share this \(kind.rawValue) with \(team.name), signed \"\(Printable.clean(vault.teamMember?.name ?? "you"))\" in the terminal? Every teammate's programs will be handed it:",
                 "  " + Printable.clean(Secrets.redacted(positional[1]))]
    for line in body where !line.isEmpty { shown.append("  " + Printable.clean(Secrets.redacted(line))) }
    if !files.isEmpty { shown.append("  rests on: " + Printable.clean(files.joined(separator: ", "))) }
    if let replaced { shown += ["  and it replaces:"] + TeamPending.commitLines(replaced, team: team) }
    try askThePerson(shown)
    do {
        let made = try TeamLedger.commit(vault: vault, team: team, kind: kind, message: positional[1], body: body.joined(separator: "\n"), files: files,
                                         author: values["--author"] ?? "person", client: "terminal", reverts: replaced?.id)
        print("[\(team.name) \(made.id)] \(made.kind.rawValue): \(made.message)")
        print("    \(made.byline); in \(team.ledgerFolder.appendingPathComponent(made.branch).path)")
        if let replaced { print("    replaces \(replaced.id) (\(replaced.byline)), now retired for the whole team") }
        print("    Your teammates' programs get it once the team folder carries it: commit and push it, or let the folder sync.")
    } catch let problem as LedgerProblem {
        throw Failure(problem.description)
    }
}

// MARK: Shares waiting for the person (D-111)

private func pending(_ positional: [String]) throws {
    let vault = try teamVault(positional.first, "team pending")
    let waiting = TeamPending.list(vault)
    guard !waiting.isEmpty else {
        print("Nothing is waiting to be shared from \(vault.root.path).")
        return
    }
    print("\(waiting.count) share\(waiting.count == 1 ? "" : "s") waiting for you. Each goes to the team only when you approve it here, in your own terminal, or in the app:")
    for share in waiting { print(""); for line in TeamPending.shown(share) { print(line) } }
    print("\nApprove with: camr team approve \(vault.root.path) <share> (or --all); drop with: camr team discard \(vault.root.path) <share>")
}

private func chosenShares(_ positional: [String], all: Bool, _ what: String) throws -> (Vault, [PendingShare]) {
    let vault = try teamVault(positional.first, "team \(what)")
    let waiting = TeamPending.list(vault)
    if all { return (vault, waiting) }
    guard positional.count >= 2 else { throw Failure("team \(what) needs your vault and a share, or --all: camr team \(what) <vault> <share>") }
    guard let share = TeamPending.find(positional[1], vault) else { throw Failure("there is no share \(positional[1]) waiting; camr team pending lists them") }
    return (vault, [share])
}

/// Publishing what a program asked to share is the person's step only: in their own terminal, after reading every word
/// that would go to the team and typing yes (D-104, D-111).
private func approve(_ positional: [String], all: Bool) throws {
    guard inPersonsTerminal() else {
        throw Failure("only you can approve a team share: approve it in the CAMR app, or run this in your own terminal. It can't be done through a pipe or by a program you've connected to CAMR.")
    }
    let (vault, shares) = try chosenShares(positional, all: all, "approve")
    guard !shares.isEmpty else { print("Nothing is waiting to be shared."); return }
    var lines = ["Share \(shares.count == 1 ? "this" : "these \(shares.count)") with your team, signed \"\(Printable.clean(vault.teamMember?.name ?? "you"))\"? Every teammate's programs will be handed \(shares.count == 1 ? "it" : "them"):"]
    for share in shares { lines.append(""); lines += TeamPending.shown(share) }
    try askThePerson(lines)
    for share in shares {
        do {
            let made = try TeamPending.approve(share, vault: vault)
            print("shared \(share.id) with \(share.team) as \(made.id), \(made.byline)")
        } catch let problem as LedgerProblem {
            logToStandardError("\(share.id) was not shared: \(problem.description)")
        }
    }
    print("Your teammates' programs get it once the team folder carries it: commit and push it, or let the folder sync.")
}

private func discard(_ positional: [String], all: Bool) throws {
    let (vault, shares) = try chosenShares(positional, all: all, "discard")
    for share in shares {
        do { try TeamPending.remove(share.id, vault) } catch let problem as LedgerProblem { throw Failure(problem.description) }
        print("dropped \(share.id); nothing reached \(share.team).")
    }
    if shares.isEmpty { print("Nothing is waiting to be shared.") }
}
