import CAMRCore
import Foundation

/// camr_commit with `share` (D-109, D-111): the commit is meant for the team's shared Ledger, but a program can't put
/// it there by itself. It is kept as a share waiting for the person, who approves it in their own terminal or the app.
extension VaultTools {
    /// The `share` a camr_commit gave, or nil when it gave none. Anything given is checked strictly by `team(strictly:)`.
    static func sharesWithTeam(_ given: String?) -> String? {
        guard let word = given?.trimmingCharacters(in: .whitespacesAndNewlines), !word.isEmpty else { return nil }
        return word
    }

    func shareWithTeam(_ share: String, kind: LedgerCommit.Kind, message: String, body: String, files: [String], author: String,
                       modelSaid: String?, supersedes: String?) -> ToolResult {
        let team: Team
        do { team = try vault.team(strictly: share) } catch let problem as NoteProblem {
            return .failure(problem.description + " Leave share out to keep it in this vault's own Ledger.")
        } catch { return .failure("\(error)") }
        var replaced: LedgerCommit?
        if let id = supersedes?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            guard let old = TeamLedger.find(id, in: team), [.decision, .correction, .fact].contains(old.kind) else {
                return .failure("There is no team decision \(id) in \(team.name) to supersede. Give the id as the team's Ledger shows it, or leave supersedes out.")
            }
            replaced = old
        }
        do {
            let waiting = try TeamPending.add(vault: vault, team: team, kind: kind, message: message, body: body, files: files.map { TeamLedger.teamPath($0, team: team) },
                                              author: author, client: connectionClient, session: connection?.id, modelSaid: modelSaid, reverts: replaced?.id)
            let who = vault.teamMember?.name ?? "the person"
            return ToolResult(text: "Not shared yet: waiting for \(who)'s approval before it goes to \(team.name). It is kept as \(waiting.id) on this Mac only, not in the team folder. "
                              + "Tell \(who) it is waiting: they approve it in their own terminal (camr team pending, then camr team approve \(waiting.id)) or in the CAMR app's Ledger. Nothing was kept in this vault's own Ledger either.",
                              summary: "share \(waiting.id) waiting for approval")
        } catch let problem as LedgerProblem {
            return .failure(problem.description)
        } catch {
            return .failure("Could not keep that share: \(error)")
        }
    }

    /// Brings CAMR's index of each team folder up to date before a call, at most as often as the vault's own.
    /// Returns a line for each team that could not be indexed.
    func freshenTeams() async -> [String] {
        guard !vault.teams().isEmpty else { return [] }
        return await vault.refreshTeams(embedder: hasVectors ? embedder : nil)
    }
}
