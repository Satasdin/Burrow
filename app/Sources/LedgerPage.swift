import AppKit
import BurrowCore
import BurrowTools
import SwiftUI

/// What the Ledger holds, read once per refresh: every commit, which were marked wrong, and which rest on changed files.
struct LedgerState: Sendable {
    var commits: [LedgerCommit] = []
    var reverted: Set<String> = []
    /// Retired commit id → the commit that retired it: a correction, or a newer decision that replaced it (D-94).
    var retiredBy: [String: LedgerCommit] = [:]
    /// Decision id → the decisions in force it may contradict, until the person says which holds (D-94).
    var unresolved: [String: [String]] = [:]
    /// Commit id → the cited files that changed since it was written.
    var stale: [String: [String]] = [:]
    var current = Ledger.defaultBranch
    /// The decisions and corrections handed to every program when it connects, by id (D-76).
    var inForce: [String] = []
    /// What burrow_check would show right now (D-79).
    var check: CheckReport?
    /// Text in the vault written to steer AI assistants (D-80).
    var flagged: [FlaggedLine] = []
    /// Team decisions (D-109): commit id → the team whose shared Ledger holds it. Their branch is shown as the team.
    var team: [String: String] = [:]
    /// The teams this vault reads, for "Share with the team" where a decision is kept.
    var teams: [String] = []
    /// Team decisions: commit id → the person-and-Mac folder its file is in, which is what vouches for it (D-111).
    var teamFolder: [String: String] = [:]
    /// Shares programs asked for, waiting for the person (D-111).
    var pending: [PendingShare] = []

    var branches: [String] { Array(Set(commits.map(\.branch))).sorted() }
    func commits(on branch: String?) -> [LedgerCommit] { branch.map { name in commits.filter { $0.branch == name } } ?? commits }
    func citing(_ path: String) -> [LedgerCommit] { commits.filter { $0.cites.keys.contains(path) } }
}

struct FlaggedLine: Sendable, Hashable {
    var path: String
    var line: Int
    var text: String
}

extension LedgerCommit.Kind {
    var title: String {
        switch self {
        case .decision: return "Decision"
        case .fact: return "Fact"
        case .correction: return "Correction"
        case .plan: return "Plan"
        case .handoff: return "Handoff"
        case .code: return "Code commit"
        case .confirmation: return "Still right"
        }
    }

    var symbol: String {
        switch self {
        case .decision: return "checkmark.seal"
        case .fact: return "text.book.closed"
        case .correction: return "arrow.uturn.backward.circle"
        case .plan: return "list.bullet.clipboard"
        case .handoff: return "arrow.right.circle"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .confirmation: return "checkmark.circle"
        }
    }

    /// Each kind keeps its own colour whatever the theme: decisions mint, facts white, plans violet,
    /// handoffs cyan (as conversations are everywhere else), corrections red. Code commits are the plain case.
    var colour: Color {
        switch self {
        case .decision: return Color(red: 0.42, green: 0.92, blue: 0.66)
        case .fact: return Night.note
        case .plan: return Color(red: 0.74, green: 0.63, blue: 1.00)
        case .handoff: return Night.conversation
        case .correction: return Night.stale
        case .code: return Night.dim
        case .confirmation: return Color(red: 0.42, green: 0.92, blue: 0.66).opacity(0.75)
        }
    }
}

/// The Ledger: what AIs understood, decided, were corrected on and where they stopped, as a timeline per branch.
struct LedgerPage: View {
    let workspace: Workspace
    let branch: String?
    @State private var resume: String?
    @State private var copied = false
    @AppStorage(SkyTheme.key) private var themeName = SkyTheme.nebula.rawValue
    private var theme: SkyTheme { SkyTheme(rawValue: themeName) ?? .nebula }

    private var commits: [LedgerCommit] { workspace.ledger.commits(on: branch) }
    private var days: [(day: Date, commits: [LedgerCommit])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: commits) { calendar.startOfDay(for: $0.at) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Ledger").font(.system(size: 30, weight: .bold)).tracking(-0.6)
                        .foregroundStyle(LinearGradient(colors: [.white, theme.accent], startPoint: .leading, endPoint: .trailing))
                    Text("\(commits.count.counted("commit"))\(branch.map { " on \($0)" } ?? " on \(workspace.ledger.branches.count.counted("branch", "branches"))")")
                        .foregroundStyle(Night.dim).monospacedDigit()
                    Spacer()
                    Button { Task { await showResume() } } label: { Label("Resume", systemImage: "arrow.right.circle") }
                        .help("What a model that lost its memory would be handed for this branch")
                }
                branchChips
                WatchPanel(workspace: workspace)
                PendingSharesCard(workspace: workspace)
                if let resume { resumeCard(resume) }
                if commits.isEmpty {
                    ContentUnavailableView("Nothing kept yet", systemImage: "books.vertical",
                                           description: Text("Programs keep decisions, plans and where they stopped here, through burrow_commit and the Claude Code and git hooks. Run burrow hook install claude <vault> to start."))
                        .foregroundStyle(Night.dim).frame(maxWidth: .infinity).padding(.top, 40)
                }
                ForEach(days, id: \.day) { day in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(day.day.dayTitle).font(.system(size: 15, weight: .semibold)).padding(.bottom, 12)
                        ForEach(Array(day.commits.enumerated()), id: \.element.id) { index, commit in
                            CommitRow(workspace: workspace, commit: commit, last: index == day.commits.count - 1)
                                .arrive(index)
                        }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 22).frame(maxWidth: 920, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(NightSky())
        .environment(\.colorScheme, .dark)
        .task(id: branch) { resume = nil }
    }

    private var branchChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: branch == nil) { workspace.go(.ledger(nil)) }
                ForEach(workspace.ledger.branches, id: \.self) { name in
                    chip(name + (name == workspace.ledger.current ? " ·" : ""), selected: branch == name) { workspace.go(.ledger(name)) }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 5)
                .foregroundStyle(selected ? .black : Night.note)
                .background(selected ? AnyShapeStyle(theme.accent) : AnyShapeStyle(Color.white.opacity(0.06)), in: .capsule)
                .overlay { Capsule().strokeBorder(selected ? .clear : Night.line) }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selected)
        }
        .buttonStyle(.plain)
    }

    private func resumeCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("What the next model is handed", systemImage: "arrow.right.circle").font(.system(size: 13, weight: .semibold)).foregroundStyle(Night.conversation)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                .controlSize(.small)
                Button { resume = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Night.dim)
            }
            Text(text).font(.system(size: 12, design: .monospaced)).foregroundStyle(Night.note.opacity(0.85)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .skyCard(tint: Night.conversation)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func showResume() async {
        copied = false
        let text = await workspace.resumeText(branch)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { resume = text }
    }
}

/// One commit on the timeline: its kind, what it says, who wrote it, and the files it rests on.
struct CommitRow: View {
    let workspace: Workspace
    let commit: LedgerCommit
    let last: Bool
    @State private var correcting = false
    @State private var right = ""

    private var wrong: Bool { workspace.ledger.reverted.contains(commit.id) }
    private var stale: [String] { workspace.ledger.stale[commit.id] ?? [] }
    private var dot: Color { wrong || !stale.isEmpty ? Night.stale : commit.kind.colour }

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A decision's body holds "Rejected: …" and "Because: …" lines; they are shown as their own blocks.
    private var reasons: (rest: String, rejected: String?, because: String?) {
        var rest: [String] = [], rejected: String?, because: String?
        for line in commit.body.components(separatedBy: "\n") {
            if line.hasPrefix("Rejected:") { rejected = line.dropFirst(9).trimmingCharacters(in: .whitespaces) }
            else if line.hasPrefix("Because:") { because = line.dropFirst(8).trimmingCharacters(in: .whitespaces) }
            else if !line.trimmingCharacters(in: .whitespaces).isEmpty { rest.append(line) }
        }
        return (rest.joined(separator: "\n"), rejected, because)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(dot.opacity(0.25)).frame(width: 22, height: 22).scaleEffect(pulse ? 1.25 : 0.8).opacity(pulse ? 0 : 1)
                    Circle().fill(dot).frame(width: 10, height: 10).shadow(color: dot, radius: 6)
                }
                .frame(width: 22, height: 22).padding(.top, 14)
                if !last {
                    Rectangle().fill(LinearGradient(colors: [dot.opacity(0.6), Night.line], startPoint: .top, endPoint: .bottom))
                        .frame(width: 1.5).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 22)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Label(commit.kind.title, systemImage: commit.kind.symbol).font(.system(size: 11.5, weight: .bold)).textCase(.uppercase).tracking(0.6)
                        .foregroundStyle(commit.kind.colour)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(commit.kind.colour.opacity(0.14), in: .capsule)
                    Label(commit.branch, systemImage: workspace.ledger.team[commit.id] == nil ? "arrow.triangle.branch" : "person.2").font(.system(size: 11.5)).foregroundStyle(Night.dim)
                    Text(commit.at.formatted(date: .omitted, time: .shortened)).font(.system(size: 11.5)).foregroundStyle(Night.faint).monospacedDigit()
                    if let by = workspace.ledger.retiredBy[commit.id], by.kind == .decision { tag("Replaced", Night.stale).help("Replaced by decision \(by.id)") }
                    else if wrong { tag("Marked wrong", Night.stale) }
                    if workspace.ledger.unresolved[commit.id] != nil { tag("Unresolved", WatchPanel.amber) }
                    if !stale.isEmpty { tag("Check again", Night.stale).help("Changed since: " + stale.joined(separator: ", ")) }
                    Spacer(minLength: 0)
                    author
                }
                Text(commit.message).font(.system(size: 14.5, weight: commit.kind == .plan || commit.kind == .decision ? .semibold : .regular))
                    .foregroundStyle(wrong ? Night.dim : Night.note).strikethrough(wrong, color: Night.stale.opacity(0.7)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                let parts = reasons
                if !parts.rest.isEmpty {
                    Text(parts.rest).font(.system(size: 12.5)).foregroundStyle(Night.dim).lineLimit(4).textSelection(.enabled)
                }
                if let because = parts.because { reason("Because", because, "quote.opening", Color(red: 0.42, green: 0.92, blue: 0.66)) }
                if let rejected = parts.rejected { reason("Turned down", rejected, "xmark.circle", Color(red: 1.0, green: 0.55, blue: 0.5)) }
                if !stale.isEmpty, !wrong, ![.handoff, .confirmation, .code].contains(commit.kind) {
                    StillRight(workspace: workspace, commit: commit, changed: stale)
                }
                if !wrong { Unresolved(workspace: workspace, commit: commit) }
                files
                if correcting {
                    HStack {
                        TextField("What is right instead", text: $right).textFieldStyle(.roundedBorder)
                        Button("Mark Wrong") {
                            let words = right
                            Task { await workspace.markWrong(commit.id, why: words) }
                            correcting = false
                        }
                        .disabled(right.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Cancel") { correcting = false }
                    }
                    .controlSize(.small)
                }
            }
            .padding(16)
            .skyCard(tint: wrong ? Night.stale : commit.kind.colour)
            .padding(.bottom, 14)
            Spacer(minLength: 0)
        }
        .contextMenu {
            if commit.kind != .correction && !wrong { Button("Mark Wrong…") { correcting = true } }
            if !stale.isEmpty, !wrong, ![.handoff, .confirmation, .code].contains(commit.kind) {
                Button("Still Right") { Task { await workspace.confirm(commit.id) } }
            }
            Button("Copy Message") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(commit.message, forType: .string) }
            if let session = commit.session, workspace.sessions.contains(where: { $0.id == session }) {
                Button("Open Conversation") { workspace.go(.session(session)) }
            }
        }
    }

    private var author: some View {
        let who = commit.author
        // A team decision is signed with the person who kept it and the program they used (D-109).
        // The byline is worked out from the folder the file is in, not the branch shown (the team's name) (D-111).
        if let person = commit.person, let folder = workspace.ledger.teamFolder[commit.id] {
            var signed = commit
            signed.branch = folder
            let line = signed.teamByline
            let matches = line.hasPrefix("kept by ")
            return AnyView(HStack(spacing: 6) {
                AuthorBadge(name: matches ? person : folder)
                Text(matches ? "\(person) · \(folder)'s files" : "\(folder)'s files · claims \(person)")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(matches ? Night.note.opacity(0.85) : Night.stale).lineLimit(1)
            }
            .help(line.prefix(1).uppercased() + line.dropFirst()))
        }
        return AnyView(HStack(spacing: 6) {
            AuthorBadge(name: who)
            Text("\(who)\(commit.client.map { $0 == who ? "" : " · \($0)" } ?? "")\(commit.modelSaid.map { $0 == who ? "" : " · model said \($0)" } ?? "")\(commit.sha.map { " · \($0.prefix(7))" } ?? "")")
                .font(.system(size: 11.5)).foregroundStyle(Night.faint).lineLimit(1)
        }
        .help(commit.byline.prefix(1).uppercased() + commit.byline.dropFirst()))
    }

    private func reason(_ title: String, _ text: String, _ symbol: String, _ colour: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5).fill(colour.opacity(0.8)).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(colour)
                Text(text).font(.system(size: 12.5)).foregroundStyle(Night.note.opacity(0.78)).lineLimit(5).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func tag(_ text: String, _ colour: Color) -> some View {
        Text(text).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 6).padding(.vertical, 1).background(colour, in: .capsule)
    }

    @ViewBuilder private var files: some View {
        let paths = commit.cites.keys.sorted()
        if !paths.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(paths.prefix(8), id: \.self) { path in
                        Button { workspace.go(.file(path), newTab: true) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                if LibraryKind.of(path) == .code {
                                    CodeChip(path: path, stale: stale.contains(path))
                                } else if workspace.map.files.contains(where: { $0.path == path }) {
                                    CoverImage(workspace: workspace, path: path, size: CGSize(width: 200, height: 150), compact: true)
                                        .frame(width: 84, height: 63).clipShape(.rect(cornerRadius: 5))
                                        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(stale.contains(path) ? Night.stale : (LibraryKind.colour(of: path) ?? Night.line).opacity(0.5)) }
                                }
                                Text(path.fileName).font(.system(size: 10.5)).foregroundStyle(stale.contains(path) ? Night.stale : Night.dim).lineLimit(1).frame(width: 84, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain).help(path)
                    }
                }
            }
        }
    }
}

/// A code file a commit rests on: its language colour, its extension and its folder, in place of a blank cover.
struct CodeChip: View {
    let path: String
    let stale: Bool

    private var ext: String { (path as NSString).pathExtension.lowercased() }
    private var colour: Color {
        switch ext {
        case "py": return Color(red: 0.36, green: 0.62, blue: 0.95)
        case "swift": return Color(red: 1.0, green: 0.52, blue: 0.30)
        case "js", "mjs", "cjs": return Color(red: 0.96, green: 0.86, blue: 0.35)
        case "ts", "tsx": return Color(red: 0.25, green: 0.56, blue: 0.95)
        case "rs": return Color(red: 0.87, green: 0.55, blue: 0.40)
        case "go": return Color(red: 0.33, green: 0.82, blue: 0.90)
        case "sh", "zsh", "bash": return Color(red: 0.55, green: 0.88, blue: 0.45)
        default: return Color(red: 0.70, green: 0.72, blue: 0.80)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(ext.isEmpty ? "file" : ext).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(.black)
                .padding(.horizontal, 5).padding(.vertical, 1).background(colour, in: .rect(cornerRadius: 3))
            Spacer(minLength: 0)
            Text(path.folderPath.fileName + "/").font(.system(size: 10, design: .monospaced)).foregroundStyle(Night.faint).lineLimit(1)
        }
        .padding(8)
        .frame(width: 84, height: 63, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(colour.opacity(0.75)).padding(8)
        }
        .background(LinearGradient(colors: [colour.opacity(0.22), colour.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(stale ? Night.stale : colour.opacity(0.45)) }
    }
}

/// For the Library inspector: what the Ledger says about this file.
struct LedgerAboutFile: View {
    let workspace: Workspace
    let path: String

    var body: some View {
        let found = workspace.ledger.citing(path)
        VStack(alignment: .leading, spacing: 8) {
            Text("In the Ledger").font(.system(size: 12, weight: .semibold))
            if found.isEmpty {
                Text("No session has written about this yet.").font(.system(size: 12)).foregroundStyle(Night.faint)
            }
            ForEach(found.prefix(5), id: \.id) { commit in
                let flagged = workspace.ledger.reverted.contains(commit.id) || workspace.ledger.stale[commit.id] != nil
                Button { workspace.go(.ledger(commit.branch)) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: commit.kind.symbol).foregroundStyle(flagged ? Night.stale : commit.kind.colour).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commit.message).font(.system(size: 12)).lineLimit(3).foregroundStyle(Night.note.opacity(flagged ? 0.6 : 0.9))
                            Text("\(commit.kind.title) · \(commit.author)").font(.system(size: 11)).foregroundStyle(Night.faint)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
