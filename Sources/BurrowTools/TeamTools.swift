import BurrowCore
import Foundation

/// burrow_commit with `share: team` (D-109): the commit goes to the team's shared Ledger, signed with the person and the
/// program that connected, instead of the vault's own.
extension VaultTools {
    /// Whether a burrow_commit's `share` asks for the team: any word but "no", "me" or "mine".
    static func sharesWithTeam(_ given: String?) -> String? {
        guard let word = given?.trimmingCharacters(in: .whitespacesAndNewlines), !word.isEmpty,
              !["no", "me", "mine", "own", "false", "private", "vault"].contains(word.lowercased()) else { return nil }
        return word
    }

    func shareWithTeam(_ share: String, kind: LedgerCommit.Kind, message: String, body: String, files: [String], author: String,
                       modelSaid: String?, supersedes: String?) -> ToolResult {
        let team: Team
        do { team = try vault.team(named: share) } catch let problem as NoteProblem {
            return .failure(problem.description + " Leave share out to keep it in this vault's own Ledger.")
        } catch { return .failure("\(error)") }
        do {
            var replaced: LedgerCommit?
            if let id = supersedes?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                guard let old = TeamLedger.ledger(team).find(id), [.decision, .correction, .fact].contains(old.kind) else {
                    return .failure("There is no team decision \(id) in \(team.name) to supersede. Give the id as the team's Ledger shows it, or leave supersedes out.")
                }
                replaced = old
            }
            let made = try TeamLedger.commit(vault: vault, team: team, kind: kind, message: message, body: body, files: files, author: author,
                                             client: connectionClient, reverts: replaced?.id, session: connection?.id, modelSaid: modelSaid)
            keptHere.insert(made.id)
            let retired = replaced.map { " It replaces \($0.id) (\($0.byline)), which is retired for the whole team; their file is kept as it was." } ?? ""
            return ToolResult(text: "Shared with \(team.name) as \(made.kind.rawValue) \(made.id), \(made.byline). Every teammate's programs are handed it once their copy of the team folder has it (a git pull, or the folder syncing).\(retired)",
                              summary: "shared \(made.kind.rawValue) \(made.id) with \(team.name)")
        } catch let problem as LedgerProblem {
            return .failure(problem.description)
        } catch {
            return .failure("Could not share that with \(team.name): \(error)")
        }
    }

    /// Brings Burrow's index of each team folder up to date before a call, at most as often as the vault's own.
    /// Returns a line for each team that could not be indexed.
    func freshenTeams() async -> [String] {
        guard !vault.teams().isEmpty else { return [] }
        return await vault.refreshTeams(embedder: hasVectors ? embedder : nil)
    }
}
