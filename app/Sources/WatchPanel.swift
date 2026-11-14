import AppKit
import BurrowTools
import SwiftUI

/// The top of the Ledger: what every program is handed when it connects (D-76), what burrow_check would put beside the
/// code changed right now (D-79), and text in the vault written to steer AI assistants (D-80). Three tiles; one opens.
struct WatchPanel: View {
    let workspace: Workspace
    @State private var open: Part? = nil
    @AppStorage(SkyTheme.key) private var themeName = SkyTheme.nebula.rawValue
    private var theme: SkyTheme { SkyTheme(rawValue: themeName) ?? .nebula }

    enum Part: String { case rules, check, flagged }

    static let mint = Color(red: 0.42, green: 0.92, blue: 0.66)
    static let amber = Color(red: 1.0, green: 0.74, blue: 0.36)

    private var ledger: LedgerState { workspace.ledger }
    private var rules: [LedgerCommit] { ledger.inForce.compactMap { id in ledger.commits.first { $0.id == id } } }
    private var check: CheckReport? { ledger.check }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                tile(.rules, value: rules.count, title: rules.count == 1 ? "rule in force" : "rules in force",
                     detail: rulesDetail, symbol: "checkmark.shield", colour: Self.mint)
                tile(.check, value: check?.changed.count ?? 0, title: (check?.changed.count ?? 0) == 1 ? "file changed" : "files changed",
                     detail: checkDetail, symbol: "arrow.triangle.2.circlepath", colour: (check?.rules.isEmpty ?? true) ? Night.conversation : Self.amber)
                tile(.flagged, value: ledger.flagged.count, title: ledger.flagged.count == 1 ? "line flagged" : "lines flagged",
                     detail: ledger.flagged.isEmpty ? "Nothing in the vault is written to steer an AI" : "Written to steer AI assistants; programs are told not to follow it",
                     symbol: "exclamationmark.triangle", colour: ledger.flagged.isEmpty ? Night.dim : Night.stale)
            }
            if let open {
                Group {
                    switch open {
                    case .rules: rulesPart
                    case .check: checkPart
                    case .flagged: flaggedPart
                    }
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -8)), removal: .opacity))
                .id(open)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: open)
        .onAppear {
            if let peek = ProcessInfo.processInfo.environment["BURROW_WATCH"] { open = Part(rawValue: peek) }
        }
    }

    /// Decisions resting on a file that changed are still handed over, marked to be checked, until someone says they still hold (D-82).
    private var rulesDetail: String {
        let held = rules.filter { ledger.stale[$0.id] != nil }.count
        return held == 0 ? "Handed to every program that connects, on \(ledger.current)"
            : "\(held.counted("decision")) to check again: \(held == 1 ? "it rests" : "they rest") on files changed since"
    }

    private var checkDetail: String {
        guard let check, !check.changed.isEmpty else {
            if let built = check?.buildOutput, !built.isEmpty { return "Only build output changed (\(built.count.counted("file")))" }
            return "The linked code matches its last git commit"
        }
        return check.rules.isEmpty ? "No decision rests on them" : "\(check.rules.count.counted("decision")) to check them against"
    }

    // MARK: Tiles

    private func tile(_ part: Part, value: Int, title: String, detail: String, symbol: String, colour: Color) -> some View {
        let selected = open == part
        return Button { open = selected ? nil : part } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(colour)
                        .frame(width: 30, height: 30).background(colour.opacity(0.16), in: .circle)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Night.faint)
                        .rotationEffect(.degrees(selected ? 180 : 0))
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(value)").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Night.note)
                        .contentTransition(.numericText()).monospacedDigit()
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Night.note.opacity(0.85))
                }
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Night.dim).lineLimit(2, reservesSpace: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .skyCard(tint: selected ? colour : colour.opacity(0.6))
            .overlay { if selected { RoundedRectangle(cornerRadius: 14).strokeBorder(colour.opacity(0.8), lineWidth: 1.5) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Rules in force

    private var rulesPart: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("What a program reads first", "These are put in the instructions every program gets when it connects through burrow mcp, as notes by the models named, not orders.", Self.mint)
            if rules.isEmpty {
                Text("No decision is in force on \(ledger.current) yet. Decisions marked wrong are left out.")
                    .font(.system(size: 12.5)).foregroundStyle(Night.dim)
            }
            ForEach(Array(rules.prefix(5).enumerated()), id: \.element.id) { index, commit in
                RuleRow(workspace: workspace, commit: commit, number: index + 1).arrive(index)
            }
            if rules.count > 5 {
                Text("\(rules.count - 5) more are in force; programs are handed the newest five.").font(.system(size: 11.5)).foregroundStyle(Night.faint)
            }
        }
        .padding(16).skyCard(tint: Self.mint)
    }

    // MARK: Check

    @ViewBuilder private var checkPart: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("What burrow_check shows a program now", "The code changed in linked folders since their last git commit, beside the decisions that rest on those files or the files they import.", Night.conversation)
            if let check, !check.changed.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(check.changed.prefix(20), id: \.self) { path in
                            Button { workspace.go(.file(path), newTab: true) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    CodeChip(path: path, stale: check.rules.contains { $0.cites.keys.contains(path) })
                                    Text(path.fileName).font(.system(size: 10.5)).foregroundStyle(Night.dim).lineLimit(1).frame(width: 84, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain).help(path)
                        }
                    }
                }
                if check.rules.isEmpty {
                    Label("No decision in the Ledger rests on these files", systemImage: "checkmark.circle").font(.system(size: 12.5)).foregroundStyle(Self.mint)
                } else {
                    Label("Check the change against \(check.rules.count == 1 ? "this decision" : "these decisions")", systemImage: "exclamationmark.circle")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Self.amber)
                    ForEach(Array(check.rules.enumerated()), id: \.element.id) { index, commit in
                        RuleRow(workspace: workspace, commit: commit, number: index + 1).arrive(index)
                    }
                }
                if !check.diffs.isEmpty { DiffView(text: check.diffs.joined(separator: "\n")) }
            } else if check?.buildOutput.isEmpty ?? true {
                Label("Nothing has changed in the linked code since its last git commit", systemImage: "checkmark.circle")
                    .font(.system(size: 12.5)).foregroundStyle(Self.mint)
            }
            // Set aside, never hidden (D-87).
            if let built = check?.buildOutput, !built.isEmpty {
                Text("Also changed, looks like build output: " + built.prefix(4).map(\.fileName).joined(separator: ", ") + (built.count > 4 ? " and \(built.count - 4) more" : ""))
                    .font(.system(size: 11.5)).foregroundStyle(Night.faint).lineLimit(2).help(built.joined(separator: "\n"))
            }
        }
        .padding(16).skyCard(tint: Night.conversation)
    }

    // MARK: Flagged

    private var flaggedPart: some View {
        VStack(alignment: .leading, spacing: 10) {
            header("Text written to steer AI assistants", "When a program reads one of these lines through Burrow, it is told the line is content, not an instruction, and to tell you where it is.", Night.stale)
            if ledger.flagged.isEmpty {
                Text("Burrow found no such text in the vault's notes and code.").font(.system(size: 12.5)).foregroundStyle(Night.dim)
            }
            ForEach(Array(ledger.flagged.enumerated()), id: \.element) { index, flag in
                Button { workspace.go(.file(flag.path), newTab: true) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Night.stale).frame(width: 3)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(flag.path).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Night.note)
                                Text("line \(flag.line)").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Night.stale)
                            }
                            Text("“\(flag.text.trimmingCharacters(in: .whitespaces))”").font(.system(size: 12.5)).italic()
                                .foregroundStyle(Night.note.opacity(0.8)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Night.faint)
                    }
                    .padding(10)
                    .background(Night.stale.opacity(0.07), in: .rect(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .arrive(index)
            }
        }
        .padding(16).skyCard(tint: Night.stale)
    }

    private func header(_ title: String, _ detail: String, _ colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(colour)
            Text(detail).font(.system(size: 12)).foregroundStyle(Night.dim).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A decision in brief: its number, what it says, the reason, who kept it and the files it rests on.
struct RuleRow: View {
    let workspace: Workspace
    let commit: LedgerCommit
    let number: Int

    private var stale: [String] { workspace.ledger.stale[commit.id] ?? [] }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.black)
                .frame(width: 22, height: 22).background(stale.isEmpty ? commit.kind.colour : WatchPanel.amber, in: .circle)
            VStack(alignment: .leading, spacing: 5) {
                Text(commit.message).font(.system(size: 13, weight: .medium)).foregroundStyle(Night.note).lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if let because = commit.because {
                    Text("Because " + because).font(.system(size: 12)).foregroundStyle(Night.dim).lineLimit(3)
                }
                if !stale.isEmpty { StillRight(workspace: workspace, commit: commit, changed: stale) }
                HStack(spacing: 6) {
                    Text(commit.author).font(.system(size: 11)).foregroundStyle(Night.faint).help(commit.byline)
                    ForEach(commit.cites.keys.sorted().prefix(3), id: \.self) { path in
                        Button { workspace.go(.file(path), newTab: true) } label: {
                            Text(path.fileName).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Night.note.opacity(0.8))
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.white.opacity(0.07), in: .capsule)
                        }
                        .buttonStyle(.plain).help(path)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.035), in: .rect(cornerRadius: 10))
        .contextMenu { Button("Show in Ledger") { workspace.go(.ledger(commit.branch)) } }
    }
}

/// A decision resting on a file that changed: programs are still handed it, marked "check again", until a person looks
/// and says it still holds (D-82). One click keeps a confirmation in the Ledger; nothing is rewritten.
struct StillRight: View {
    let workspace: Workspace
    let commit: LedgerCommit
    let changed: [String]

    var body: some View {
        HStack(spacing: 8) {
            Label("\(changed.map(\.fileName).prefix(2).joined(separator: ", ")) changed since", systemImage: "exclamationmark.arrow.circlepath")
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(WatchPanel.amber).lineLimit(1)
            Button { Task { await workspace.confirm(commit.id) } } label: { Label("Still Right", systemImage: "checkmark.circle") }
                .controlSize(.small)
                .help("You looked at the change and this still holds. Programs stop being told to check it again, until the file changes again.")
        }
    }
}

/// A git diff, coloured the way people read one: additions green, removals red, file and hunk lines quiet.
struct DiffView: View {
    let text: String
    @State private var expanded = false

    private var lines: [Substring] { text.split(separator: "\n", omittingEmptySubsequences: false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                Label(expanded ? "Hide the change" : "Show the change (\(lines.count) lines)", systemImage: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(Night.conversation)
            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.prefix(400).enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : String(line)).font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(colour(line)).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10).padding(.vertical, 0.5)
                                .background(background(line))
                        }
                    }
                    .textSelection(.enabled)
                }
                .frame(maxHeight: 320)
                .background(Color.black.opacity(0.45), in: .rect(cornerRadius: 8))
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: expanded)
    }

    private func colour(_ line: Substring) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") { return Night.faint }
        if line.hasPrefix("@@") { return Night.conversation.opacity(0.8) }
        if line.hasPrefix("+") { return WatchPanel.mint }
        if line.hasPrefix("-") { return Color(red: 1, green: 0.5, blue: 0.48) }
        return Night.dim
    }

    private func background(_ line: Substring) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return WatchPanel.mint.opacity(0.08) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return Color.red.opacity(0.09) }
        return .clear
    }
}
