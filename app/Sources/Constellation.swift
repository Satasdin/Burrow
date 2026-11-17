import AVKit
import AppKit
import BurrowCore
import CryptoKit
import SwiftUI

// The constellation (D-120): the splash's sparks land as the vault's map, the start window shows each vault as its own
// map, and the vault's home is the live map, where the notes a connected program reads light up gold.

// MARK: Program icons

/// A program's own icon, asked of macOS from the app installed on this Mac. Burrow bundles no one else's logo, and an
/// app that isn't installed falls back to the symbol the page used before.
enum ProgramApp {
    static func bundles(client: String?) -> [String] {
        let name = (client ?? "").lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if name.contains("codex") { return ["com.openai.codex", "com.openai.chat"] }
        if name.contains("claude") { return ["com.anthropic.claudefordesktop"] }
        if name.contains("ollama") { return ["com.electron.ollama"] }
        if name.contains("lmstudio") { return ["ai.elementlabs.lmstudio"] }
        return []
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    /// The app's name on disk, for when its bundle id is not the one we know (an older or newer build).
    static func appName(client: String?) -> String? {
        let name = (client ?? "").lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if name.contains("lmstudio") { return "LM Studio" }
        if name.contains("ollama") { return "Ollama" }
        if name.contains("codex") { return "Codex" }
        if name.contains("claude") { return "Claude" }
        return nil
    }

    @MainActor static func icon(client: String?) -> NSImage? {
        for id in bundles(client: client) {
            if let known = cache[id] { return known }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            cache[id] = icon
            return icon
        }
        guard let app = appName(client: client) else { return nil }
        if let known = cache[app] { return known }
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        for folder in ["/Applications", home] {
            let path = "\(folder)/\(app).app"
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let icon = NSWorkspace.shared.icon(forFile: path)
            cache[app] = icon
            return icon
        }
        return nil
    }
}

extension Program {
    /// The word a program's MCP client name holds, for finding its app.
    var clientWord: String {
        switch self {
        case .claudeCode: return "claude"
        case .lmStudio: return "lmstudio"
        case .ollama: return "ollama"
        default: return rawValue
        }
    }
}

struct ProgramIcon: View {
    let client: String?
    var symbol: String = "app.connected.to.app.below.fill"
    var colour: Color = .secondary
    var size: CGFloat = 22

    var body: some View {
        if let icon = ProgramApp.icon(client: client) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: symbol).font(.system(size: size * 0.62, weight: .semibold)).foregroundStyle(colour)
                .frame(width: size, height: size)
        }
    }
}

// MARK: What programs read, and what the Ledger says about each note

struct ProgramRead: Identifiable {
    let name: String
    let client: String?
    var paths: Set<String>
    var last: Date
    var id: String { name }
}

enum LedgerMark { case inForce, changed, steer }

extension Workspace {
    /// What each connected program looked up lately, from the trail Burrow keeps of every lookup (TrailStep), newest first.
    func programReads(within window: TimeInterval = 600, now: Date = Date()) -> [ProgramRead] {
        var out: [String: ProgramRead] = [:]
        for session in sessions where now.timeIntervalSince(session.updated) < window {
            let name = session.program == .other ? ((session.client ?? "").lowercased().contains("codex") ? "Codex" : (session.client ?? "A program")) : session.program.name
            for step in session.lookups where now.timeIntervalSince(step.at) < window && !step.files.isEmpty {
                var read = out[name] ?? ProgramRead(name: name, client: session.client, paths: [], last: step.at)
                read.paths.formUnion(step.files.map(Self.plainPath))
                read.last = max(read.last, step.at)
                out[name] = read
            }
        }
        return out.values.sorted { $0.last > $1.last }
    }

    /// "notes/a.md:12-40" → "notes/a.md": a read of some lines is a read of the note.
    static func plainPath(_ path: String) -> String {
        guard let colon = path.lastIndex(of: ":"), path[path.index(after: colon)...].allSatisfy({ $0.isNumber || $0 == "-" }) else { return path }
        return String(path[..<colon])
    }

    /// The notes a decision in force rests on (green), the ones whose file changed since (amber), and text written to
    /// steer AI (red): the Watch panel's three states, placed on the map.
    var ledgerMarks: [String: LedgerMark] {
        var marks: [String: LedgerMark] = [:]
        let byID = Dictionary(ledger.commits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let inForce = Set(ledger.inForce)
        for id in inForce { for path in (byID[id]?.cites ?? [:]).keys { marks[path] = .inForce } }
        for (id, files) in ledger.stale where inForce.contains(id) { for path in files { marks[path] = .changed } }
        for line in ledger.flagged { marks[line.path] = .steer }
        return marks
    }
}

extension LedgerMark {
    var colour: Color {
        switch self {
        case .inForce: return WatchPanel.mint
        case .changed: return WatchPanel.amber
        case .steer: return Night.stale
        }
    }
    var label: String {
        switch self {
        case .inForce: return "decision in force"
        case .changed: return "its file changed"
        case .steer: return "written to steer AI"
        }
    }
}

// MARK: Each vault's map, kept for the start window

/// A small copy of a vault's map, saved each time the vault is read, so the start window can show a vault as its own
/// constellation without opening it.
struct MapSnapshot: Codable {
    var vault: String
    var notes: Int
    var links: Int
    var saved: Date
    /// x and y from 0 to 1, the folder's colour number, and the star's size.
    var nodes: [[Float]]
    var edges: [[Int]]

    static var folder: URL { BurrowPlaces.stateFolder.appendingPathComponent("app-maps", isDirectory: true) }

    static func file(for vault: String) -> URL {
        let hash = SHA256.hash(data: Data(vault.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(hash + ".json")
    }

    static func load(_ vault: String) -> MapSnapshot? {
        guard let data = try? Data(contentsOf: file(for: vault)) else { return nil }
        return try? JSONDecoder().decode(MapSnapshot.self, from: data)
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Self.file(for: vault), options: .atomic) }
    }
}

extension Workspace {
    /// The 1,500 best-linked stars and the links between them: enough to look like the vault, small enough to read at once.
    func saveSnapshot() {
        let sim = self.sim
        let (nodes, edges): ([[Float]], [[Int]]) = sim.withPositions {
            guard !sim.nodes.isEmpty, let left = sim.x.min(), let right = sim.x.max(), let top = sim.y.min(), let bottom = sim.y.max() else { return ([], []) }
            let keep = sim.nodes.indices.sorted { sim.nodes[$0].degree > sim.nodes[$1].degree }.prefix(1500)
            let place = Dictionary(uniqueKeysWithValues: keep.enumerated().map { ($1, $0) })
            let span = max(right - left, bottom - top, 1)
            let nodes = keep.map { i -> [Float] in
                [Float((sim.x[i] - left) / span), Float((sim.y[i] - top) / span), Float(sim.nodes[i].group), Float(min(5.5, sqrt(CGFloat(sim.nodes[i].degree)) * 0.8))]
            }
            let edges = sim.edges.compactMap { edge -> [Int]? in
                guard let a = place[edge.a], let b = place[edge.b] else { return nil }
                return [a, b]
            }
            return (nodes, Array(edges.prefix(4000)))
        }
        guard !nodes.isEmpty else { return }
        let snapshot = MapSnapshot(vault: folder.path, notes: stats?.notes ?? 0, links: stats?.links ?? 0, saved: Date(), nodes: nodes, edges: edges)
        Task.detached(priority: .utility) { snapshot.save() }
    }
}

// MARK: The splash

/// When the splash film ends, the map it lands on plays its arrival (the sparks become the vault's stars).
enum Splash {
    @MainActor static var shown = false
    @MainActor static var endedAt: Date?
    static let ended = Notification.Name("BurrowSplashEnded")

    /// A cold launch plays it; a layout check or a recorded tour doesn't, unless BURROW_SPLASH asks.
    static var wanted: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["BURROW_SPLASH"] != nil { return true }
        return environment["BURROW_SNAPSHOT"] == nil && environment["BURROW_RECORD"] == nil && environment["BURROW_TOUR"] == nil
    }

    /// The landing plays right after the film, not every time a page opens.
    @MainActor static var justEnded: Bool { endedAt.map { Date().timeIntervalSince($0) < 2.5 } ?? false }
}

struct SplashView: View {
    let done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black
            if reduceMotion || Brand.splash == nil {
                BurrowWordmark(height: 64).padding(60)
            } else if let url = Brand.splash {
                SplashPlayer(url: url, done: done)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: done)
        .onAppear {
            if reduceMotion || Brand.splash == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: done) }
        }
        .accessibilityElement()
        .accessibilityLabel("Burrow")
        .accessibilityHint("Click to skip")
    }
}

/// Hides the window's title bar and its buttons while the splash plays, and gives them back as they were after. The
/// start window has no toolbar, so hiding the toolbar alone left its plain title bar over the film (D-121).
struct SplashChrome: NSViewRepresentable {
    let hidden: Bool

    final class Coordinator {
        var saved: (transparent: Bool, title: NSWindow.TitleVisibility, fullSize: Bool)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        let hidden = hidden
        // The view is in its window only after this pass.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if hidden, coordinator.saved == nil {
                coordinator.saved = (window.titlebarAppearsTransparent, window.titleVisibility, window.styleMask.contains(.fullSizeContentView))
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                buttons(window, hidden: true)
            } else if !hidden, let saved = coordinator.saved {
                coordinator.saved = nil
                window.titlebarAppearsTransparent = saved.transparent
                window.titleVisibility = saved.title
                if !saved.fullSize { window.styleMask.remove(.fullSizeContentView) }
                buttons(window, hidden: false)
            }
        }
    }

    private func buttons(_ window: NSWindow, hidden: Bool) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(kind)?.isHidden = hidden }
    }
}

/// The film, without controls, filling the window; it reports its end once.
struct SplashPlayer: NSViewRepresentable {
    let url: URL
    let done: () -> Void

    final class PlayerView: NSView {
        let player: AVPlayer
        private var observer: Any?

        init(url: URL, done: @escaping () -> Void) {
            player = AVPlayer(url: url)
            super.init(frame: .zero)
            wantsLayer = true
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.backgroundColor = NSColor.black.cgColor
            self.layer = layer
            observer = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in done() }
            player.play()
        }

        required init?(coder: NSCoder) { nil }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }

    func makeNSView(context: Context) -> PlayerView { PlayerView(url: url, done: done) }
    func updateNSView(_ view: PlayerView, context: Context) {}
    static func dismantleNSView(_ view: PlayerView, coordinator: ()) { view.player.pause() }
}

// MARK: The arrival

/// How far a star is into its landing, 0 to 1. Each lands a little after the last, the brightest first.
struct Landing {
    let start: Date
    let count: Int

    static let length: Double = 1.6

    func progress(_ rank: Int, at time: Date) -> CGFloat {
        let delay = Double(rank) / Double(max(count, 1)) * 0.7
        let t = (time.timeIntervalSince(start) - delay) / (Self.length - 0.7)
        let clamped = min(1, max(0, t))
        return CGFloat(1 - pow(1 - clamped, 3))
    }

    func isRunning(at time: Date) -> Bool { time.timeIntervalSince(start) < Self.length + 0.1 }

    /// Where a star starts: scattered around the middle, where the splash's sparks were.
    static func spark(_ i: Int, around centre: CGPoint, reach: CGFloat) -> CGPoint {
        var seed = UInt64(truncatingIfNeeded: i &* 2_654_435_761 &+ 97)
        func next() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
        }
        let angle = next() * .pi * 2
        let distance = sqrt(next()) * reach
        return CGPoint(x: centre.x + cos(angle) * distance * 1.6, y: centre.y + sin(angle) * distance * 0.5)
    }
}

// MARK: The start window

struct StartPage: View {
    let library: Library
    @State private var landing: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Vaults in temporary folders are left off: test runs made them, and they read as clutter.
    private var vaults: [String] {
        library.choices.filter { path in !["/private/tmp/", "/tmp/", "/private/var/folders/", "/var/folders/"].contains { path.hasPrefix($0) } }
    }
    private var first: String? { vaults.first }
    private var snapshot: MapSnapshot? { first.flatMap(MapSnapshot.load) }

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.016, blue: 0.014).ignoresSafeArea()
            RadialGradient(colors: [Brand.flame.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 700).ignoresSafeArea()
            HStack(spacing: 0) {
                left.frame(maxWidth: 620, alignment: .leading).padding(.leading, 64).padding(.trailing, 24)
                Spacer(minLength: 0)
                right.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { startLanding() }
        .onReceive(NotificationCenter.default.publisher(for: Splash.ended)) { _ in startLanding() }
    }

    private func startLanding() {
        guard !reduceMotion, !(Splash.shown && Splash.endedAt == nil) else { return }
        landing = Date()
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 0) {
            BurrowWordmark(height: 56)
            Text("One memory for every AI on this Mac.").font(.system(size: 22, weight: .medium)).foregroundStyle(.white).padding(.top, 34)
            Text("Your notes and code, read by Claude Code, Codex and Ollama, kept here.")
                .font(.system(size: 15)).foregroundStyle(.white.opacity(0.55)).padding(.top, 8)
            HStack(spacing: 10) {
                if let first {
                    Button { library.open(URL(fileURLWithPath: first)) } label: {
                        Text("Open \(Library.shortName(first, among: vaults))").lineLimit(1).padding(.horizontal, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(SkyTheme.ember.accent)
                }
                Button("New Vault…") { createVault(library) }.buttonStyle(.bordered)
                Button("Open Folder…") { pickVault(library) }.buttonStyle(.bordered)
            }
            .controlSize(.extraLarge).padding(.top, 30)
            if !vaults.isEmpty {
                Text("YOUR VAULTS").font(.system(size: 11, weight: .semibold)).fontWidth(.expanded).kerning(1.2)
                    .foregroundStyle(.white.opacity(0.4)).padding(.top, 44).padding(.bottom, 10)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(vaults.prefix(8).enumerated()), id: \.element) { index, path in
                            VaultRow(path: path, name: Library.shortName(path, among: vaults), isLast: index == 0) {
                                library.open(URL(fileURLWithPath: path))
                            }
                        }
                    }
                }
                .frame(maxHeight: 330)
                .scrollIndicators(.never)
            }
            if let failure = library.failure { Text(failure).foregroundStyle(.red).padding(.top, 12) }
        }
    }

    @ViewBuilder private var right: some View {
        if let snapshot {
            ZStack(alignment: .bottomLeading) {
                MiniMap(snapshot: snapshot, landing: landing).padding(40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Library.shortName(snapshot.vault, among: vaults)).font(.system(size: 18, weight: .semibold)).fontWidth(.expanded).foregroundStyle(.white)
                    Text("\(snapshot.notes.counted("note")) · \(snapshot.links.counted("link")) · \(snapshot.saved.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.5)).monospacedDigit()
                }
                .padding(36)
            }
        } else {
            VStack(spacing: 12) {
                NightSky().frame(maxWidth: .infinity, maxHeight: .infinity).overlay {
                    Text(first == nil ? "Your vault's map appears here." : "Its map appears here after it opens once.")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }
}

struct VaultRow: View {
    let path: String
    let name: String
    let isLast: Bool
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        let snapshot = MapSnapshot.load(path)
        Button(action: open) {
            HStack(spacing: 12) {
                Circle().fill(isLast ? Theme.gold : Color(red: 0.56, green: 0.72, blue: 1)).frame(width: 7, height: 7)
                    .shadow(color: isLast ? Theme.gold : .clear, radius: 5)
                Text(name).font(.system(size: 14.5, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 12)
                Text(detail(snapshot)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.45)).lineLimit(1).truncationMode(.head)
            }
            .padding(.horizontal, 14).frame(height: 40)
            .background(Color.white.opacity(hovering ? 0.09 : (isLast ? 0.06 : 0.03)), in: .rect(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(path)
    }

    private func detail(_ snapshot: MapSnapshot?) -> String {
        let place = ((path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath
        guard let snapshot else { return place }
        return "\(snapshot.notes.counted("note")) · \(snapshot.saved.formatted(.relative(presentation: .named)))"
    }
}

/// A vault's saved map, drawn the way the Map draws it: links faint, stars in their folder's colour with a halo.
struct MiniMap: View {
    let snapshot: MapSnapshot
    let landing: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let arrival = landing.map { Landing(start: $0, count: snapshot.nodes.count) }
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || !(arrival?.isRunning(at: Date()) ?? false))) { time in
            Canvas { context, size in
                let side = min(size.width, size.height)
                let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                func place(_ i: Int) -> CGPoint {
                    let node = snapshot.nodes[i]
                    let spot = CGPoint(x: origin.x + CGFloat(node[0]) * side, y: origin.y + CGFloat(node[1]) * side)
                    guard let arrival, !reduceMotion else { return spot }
                    let p = arrival.progress(i, at: time.date)
                    let spark = Landing.spark(i, around: centre, reach: side * 0.35)
                    return CGPoint(x: spark.x + (spot.x - spark.x) * p, y: spark.y + (spot.y - spark.y) * p)
                }
                var glow = context
                glow.blendMode = .plusLighter
                let settled = arrival.map { $0.progress(snapshot.nodes.count - 1, at: time.date) } ?? 1
                var lines = Path()
                for edge in snapshot.edges where edge.count == 2 {
                    lines.move(to: place(edge[0]))
                    lines.addLine(to: place(edge[1]))
                }
                glow.stroke(lines, with: .color(.white.opacity(0.07 * settled)), lineWidth: 0.6)
                for i in snapshot.nodes.indices {
                    let node = snapshot.nodes[i]
                    let spot = place(i)
                    let group = Int(node[2])
                    let landed = arrival.map { $0.progress(i, at: time.date) } ?? 1
                    // In flight a star is a spark: small and gold. Landed, it takes its folder's colour.
                    let colour = landed < 1 ? Theme.gold : (group < Theme.clusters.count ? Theme.clusters[group] : Theme.otherCluster)
                    let radius = (1.6 + CGFloat(node[3])) * (side / 700)
                    let halo = radius * 4
                    glow.fill(Path(ellipseIn: CGRect(x: spot.x - halo, y: spot.y - halo, width: halo * 2, height: halo * 2)),
                              with: .radialGradient(Gradient(colors: [colour.opacity(0.35), .clear]), center: spot, startRadius: 0, endRadius: halo))
                    glow.fill(Path(ellipseIn: CGRect(x: spot.x - radius, y: spot.y - radius, width: radius * 2, height: radius * 2)), with: .color(colour.opacity(0.95)))
                }
            }
        }
        .accessibilityLabel("Map of \(snapshot.notes) notes")
    }
}

@MainActor
func createVault(_ library: Library) {
    let panel = NSSavePanel()
    panel.prompt = "Create Vault"
    panel.nameFieldStringValue = "Notes"
    panel.message = "Name a new folder for your vault. Nothing leaves this Mac."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        library.open(url)
    } catch {
        library.failure = "Burrow could not make that folder: \(error.localizedDescription)"
    }
}

// MARK: The vault's home: the live map

struct HomePage: View {
    let workspace: Workspace
    @State private var landing: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let reads = workspace.programReads()
        let marks = workspace.ledgerMarks
        ZStack(alignment: .topLeading) {
            GraphCanvas(workspace: workspace, compact: false, live: true, landing: landing)
            header.padding(28)
        }
        .overlay(alignment: .bottomLeading) { ReadingChips(reads: reads).padding(22) }
        .overlay(alignment: .bottomTrailing) { if !marks.isEmpty || !reads.isEmpty { MapKey(marks: Set(marks.values), reading: !reads.isEmpty).padding(22) } }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .onAppear { if Splash.justEnded, !reduceMotion { landing = Date() } }
        .onReceive(NotificationCenter.default.publisher(for: Splash.ended)) { _ in if !reduceMotion { landing = Date() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                BurrowMark(size: 30)
                Text(workspace.name).font(.system(size: 30, weight: .bold)).fontWidth(.expanded).foregroundStyle(.white)
            }
            if let stats = workspace.stats {
                Text("\(stats.notes.counted("note")) · \(stats.links.counted("link")) · \(workspace.ledger.inForce.count.counted("rule")) in force")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.55)).monospacedDigit()
            } else if let progress = workspace.progress {
                Text(progress).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
            }
            HStack(spacing: 8) {
                Button { Task { await workspace.newNote() } } label: { Label("New Note", systemImage: "square.and.pencil") }
                Button { workspace.paletteOpen = true } label: { Label("Quick Open", systemImage: "magnifyingglass") }
                Button { workspace.go(.library(.all)) } label: { Label("Library", systemImage: "square.grid.2x2") }
                Button { workspace.go(.ledger(nil)) } label: { Label("Ledger", systemImage: "books.vertical") }
            }
            .controlSize(.regular).padding(.top, 6)
        }
    }
}

/// "Claude Code is reading · 6 notes · just now": one line per program that looked something up in the last ten minutes.
struct ReadingChips: View {
    let reads: [ProgramRead]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { time in
            VStack(alignment: .leading, spacing: 8) {
                ForEach(reads.prefix(3).reversed()) { read in
                    let fresh = time.date.timeIntervalSince(read.last) < 60
                    HStack(spacing: 10) {
                        ProgramIcon(client: read.client, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(fresh ? "\(read.name) is reading" : "\(read.name) read").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            Text("\(read.paths.count.counted("note")) · \(read.last.formatted(.relative(presentation: .named)))")
                                .font(.system(size: 11.5)).foregroundStyle(Theme.gold).monospacedDigit()
                        }
                    }
                    .padding(.leading, 8).padding(.trailing, 16).padding(.vertical, 7)
                    .background(Color(red: 0.1, green: 0.08, blue: 0.06).opacity(0.92), in: .capsule)
                    .overlay { Capsule().strokeBorder(Theme.gold.opacity(fresh ? 0.6 : 0.25)) }
                }
            }
        }
    }
}

struct MapKey: View {
    let marks: Set<LedgerMark>
    let reading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if reading { row(Circle().fill(Theme.gold).frame(width: 9, height: 9).shadow(color: Theme.gold, radius: 4), "read by a program") }
            ForEach([LedgerMark.inForce, .changed, .steer].filter(marks.contains), id: \.self) { mark in
                row(Circle().strokeBorder(mark.colour, lineWidth: 2).frame(width: 13, height: 13), mark.label)
            }
        }
        .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color(red: 0.06, green: 0.05, blue: 0.045).opacity(0.9), in: .rect(cornerRadius: 12))
    }

    private func row(_ dot: some View, _ text: String) -> some View {
        HStack(spacing: 9) { dot.frame(width: 14); Text(text) }
    }
}
