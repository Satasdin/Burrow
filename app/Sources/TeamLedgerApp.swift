import BurrowCore
import BurrowTools
import Foundation

/// The team's shared decisions on the app's Ledger page (D-109): each shown beside the vault's own, its branch shown as
/// the team, signed with the person who kept it and the program they used.
extension Engine {
    func addTeams(to state: inout LedgerState) {
        let teams = vault.teams()
        state.teams = teams.map(\.name)
        guard !teams.isEmpty else { return }
        var added: [LedgerCommit] = []
        for team in teams {
            let ledger = TeamLedger.ledger(team)
            let stale = ledger.staleness()
            for var commit in ledger.all() where commit.person != nil {
                let changed = stale(commit)
                if !changed.isEmpty { state.stale[commit.id] = changed }
                state.team[commit.id] = team.name
                commit.branch = team.name
                added.append(commit)
            }
            state.reverted.formUnion(ledger.reverted())
            state.retiredBy.merge(ledger.retirements()) { own, _ in own }
            state.inForce += TeamLedger.inForce(team).prefix(TeamLedger.limit(afterOwn: state.inForce.count)).map(\.id)
        }
        state.commits = (state.commits + added).sorted { $0.at == $1.at ? $0.id > $1.id : $0.at > $1.at }
    }

    /// Keeps a decision in a team's shared Ledger from the app, signed with the person's name and "the Burrow app".
    func shareWithTeam(_ name: String, _ kind: LedgerCommit.Kind, _ message: String, files: [String], session: String?) throws -> LedgerCommit {
        let team = try vault.team(named: name)
        return try TeamLedger.commit(vault: vault, team: team, kind: kind, message: message, files: files, author: "person", client: "Burrow app", session: session)
    }
}
