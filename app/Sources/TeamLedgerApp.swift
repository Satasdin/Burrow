import BurrowCore
import BurrowTools
import SwiftUI

/// The team's shared decisions on the app's Ledger page (D-109): each shown beside the vault's own, its branch shown as
/// the team, with the folder it was written in. A teammate's correction or supersede marks only that team's own
/// decisions, never the person's own or another team's (D-111).
extension Engine {
    func addTeams(to state: inout LedgerState) {
        let teams = vault.teams()
        state.teams = teams.map(\.name)
        state.pending = TeamPending.list(vault)
        guard !teams.isEmpty else { return }
        var added: [LedgerCommit] = []
        for team in teams {
            let commits = TeamLedger.commits(team)
            let stale = TeamLedger.staleness(team, commits)
            for var commit in commits {
                let changed = stale(commit)
                if !changed.isEmpty { state.stale[commit.id] = changed }
                state.team[commit.id] = team.name
                state.teamFolder[commit.id] = commit.branch
                commit.branch = team.name
                added.append(commit)
            }
            // Scoped to this team's own commits: a planted correction naming one of the person's ids does nothing.
            let retirements = TeamLedger.retirements(commits)
            state.reverted.formUnion(retirements.keys)
            state.retiredBy.merge(retirements) { own, _ in own }
            state.inForce += TeamLedger.inForce(team).prefix(TeamLedger.limit(afterOwn: state.inForce.count)).map(\.id)
        }
        state.commits = (state.commits + added).sorted { $0.at == $1.at ? $0.id > $1.id : $0.at > $1.at }
    }

    /// Keeps a decision in a team's shared Ledger from the app, signed with the person's name and "the Burrow app".
    func shareWithTeam(_ name: String, _ kind: LedgerCommit.Kind, _ message: String, files: [String], session: String?) throws -> LedgerCommit {
        let team = try vault.team(named: name)
        return try TeamLedger.commit(vault: vault, team: team, kind: kind, message: message, files: files, author: "person", client: "Burrow app", session: session)
    }

    /// The person approves a share a program asked for: it goes to the team (D-111).
    func approveShare(_ id: String) throws {
        guard let share = TeamPending.find(id, vault) else { return }
        try TeamPending.approve(share, vault: vault)
    }

    func discardShare(_ id: String) throws { try TeamPending.remove(id, vault) }
}

/// What programs asked to share with the team, waiting for the person: every word that would go, then Share or Drop (D-111).
struct PendingSharesCard: View {
    let workspace: Workspace

    var body: some View {
        let waiting = workspace.ledger.pending
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Waiting for you before it goes to the team", systemImage: "person.2.badge.gearshape")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(WatchPanel.amber)
                Text("A program asked to share \(waiting.count == 1 ? "this" : "these") with your team. Nothing reaches your teammates until you share it.")
                    .font(.system(size: 12)).foregroundStyle(Night.dim)
                ForEach(waiting) { share in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(share.kind.title) for \(share.team) · asked by \(LedgerCommit.programName(share.client ?? share.author))")
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Night.faint)
                        Text(share.shownMessage).font(.system(size: 14, weight: .semibold)).foregroundStyle(Night.note).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if !share.shownBody.isEmpty {
                            Text(share.shownBody).font(.system(size: 12.5)).foregroundStyle(Night.note.opacity(0.8)).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !share.files.isEmpty {
                            Text("Rests on " + share.files.joined(separator: ", ")).font(.system(size: 11.5)).foregroundStyle(Night.faint)
                        }
                        if let reverts = share.reverts {
                            // The decision it would retire, in full, so the person sees exactly what they agree to (D-112).
                            let old = workspace.ledger.commits.first { $0.id == reverts }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(share.kind == .correction ? "Marks this team decision wrong:" : "Replaces this team decision:")
                                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Night.stale)
                                Text(old.map { $0.message + ($0.body.isEmpty ? "" : "\n" + $0.body) } ?? "\(reverts), no longer in the team's Ledger")
                                    .font(.system(size: 12.5)).foregroundStyle(Night.note.opacity(0.8)).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        HStack {
                            Button("Share with \(share.team)") { Task { await workspace.approveShare(share.id) } }
                            Button("Drop") { Task { await workspace.discardShare(share.id) } }
                        }
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 8))
                }
            }
            .padding(16)
            .skyCard(tint: WatchPanel.amber)
        }
    }
}
