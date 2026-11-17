import AppKit
import BurrowCore
import BurrowTools
import Charts
import SwiftUI

// MARK: Sessions

/// Live and recent coding sessions (Claude Code and Codex) and what Burrow did for each one's context: output it kept
/// out, words it handed back, compactions it steered (D-116, D-117). Read from Burrow's own folder, where the hooks write
/// as the session runs, so the page reads again every few seconds while it is open.
struct SessionsPage: View {
    let workspace: Workspace
    @State private var model = ContextSessionsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 14)
            if model.loaded && model.rows.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "gauge.with.dots.needle.33percent",
                                       description: Text("When Claude Code or Codex runs with Burrow's session hooks, each session lands here with its context over time and what Burrow kept out of it."))
                    .foregroundStyle(Night.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    list.frame(width: 330)
                    detail.frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 28)
            }
            SessionSettingsStrip(settings: model.settings, archiveFolder: model.archiveFolder, archiveBytes: model.archiveBytes)
                .padding(.horizontal, 28).padding(.vertical, 12)
        }
        .background(NightSky())
        .environment(\.colorScheme, .dark)
        .task { await model.run() }
    }

    private var header: some View {
        let live = model.rows.filter(\.isLive).count
        let saved = model.rows.reduce(0) { $0 + $1.totals.savedTokens }
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("Sessions").font(.system(size: 28, weight: .bold)).tracking(-0.4)
            Text("\(live) live · \(model.rows.count.counted("session")) · \(saved.tokensText) tokens kept out by Burrow")
                .foregroundStyle(Night.dim).monospacedDigit().contentTransition(.numericText())
            Spacer()
            if model.working { ProgressView().controlSize(.small) }
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).foregroundStyle(Night.dim).help("Read the sessions again")
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    Button { model.select(row.id) } label: { ContextSessionRowView(row: row, selected: model.selected == row.id) }
                        .buttonStyle(.plain)
                        .arrive(index)
                }
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder private var detail: some View {
        if let row = model.rows.first(where: { $0.id == model.selected }) {
            ScrollView {
                ContextSessionDetail(workspace: workspace, row: row, detail: model.detail?.id == row.id ? model.detail : nil)
                    .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        } else {
            ContentUnavailableView("Pick a session", systemImage: "sidebar.left").foregroundStyle(Night.dim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: The model

/// One session in the list: from the meter, the archive, or both.
struct ContextSessionRow: Identifiable, Equatable {
    let id: String
    var program: SessionText.Program?
    var name: String
    var cwd: String?
    var model: String?
    var updated: Date
    var totals: SessionReport.Totals
    /// Context tokens per request, thinned for a sparkline.
    var spark: [Int]
    var contextNow: Int
    var contextPeak: Int
    var compactions: Int

    var short: String { String(id.prefix(8)) }
    var folder: String? { cwd.map { ($0 as NSString).lastPathComponent } }
    /// A hook wrote, or the transcript grew, in the last three minutes.
    var isLive: Bool { Date().timeIntervalSince(updated) < 180 }
    var tint: Color { program?.colour ?? Night.conversation }
}

/// The selected session opened up: every request's context, where it was compacted, and what Burrow did.
struct ContextSessionDetailData: Equatable {
    let id: String
    var usage: [Int]
    /// Indexes into `usage` where the program compacted.
    var compactionsAt: [Int]
    /// Newest first.
    var events: [MeterEvent]
}

@MainActor @Observable
final class ContextSessionsModel {
    var rows: [ContextSessionRow] = []
    var selected: String?
    var detail: ContextSessionDetailData?
    var settings = SessionSettings()
    var archiveFolder = ""
    var archiveBytes = 0
    var loaded = false
    var working = false
    @ObservationIgnored private let store = ContextSessionStore()

    /// Reads now, then every four seconds while the page is open; quickly again while transcripts are still being read.
    func run() async {
        while !Task.isCancelled {
            let pending = await refresh()
            try? await Task.sleep(for: pending ? .milliseconds(80) : .seconds(4))
        }
    }

    @discardableResult
    func refresh() async -> Bool {
        working = true
        let snapshot = await store.read(budget: 0.5)
        if snapshot.rows != rows { withAnimation(.smooth(duration: 0.25)) { rows = snapshot.rows } }
        settings = snapshot.settings
        archiveFolder = snapshot.archiveFolder
        archiveBytes = snapshot.archiveBytes
        if selected == nil || !rows.contains(where: { $0.id == selected }) { selected = rows.first?.id }
        await loadDetail()
        loaded = true
        working = snapshot.pending
        return snapshot.pending
    }

    func select(_ id: String) {
        guard id != selected else { return }
        selected = id
        detail = nil
        Task { await loadDetail() }
    }

    private func loadDetail() async {
        guard let id = selected else { detail = nil; return }
        let fresh = await store.detail(id)
        guard id == selected else { return }
        if fresh != detail { detail = fresh }
    }
}

/// Reads sessions off the main thread and keeps what it parsed, keyed by the file's size and date, so only a transcript
/// that grew is read again.
actor ContextSessionStore {
    struct Snapshot {
        var rows: [ContextSessionRow]
        var settings: SessionSettings
        var archiveFolder: String
        var archiveBytes: Int
        var pending: Bool
    }

    private struct Parsed {
        var stamp: String
        var name: String
        var cwd: String?
        var model: String?
        var usage: [Int]
        var compactionsAt: [Int]
    }

    private var parsed: [String: Parsed] = [:]
    private var totals: [String: (updated: Date, totals: SessionReport.Totals)] = [:]
    private var located: [String: (path: String, program: SessionText.Program)] = [:]
    private var codexIndex: [String: String] = [:]
    private var codexIndexedAt = Date.distantPast
    private var archived: [SessionArchive.Meta] = []
    private var archivedAt = Date.distantPast
    private var lastRows: [String: ContextSessionRow] = [:]

    func read(budget: TimeInterval) -> Snapshot {
        let places = SessionHooks.Places()
        if Date().timeIntervalSince(archivedAt) > 15 {
            archived = places.archive.list()
            archivedAt = Date()
        }
        let byID = Dictionary(archived.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var updated: [String: Date] = [:]
        var metered: [String: Date] = [:]
        for (id, at) in places.meter.sessions() { updated[id] = at; metered[id] = at }
        for meta in archived.prefix(50) { updated[meta.id] = max(updated[meta.id] ?? .distantPast, meta.ended ?? meta.sourceModified) }

        let started = Date()
        var pending = false
        var rows: [ContextSessionRow] = []
        for (id, meterAt) in updated {
            let meta = byID[id]
            var row = lastRows[id] ?? ContextSessionRow(id: id, program: meta?.program, name: meta?.name ?? "Session \(id.prefix(8))", cwd: meta?.cwd,
                                                         model: meta?.model, updated: meterAt, totals: SessionReport.totals([]), spark: [],
                                                         contextNow: meta?.contextLast ?? 0, contextPeak: meta?.contextPeak ?? 0, compactions: meta?.compactions ?? 0)
            row.updated = meterAt
            row.totals = eventTotals(id, at: metered[id], meter: places.meter)
            if let source = source(id, meta: meta) {
                row.program = source.program
                if let at = modified(source.path) { row.updated = max(row.updated, at) }
            }
            if let summary = parsedSummary(id, meta: meta, archive: places.archive, allowParse: Date().timeIntervalSince(started) < budget) {
                row.name = summary.name
                row.cwd = summary.cwd ?? row.cwd
                row.model = summary.model ?? row.model
                row.spark = Self.thin(summary.usage, to: 48)
                row.contextNow = summary.usage.last ?? row.contextNow
                row.contextPeak = summary.usage.max() ?? row.contextPeak
                row.compactions = max(summary.compactionsAt.count, row.totals.compactions)
            } else if needsParse(id, meta: meta) {
                pending = true
            }
            lastRows[id] = row
            rows.append(row)
        }
        rows.sort { $0.updated > $1.updated }
        return Snapshot(rows: rows, settings: places.settings, archiveFolder: places.archive.folder.path,
                        archiveBytes: archived.reduce(0) { $0 + $1.archivedBytes }, pending: pending)
    }

    func detail(_ id: String) -> ContextSessionDetailData {
        let places = SessionHooks.Places()
        let meta = archived.first { $0.id == id } ?? places.archive.meta(.claudeCode, id) ?? places.archive.meta(.codex, id)
        let summary = parsedSummary(id, meta: meta, archive: places.archive, allowParse: true)
        return ContextSessionDetailData(id: id, usage: summary?.usage ?? [], compactionsAt: summary?.compactionsAt ?? [],
                                        events: places.meter.events(session: id).reversed())
    }

    // MARK: Reading

    /// The meter's totals, read again only when its file changed (`at` is when it was last written).
    private func eventTotals(_ id: String, at: Date?, meter: SessionMeter) -> SessionReport.Totals {
        guard let at else { return SessionReport.totals([]) }
        if let known = totals[id], known.updated == at { return known.totals }
        let made = SessionReport.totals(meter.events(session: id))
        totals[id] = (at, made)
        return made
    }

    /// The live transcript: where the archive says it came from, else found in Claude Code's or Codex's folders.
    private func source(_ id: String, meta: SessionArchive.Meta?) -> (path: String, program: SessionText.Program)? {
        if let meta, FileManager.default.fileExists(atPath: meta.sourcePath) { return (meta.sourcePath, meta.program) }
        if let known = located[id], FileManager.default.fileExists(atPath: known.path) { return known }
        for root in Folds.transcriptRoots() {
            for project in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                let file = project.appendingPathComponent(id + ".jsonl")
                if FileManager.default.fileExists(atPath: file.path) {
                    located[id] = (file.path, .claudeCode)
                    return located[id]
                }
            }
        }
        if codexIndex[id] == nil, Date().timeIntervalSince(codexIndexedAt) > 30 { indexCodex() }
        if let path = codexIndex[id] {
            located[id] = (path, .codex)
            return located[id]
        }
        return nil
    }

    private func indexCodex() {
        codexIndexedAt = Date()
        guard let folder = SessionArchive.Sources.standard().codex,
              let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return }
        for case let file as URL in walker where file.pathExtension == "jsonl" && file.lastPathComponent.hasPrefix("rollout-") {
            // rollout-<date>T<time>-<uuid>.jsonl: the session's id is the last 36 characters.
            let name = file.deletingPathExtension().lastPathComponent
            if name.count > 36 { codexIndex[String(name.suffix(36))] = file.path }
        }
    }

    private func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private func stamp(of path: String) -> String? {
        guard let values = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return "\(path)|\((values[.size] as? Int) ?? 0)|\((values[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
    }

    private func wanted(_ id: String, meta: SessionArchive.Meta?) -> String? {
        if let source = located[id] ?? meta.map({ ($0.sourcePath, $0.program) }), let stamp = stamp(of: source.path) { return stamp }
        if let meta { return "archive|\(meta.archivedAt.timeIntervalSince1970)" }
        return nil
    }

    private func needsParse(_ id: String, meta: SessionArchive.Meta?) -> Bool {
        guard let wanted = wanted(id, meta: meta) else { return false }
        return parsed[id]?.stamp != wanted
    }

    /// The session's name and context over time: from the transcript while it exists (it may still be growing), else from
    /// the archive's copy. Read again only when the file changed.
    private func parsedSummary(_ id: String, meta: SessionArchive.Meta?, archive: SessionArchive, allowParse: Bool) -> Parsed? {
        let source = self.source(id, meta: meta)
        guard let wanted = wanted(id, meta: meta) else { return nil }
        if let known = parsed[id], known.stamp == wanted { return known }
        guard allowParse else { return parsed[id] }
        var session: SessionText?
        if let source, let text = try? String(contentsOfFile: source.path, encoding: .utf8) {
            session = source.program == .codex ? SessionText.codex(text, id: id) : SessionText.claudeCode(text, id: id)
        } else if let meta {
            session = archive.load(meta)
        }
        guard let session else { return nil }
        let made = Parsed(stamp: wanted, name: session.name, cwd: session.cwd, model: session.model,
                          usage: session.usage.map(\.context), compactionsAt: Self.compactionIndexes(session))
        parsed[id] = made
        return made
    }

    /// Where each compaction falls among the requests: the first request at or after it.
    private static func compactionIndexes(_ session: SessionText) -> [Int] {
        guard !session.usage.isEmpty else { return [] }
        return session.compactions.compactMap { compaction in
            guard let at = compaction.at else { return nil }
            return session.usage.firstIndex { ($0.at ?? .distantPast) >= at } ?? session.usage.count - 1
        }
    }

    static func thin(_ values: [Int], to count: Int) -> [Int] {
        guard values.count > count, count > 1 else { return values }
        let step = Double(values.count - 1) / Double(count - 1)
        return (0..<count).map { values[Int((Double($0) * step).rounded())] }
    }
}

// MARK: The list

struct ContextSessionRowView: View {
    let row: ContextSessionRow
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if row.isLive { LiveDot(colour: row.tint) }
                Image(systemName: row.program?.symbol ?? "questionmark.circle").font(.system(size: 11)).foregroundStyle(row.tint)
                Text(row.program?.title ?? "Unknown program").font(.system(size: 11.5, weight: .medium)).foregroundStyle(row.tint)
                if let folder = row.folder { Text(folder).font(.system(size: 11.5)).foregroundStyle(Night.dim).lineLimit(1) }
                Spacer(minLength: 4)
                Text(row.updated.formatted(.relative(presentation: .named))).font(.system(size: 11)).foregroundStyle(Night.faint).lineLimit(1)
            }
            Text(row.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Night.note).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .bottom, spacing: 10) {
                Sparkline(values: row.spark, colour: row.tint).frame(height: 24)
                VStack(alignment: .trailing, spacing: 3) {
                    if row.totals.savedTokens > 0 {
                        Text("−\(row.totals.savedTokens.tokensText)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.gold)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Theme.gold.opacity(0.12), in: .capsule)
                            .help("\(row.totals.savedTokens.formatted()) tokens kept out of the context by Burrow")
                    }
                    if row.contextNow > 0 {
                        Text("\(row.contextNow.tokensText) now").font(.system(size: 10.5)).foregroundStyle(Night.faint)
                    }
                }
                .monospacedDigit()
            }
        }
        .padding(12)
        .background(selected ? row.tint.opacity(0.10) : .clear, in: .rect(cornerRadius: 12))
        .skyCard(tint: selected ? row.tint : .white, radius: 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A context line drawn small: no axes, the last point lit.
struct Sparkline: View {
    let values: [Int]
    let colour: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let top = values.max(), top > 0 else {
                var flat = Path()
                flat.move(to: CGPoint(x: 0, y: size.height - 1)); flat.addLine(to: CGPoint(x: size.width, y: size.height - 1))
                context.stroke(flat, with: .color(Night.line), lineWidth: 1)
                return
            }
            let points = values.enumerated().map { index, value in
                CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1), y: size.height - 2 - (size.height - 4) * CGFloat(value) / CGFloat(top))
            }
            var line = Path()
            line.addLines(points)
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height)); area.addLine(to: CGPoint(x: 0, y: size.height)); area.closeSubpath()
            context.fill(area, with: .linearGradient(Gradient(colors: [colour.opacity(0.28), colour.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(colour.opacity(0.9)), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            if let last = points.last {
                context.fill(Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)), with: .color(colour))
            }
        }
        .accessibilityHidden(true)
    }
}

struct LiveDot: View {
    let colour: Color
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle().fill(WatchPanel.mint).frame(width: 6, height: 6)
            .shadow(color: WatchPanel.mint, radius: glow ? 5 : 1)
            .help("Live: written to in the last three minutes")
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glow = true }
            }
    }
}

// MARK: The detail

struct ContextSessionDetail: View {
    let workspace: Workspace
    let row: ContextSessionRow
    let detail: ContextSessionDetailData?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            tiles
            chart
            ResumeCommands(workspace: workspace, id: row.id, program: row.program)
            timeline
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: row.program?.symbol ?? "questionmark.circle").foregroundStyle(row.tint)
                Text(row.program?.title ?? "Unknown program").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(row.tint)
                if row.isLive { LiveDot(colour: row.tint); Text("live").font(.system(size: 11.5, weight: .medium)).foregroundStyle(WatchPanel.mint) }
                Text(row.short).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Night.faint).textSelection(.enabled)
            }
            Text(row.name).font(.system(size: 22, weight: .bold)).tracking(-0.3).foregroundStyle(Night.note).lineLimit(3)
            HStack(spacing: 12) {
                if let cwd = row.cwd { Label(row.folder ?? cwd, systemImage: "folder").help(cwd) }
                if let model = row.model { Label(model, systemImage: "cpu") }
                Label(row.updated.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
            }
            .font(.system(size: 12)).foregroundStyle(Night.dim).lineLimit(1)
        }
    }

    private var tiles: some View {
        let totals = row.totals
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
            ContextTile(title: "Context now", value: row.contextNow.tokensText, detail: "peak \(row.contextPeak.tokensText) tokens", tint: row.tint)
            ContextTile(title: "Compactions", value: row.compactions.formatted(), detail: totals.steered > 0 ? "\(totals.steered) steered by Burrow" : "none steered", tint: Night.document)
            ContextTile(title: "Kept out", value: totals.savedTokens.tokensText, detail: "tokens · \((totals.kept + totals.shortened).counted("output"))", tint: Theme.gold)
            ContextTile(title: "Recalls", value: totals.recalls.formatted(), detail: "\(totals.recalledCharacters.formatted()) characters handed back", tint: Night.conversation)
            ContextTile(title: "Expanded", value: totals.expanded.formatted(), detail: "kept outputs read again", tint: Night.cache)
        }
    }

    private struct Point: Identifiable { let id: Int; let tokens: Int }

    @ViewBuilder private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Context per request").font(.system(size: 12, weight: .semibold)).foregroundStyle(Night.dim)
                Spacer()
                if let detail, !detail.compactionsAt.isEmpty {
                    Label("compacted", systemImage: "line.diagonal").font(.system(size: 11)).foregroundStyle(Night.document.opacity(0.9))
                }
            }
            if let detail, detail.usage.count > 1 {
                let stride = max(1, detail.usage.count / 800)
                let points = Swift.stride(from: 0, to: detail.usage.count, by: stride).map { Point(id: $0 + 1, tokens: detail.usage[$0]) }
                Chart {
                    ForEach(points) { point in
                        AreaMark(x: .value("Request", point.id), y: .value("Tokens", point.tokens))
                            .foregroundStyle(LinearGradient(colors: [row.tint.opacity(0.32), row.tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Request", point.id), y: .value("Tokens", point.tokens))
                            .foregroundStyle(row.tint).lineStyle(StrokeStyle(lineWidth: 1.6))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(Array(detail.compactionsAt.enumerated()), id: \.offset) { _, index in
                        RuleMark(x: .value("Request", index + 1))
                            .foregroundStyle(Night.document.opacity(0.85)).lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .annotation(position: .top, alignment: index < detail.usage.count / 2 ? .leading : .trailing, spacing: 2) {
                                Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 9, weight: .bold)).foregroundStyle(Night.document)
                            }
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine().foregroundStyle(Night.line)
                    AxisValueLabel().foregroundStyle(Night.faint)
                } }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Night.line)
                    AxisValueLabel { if let tokens = value.as(Int.self) { Text(tokens.tokensText) } }.foregroundStyle(Night.faint)
                } }
                .chartXScale(domain: 1...max(2, detail.usage.count))
                .chartXAxisLabel("request", alignment: .trailing)
                .frame(height: 190)
                .shadow(color: row.tint.opacity(0.35), radius: 8)
            } else {
                Text(detail == nil ? "Reading the transcript…" : "No context sizes in this transcript yet.")
                    .font(.system(size: 12)).foregroundStyle(Night.faint).frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .padding(14).skyCard(tint: row.tint, radius: 12)
    }

    @ViewBuilder private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What Burrow did").font(.system(size: 15, weight: .semibold)).foregroundStyle(Night.note)
            if let events = detail?.events, !events.isEmpty {
                let shown = Array(events.prefix(300))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, event in
                        MeterEventRow(event: event, last: index == shown.count - 1)
                    }
                }
                if events.count > shown.count {
                    Text("The newest \(shown.count) of \(events.count.counted("event")).").font(.system(size: 11.5)).foregroundStyle(Night.faint)
                }
            } else {
                Text(detail == nil ? "Reading…" : "Nothing yet: Burrow's hooks have not acted in this session.")
                    .font(.system(size: 12)).foregroundStyle(Night.faint)
            }
        }
    }
}

struct ContextTile: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Night.dim)
            Text(value).font(.system(size: 22, weight: .semibold)).foregroundStyle(tint).monospacedDigit()
                .contentTransition(.numericText())
            Text(detail).font(.system(size: 10.5)).foregroundStyle(Night.faint).lineLimit(2).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .skyCard(tint: tint, radius: 12)
    }
}

/// One thing Burrow did, drawn as a node on a line like the conversation trail.
struct MeterEventRow: View {
    let event: MeterEvent
    let last: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: event.kind.symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 18, height: 18).background(event.kind.colour, in: .circle)
                    .shadow(color: event.kind.colour.opacity(0.6), radius: 4)
                if !last { Rectangle().fill(Night.line).frame(width: 1.5).frame(maxHeight: .infinity) }
            }
            .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Night.note)
                    if let handle = event.handle {
                        Text(handle).font(.system(size: 11, design: .monospaced)).foregroundStyle(event.kind.colour).textSelection(.enabled)
                    }
                    Spacer(minLength: 4)
                    Text(event.at.formatted(date: .omitted, time: .standard)).font(.system(size: 11)).foregroundStyle(Night.faint).monospacedDigit()
                }
                if let label = event.label, !label.isEmpty {
                    Text(label).font(.system(size: 11.5, design: event.kind == .recalled ? .default : .monospaced))
                        .foregroundStyle(Night.dim).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
                if let amounts { Text(amounts).font(.system(size: 11)).foregroundStyle(Night.faint).monospacedDigit() }
            }
            .padding(.bottom, 12)
        }
    }

    private var title: String {
        switch event.kind {
        case .kept: return "Kept \(event.tool) output"
        case .shortened: return "Shortened a \(event.tool)"
        case .recalled: return "Handed words back"
        case .steered: return "Steered the summary"
        case .compacted: return "Compacted"
        case .folded: return "Folded"
        case .archived: return "Archived"
        case .resumed: return "Resumed"
        case .expanded: return "Expanded again"
        }
    }

    private var amounts: String? {
        switch event.kind {
        case .kept, .shortened:
            return "\(event.original.formatted()) → \(event.shown.formatted()) characters · \(event.saved.formatted()) kept out"
        case .recalled: return "\(event.shown.formatted()) characters handed back"
        case .steered: return event.shown > 0 ? "\(event.shown.formatted()) characters of guidance" : nil
        case .expanded: return event.shown > 0 ? "\(event.shown.formatted()) characters shown" : nil
        case .archived: return event.shown > 0 ? "\(event.shown.bytesText) kept" : nil
        case .resumed: return event.original > 0 ? "\(event.original.tokensText) tokens of context" : nil
        case .compacted, .folded: return nil
        }
    }
}

/// The lines that carry this session on in another program, each with a copy button.
struct ResumeCommands: View {
    let workspace: Workspace
    let id: String
    let program: SessionText.Program?
    @State private var copied: String?

    private var lines: [(who: String, line: String, tint: Color)] {
        let short = String(id.prefix(8))
        let vault = "'" + workspace.folder.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let burrow = Connections.command.contains(" ") ? "'\(Connections.command)'" : Connections.command
        return [("Claude Code", "/burrow-resume \(short)", SessionText.Program.claudeCode.colour),
                ("Codex", "$burrow-resume \(short)", SessionText.Program.codex.colour),
                ("Burrow chat", "\(burrow) chat \(vault) --resume \(short)", Night.note)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resume in…").font(.system(size: 12, weight: .semibold)).foregroundStyle(Night.dim)
            ForEach(lines, id: \.line) { item in
                HStack(spacing: 10) {
                    Text(item.who).font(.system(size: 11.5, weight: .medium)).foregroundStyle(item.tint).frame(width: 84, alignment: .leading)
                    Text(item.line).font(.system(size: 12, design: .monospaced)).foregroundStyle(Night.note.opacity(0.88))
                        .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.line, forType: .string)
                        copied = item.line
                    } label: {
                        Image(systemName: copied == item.line ? "checkmark" : "doc.on.doc").frame(width: 16)
                    }
                    .buttonStyle(.borderless).foregroundStyle(copied == item.line ? WatchPanel.mint : Night.dim)
                    .help("Copy")
                    .accessibilityLabel("Copy the \(item.who) line")
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 7))
            }
        }
        .padding(14).skyCard(radius: 12)
        .task(id: copied) {
            guard copied != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = nil
        }
    }
}

/// What Burrow does to live sessions, as the person set it. Read-only here for now; `burrow session` changes it.
struct SessionSettingsStrip: View {
    let settings: SessionSettings
    let archiveFolder: String
    let archiveBytes: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3").foregroundStyle(Night.faint).font(.system(size: 11))
            pill("Lean Bash", settings.leanBash)
            pill("Lean Read", settings.leanRead)
            pill("Lean Grep", settings.leanGrep)
            pill("Recall", settings.recall)
            pill("Steer", settings.steer)
            pill("Archive", settings.archive)
            Spacer(minLength: 10)
            Image(systemName: "archivebox").foregroundStyle(Night.faint).font(.system(size: 11))
            Text((archiveFolder as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.head).foregroundStyle(Night.dim)
                .help(archiveFolder)
            Text(archiveBytes.bytesText).foregroundStyle(Night.note.opacity(0.85)).monospacedDigit()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .skyCard(radius: 10)
    }

    private func pill(_ title: String, _ on: Bool) -> some View {
        HStack(spacing: 4) {
            Circle().fill(on ? WatchPanel.mint : Night.faint).frame(width: 5, height: 5)
            Text(title).foregroundStyle(on ? Night.note.opacity(0.9) : Night.faint)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .overlay { Capsule().strokeBorder(on ? WatchPanel.mint.opacity(0.35) : Night.line) }
        .help("\(title) is \(on ? "on" : "off")")
    }
}

// MARK: Small helpers

extension SessionText.Program {
    var title: String { self == .codex ? "Codex" : "Claude Code" }
    var symbol: String { self == .codex ? "curlybraces" : Program.claudeCode.symbol }
    var colour: Color { self == .codex ? Color(red: 0.62, green: 0.80, blue: 1.00) : Program.claudeCode.colour }
}

extension MeterEvent.Kind {
    var symbol: String {
        switch self {
        case .kept: return "tray.and.arrow.down.fill"
        case .shortened: return "scissors"
        case .recalled: return "arrow.uturn.backward"
        case .steered: return "helm"
        case .compacted: return "arrow.down.right.and.arrow.up.left"
        case .folded: return "rectangle.compress.vertical"
        case .archived: return "archivebox.fill"
        case .resumed: return "play.fill"
        case .expanded: return "arrow.up.left.and.arrow.down.right"
        }
    }

    var colour: Color {
        switch self {
        case .kept, .shortened: return Theme.gold
        case .recalled: return Night.conversation
        case .steered, .compacted, .folded: return Night.document
        case .archived: return Color(white: 0.7)
        case .resumed: return WatchPanel.mint
        case .expanded: return Night.cache
        }
    }
}

extension Int {
    /// Tokens the way a person reads them: 950, 12.4K, 182K, 1.2M.
    var tokensText: String { formatted(.number.notation(.compactName).precision(.significantDigits(1...3))) }
}
