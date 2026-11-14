import BurrowCore
import Foundation

/// A decision a program asked to share with a team, waiting for the person (D-111). A program connected over MCP, or a
/// note in the vault talking to one, must not be able to publish into a folder every teammate reads: so `burrow_commit`
/// with `share` keeps it here, in Burrow's own folder on this Mac, never in the team folder, until the person approves it
/// in their own terminal (`burrow team approve`, typing yes) or in the app. Its words are kept with secrets taken out
/// (`Secrets.redacted`, D-105), and taken out again before it is shown and before it is published.
public struct PendingShare: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// The vault it was asked from, by its real path.
    public var vault: String
    public var team: String
    public var teamPath: String
    public var kind: LedgerCommit.Kind
    public var message: String
    public var body: String
    public var files: [String]
    public var author: String
    public var client: String?
    public var session: String?
    public var modelSaid: String?
    public var reverts: String?
    public var at: Date

    /// The words as they are shown and published: secrets out, every time.
    public var shownMessage: String { Secrets.redacted(message) }
    public var shownBody: String { Secrets.redacted(body) }
}

public enum TeamPending {
    static func file(_ vault: Vault) -> URL { vault.stateFolder.appendingPathComponent("team-pending.json") }
    static func key(_ vault: Vault) -> String { vault.root.standardizedFileURL.resolvingSymlinksInPath().path }

    static func loadAll(_ vault: Vault) throws -> [PendingShare] {
        let url = file(vault)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode([PendingShare].self, from: Data(contentsOf: url)) } catch {
            throw LedgerProblem("Burrow's list of shares waiting for approval (\(url.path)) can't be read, so it was left as it is: \(error.localizedDescription)")
        }
    }

    static func save(_ all: [PendingShare], _ vault: Vault) throws {
        try FileManager.default.createDirectory(at: vault.stateFolder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(all).write(to: file(vault), options: .atomic)
    }

    /// This vault's shares waiting for the person, oldest first.
    public static func list(_ vault: Vault) -> [PendingShare] {
        ((try? loadAll(vault)) ?? []).filter { $0.vault == key(vault) }.sorted { $0.at < $1.at }
    }

    /// Keeps a share asked for by a program, for the person to approve. Nothing is written to the team folder.
    @discardableResult
    public static func add(vault: Vault, team: Team, kind: LedgerCommit.Kind, message: String, body: String, files: [String], author: String,
                           client: String?, session: String?, modelSaid: String?, reverts: String?) throws -> PendingShare {
        guard [.decision, .fact, .correction, .plan].contains(kind) else { throw LedgerProblem("Only a decision, fact, plan or correction can be shared with the team.") }
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LedgerProblem("A commit needs a message.") }
        guard text.count <= 600 else { throw LedgerProblem("A commit message holds 600 characters; put the rest in its body.") }
        var all = try loadAll(vault)
        let share = PendingShare(id: "share-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased(),
                                 vault: key(vault), team: team.name, teamPath: team.path, kind: kind, message: Secrets.redacted(text),
                                 body: Secrets.redacted(String(body.prefix(8_000))), files: Array(files.prefix(24).map { String($0.prefix(512)) }),
                                 author: author, client: client, session: session, modelSaid: modelSaid.map { String($0.prefix(120)) },
                                 reverts: reverts, at: Date())
        all.append(share)
        try save(all, vault)
        return share
    }

    /// The share by id, among this vault's.
    public static func find(_ id: String, _ vault: Vault) -> PendingShare? {
        let mine = list(vault)
        return mine.first { $0.id == id } ?? mine.first { $0.id.hasPrefix(id) && id.count >= 8 }
    }

    /// Publishes an approved share to its team's Ledger, signed with the person and the program that asked, and takes it
    /// off the list. Only the person's own steps call this: `burrow team approve` after they typed yes, or the app.
    @discardableResult
    public static func approve(_ share: PendingShare, vault: Vault) throws -> LedgerCommit {
        guard let team = vault.teams().first(where: { $0.name == share.team && $0.path == share.teamPath }) else {
            throw LedgerProblem("This vault no longer reads the team \(share.team), so the share was left waiting. Discard it with burrow team discard.")
        }
        let made = try TeamLedger.commit(vault: vault, team: team, kind: share.kind, message: share.shownMessage, body: share.shownBody, files: share.files,
                                         author: share.author, client: share.client, reverts: share.reverts, session: share.session, modelSaid: share.modelSaid)
        try remove(share.id, vault)
        return made
    }

    /// Takes a share off the list without publishing it.
    public static func remove(_ id: String, _ vault: Vault) throws {
        let all = try loadAll(vault)
        try save(all.filter { !($0.id == id && $0.vault == key(vault)) }, vault)
    }

    /// The share as the person reads it before saying yes: everything that would go to the team, secrets out.
    public static func shown(_ share: PendingShare) -> [String] {
        var lines = ["\(share.id): a \(share.kind.rawValue) for \(share.team), asked by \(LedgerCommit.programName(share.client ?? share.author))"
                     + (share.modelSaid.map { " (the model called itself \"\($0)\")" } ?? "") + ", \(Ledger.when(share.at))",
                     "  " + share.shownMessage]
        for line in share.shownBody.components(separatedBy: "\n") where !line.isEmpty { lines.append("  " + line) }
        if !share.files.isEmpty { lines.append("  rests on: " + share.files.joined(separator: ", ")) }
        if let reverts = share.reverts {
            let team = Team(name: share.team, path: share.teamPath)
            if let old = TeamLedger.find(reverts, in: team) {
                lines.append(share.kind == .correction ? "  and it marks this team decision wrong:" : "  and it replaces this team decision:")
                lines += commitLines(old, team: team)
            } else {
                lines.append("  and it replaces team decision \(reverts), which is no longer in the team's Ledger")
            }
        }
        return lines.map(Printable.clean)
    }

    /// A team commit in full, as the person is shown it before agreeing to replace it or mark it wrong (D-112).
    public static func commitLines(_ commit: LedgerCommit, team: Team) -> [String] {
        var lines = ["    \(team.name) \(commit.id) [\(commit.kind.rawValue)], \(commit.byline), \(Ledger.when(commit.at))", "    " + commit.message]
        for line in commit.body.components(separatedBy: "\n") where !line.isEmpty { lines.append("    " + line) }
        if !commit.cites.isEmpty { lines.append("    rests on: " + commit.cites.keys.sorted().joined(separator: ", ")) }
        return lines.map(Printable.clean)
    }
}
