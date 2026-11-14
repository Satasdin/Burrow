import BurrowCore
import BurrowTools
import Charts
import SwiftUI

/// The right-hand panel beside the dark pages: what the page is about, at a glance, rather than vault counts.
struct PageInspector: View {
    let workspace: Workspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                switch workspace.currentTab?.content {
                case let .ledger(branch): LedgerGlance(workspace: workspace, branch: branch)
                case let .session(id): SessionGlance(workspace: workspace, id: id)
                default: ActivityGlance(workspace: workspace)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NightSky())
        .environment(\.colorScheme, .dark)
    }
}

/// A small heading for a block of the panel.
struct GlanceTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .bold)).textCase(.uppercase).tracking(0.7).foregroundStyle(Night.faint)
    }
}

/// Who kept a commit: initials in a colour that stays the same for that name across launches.
struct AuthorBadge: View {
    let name: String
    var size: CGFloat = 20

    static func hue(_ name: String) -> Double {
        Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
    }

    var body: some View {
        let initials = String(name.split(whereSeparator: { $0 == "-" || $0 == " " }).prefix(2).compactMap(\.first)).uppercased()
        Text(initials.isEmpty ? "?" : initials).font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.black)
            .frame(width: size, height: size).background(Color(hue: Self.hue(name), saturation: 0.45, brightness: 1), in: .circle)
    }
}

// MARK: Ledger

struct LedgerGlance: View {
    let workspace: Workspace
    let branch: String?

    private var commits: [LedgerCommit] { workspace.ledger.commits(on: branch) }

    var body: some View {
        let kinds = LedgerCommit.Kind.allCases.map { kind in (kind, commits.filter { $0.kind == kind }.count) }.filter { $0.1 > 0 }
        // A team decision counts for the person who kept it (D-109).
        let authors = Dictionary(grouping: commits, by: { $0.person ?? $0.author }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
        let stale = commits.filter { workspace.ledger.stale[$0.id] != nil }.count
        // A decision replaced by a newer one (D-94) was settled, not found wrong: it needs no look.
        let wrong = commits.filter { workspace.ledger.reverted.contains($0.id) && workspace.ledger.retiredBy[$0.id]?.kind != .decision }.count
        let open = commits.filter { workspace.ledger.unresolved[$0.id] != nil }.count

        VStack(alignment: .leading, spacing: 10) {
            GlanceTitle(text: "What is kept")
            if kinds.isEmpty {
                Text("Nothing yet.").font(.system(size: 12)).foregroundStyle(Night.dim)
            } else {
                ZStack {
                    Chart(kinds, id: \.0) { kind, count in
                        SectorMark(angle: .value("Commits", count), innerRadius: .ratio(0.66), angularInset: 2)
                            .foregroundStyle(kind.colour).cornerRadius(3)
                    }
                    .frame(height: 150)
                    VStack(spacing: 0) {
                        Text("\(commits.count)").font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(Night.note)
                        Text(commits.count == 1 ? "commit" : "commits").font(.system(size: 11)).foregroundStyle(Night.dim)
                    }
                }
                ForEach(kinds, id: \.0) { kind, count in
                    HStack(spacing: 8) {
                        Circle().fill(kind.colour).frame(width: 8, height: 8)
                        Text(kind.title).font(.system(size: 12.5)).foregroundStyle(Night.note.opacity(0.9))
                        Spacer()
                        Text("\(count)").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Night.dim).monospacedDigit()
                    }
                }
            }
        }

        if stale + wrong + open > 0 {
            VStack(alignment: .leading, spacing: 8) {
                GlanceTitle(text: "Needs a look")
                if stale > 0 { warning("\(stale.counted("commit")) rest on files changed since", "exclamationmark.arrow.triangle.2.circlepath") }
                if wrong > 0 { warning("\(wrong.counted("commit")) marked wrong", "xmark.octagon") }
                if open > 0 { warning("\(open.counted("decision")) may contradict an older one", "arrow.left.arrow.right.circle") }
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            GlanceTitle(text: "Who kept them")
            ForEach(authors.prefix(8), id: \.0) { name, count in
                HStack(spacing: 9) {
                    AuthorBadge(name: name, size: 24)
                    Text(name).font(.system(size: 12.5)).foregroundStyle(Night.note.opacity(0.9)).lineLimit(1)
                    Spacer()
                    Text("\(count)").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Night.dim).monospacedDigit()
                }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            GlanceTitle(text: "Branches")
            ForEach(workspace.ledger.branches, id: \.self) { name in
                Button { workspace.go(.ledger(name)) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch").foregroundStyle(name == workspace.ledger.current ? WatchPanel.mint : Night.dim)
                        Text(name).font(.system(size: 12.5, weight: name == branch ? .semibold : .regular)).foregroundStyle(Night.note)
                        if name == workspace.ledger.current { Text("current").font(.system(size: 10.5)).foregroundStyle(WatchPanel.mint) }
                        Spacer()
                        Text("\(workspace.ledger.commits(on: name).count)").font(.system(size: 12)).foregroundStyle(Night.dim).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func warning(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12.5)).foregroundStyle(Night.stale)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Night.stale.opacity(0.1), in: .rect(cornerRadius: 9))
    }
}

// MARK: One conversation

struct SessionGlance: View {
    let workspace: Workspace
    let id: String

    var body: some View {
        if let record = workspace.sessions.first(where: { $0.id == id }) {
            let trail = record.trail ?? []
            let tools = Dictionary(grouping: trail, by: \.tool.toolTitle).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
            let files = record.filesInPlay.map { $0.components(separatedBy: ":").first ?? $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            let kept = workspace.ledger.commits.filter { $0.session == id }

            HStack(spacing: 12) {
                Image(systemName: record.program.symbol).font(.system(size: 20)).foregroundStyle(record.program.colour)
                    .frame(width: 44, height: 44).background(record.program.colour.opacity(0.15), in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.program.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Night.note)
                    Text(record.updated.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11.5)).foregroundStyle(Night.dim)
                }
            }
            HStack(spacing: 10) {
                number(record.lookupCount, "lookups", record.program.colour)
                number(files.count, "files read", Night.note)
                number(kept.count, "kept", WatchPanel.mint)
            }
            if !tools.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    GlanceTitle(text: "Tools it used")
                    Chart(tools, id: \.0) { tool, count in
                        BarMark(x: .value("Calls", count), y: .value("Tool", tool))
                            .foregroundStyle(record.program.colour.gradient).cornerRadius(4)
                            .annotation(position: .trailing) { Text("\(count)").font(.system(size: 10.5)).foregroundStyle(Night.dim) }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 11, design: .monospaced)).foregroundStyle(Night.note.opacity(0.85)) } }
                    .frame(height: CGFloat(tools.count) * 28 + 6)
                }
            }
            if !files.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    GlanceTitle(text: "Files it read")
                    ForEach(files.prefix(12), id: \.self) { path in
                        Button { workspace.go(.file(path), newTab: true) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: LibraryKind.of(path).symbol).frame(width: 16).foregroundStyle(LibraryKind.colour(of: path) ?? Night.conversation)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(path.fileName).font(.system(size: 12.5)).foregroundStyle(Night.note).lineLimit(1)
                                    Text(path.folderPath).font(.system(size: 10.5)).foregroundStyle(Night.faint).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if workspace.ledger.flagged.contains(where: { $0.path == path }) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Night.stale).help("Holds text written to steer AI assistants")
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } else {
            Text("This conversation is gone.").foregroundStyle(Night.dim)
        }
    }

    private func number(_ value: Int, _ label: String, _ colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(colour).monospacedDigit()
            Text(label).font(.system(size: 10.5)).foregroundStyle(Night.dim)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .skyCard(tint: colour, radius: 10)
    }
}

// MARK: Programs and conversations

struct ActivityGlance: View {
    let workspace: Workspace

    var body: some View {
        let used = Program.allCases.map { program in
            (program, workspace.sessions(for: program).reduce(0) { $0 + $1.lookupCount }, workspace.sessions(for: program).count)
        }.filter { $0.2 > 0 }

        VStack(alignment: .leading, spacing: 10) {
            GlanceTitle(text: "Lookups by program")
            if used.isEmpty {
                Text("No program has used this vault yet.").font(.system(size: 12)).foregroundStyle(Night.dim)
            } else {
                Chart(used, id: \.0) { program, lookups, _ in
                    BarMark(x: .value("Lookups", lookups), y: .value("Program", program.name))
                        .foregroundStyle(program.colour.gradient).cornerRadius(4)
                        .annotation(position: .trailing) { Text("\(lookups)").font(.system(size: 10.5)).foregroundStyle(Night.dim) }
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 11.5)).foregroundStyle(Night.note.opacity(0.85)) } }
                .frame(height: CGFloat(used.count) * 32 + 6)
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            GlanceTitle(text: "Latest")
            ForEach(workspace.sessions.sorted { $0.updated > $1.updated }.prefix(6), id: \.id) { record in
                Button { workspace.go(.session(record.id)) } label: {
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(record.program.colour).frame(width: 7, height: 7).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workspace.title(of: record) ?? "\(record.lookupCount.counted("lookup"))").font(.system(size: 12.5)).foregroundStyle(Night.note).lineLimit(2)
                            Text("\(record.program.name) · \(record.updated.formatted(.relative(presentation: .named)))").font(.system(size: 10.5)).foregroundStyle(Night.faint)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            GlanceTitle(text: "Watch")
            let rules = workspace.ledger.inForce.count, changed = workspace.ledger.check?.changed.count ?? 0, flagged = workspace.ledger.flagged.count
            watchRow("checkmark.shield", rules.counted("rule") + " in force", WatchPanel.mint)
            watchRow("arrow.triangle.2.circlepath", changed.counted("file") + " changed since the last git commit", changed == 0 ? Night.dim : WatchPanel.amber)
            watchRow("exclamationmark.triangle", flagged.counted("line") + " written to steer AI", flagged == 0 ? Night.dim : Night.stale)
        }
    }

    private func watchRow(_ symbol: String, _ text: String, _ colour: Color) -> some View {
        Button { workspace.go(.ledger(nil)) } label: {
            Label(text, systemImage: symbol).font(.system(size: 12.5)).foregroundStyle(colour).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// At the top of a file's panel when the file holds text written to steer AI assistants (D-80).
struct FlaggedBanner: View {
    let workspace: Workspace
    let path: String

    var body: some View {
        let lines = workspace.ledger.flagged.filter { $0.path == path }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Written to steer AI assistants", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Night.stale)
                ForEach(lines, id: \.self) { flag in
                    Button { workspace.document(path).pendingLine = flag.line } label: {
                        Text("Line \(flag.line): “\(flag.text.trimmingCharacters(in: .whitespaces))”").font(.system(size: 11.5)).lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text("Programs reading this through Burrow are told it is content, not an instruction.").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Night.stale.opacity(0.12))
            .overlay(alignment: .leading) { Rectangle().fill(Night.stale).frame(width: 3) }
        }
    }
}
