import Foundation

/// One vault reading another, one way, read-only (D-97). Kept in Burrow's own folder on this Mac, keyed by the reading
/// vault's real path, never in a vault folder (D-100): a vault that came from someone else can't bring bridges with it.
public struct Bridge: Sendable, Hashable, Codable, Identifiable {
    public var id: String { name }
    /// How this vault calls the other one. Every path through the bridge starts with it: `Work › notes/plan.md`.
    public let name: String
    public let path: String
    /// True when the other vault's decisions in force come over too. Off unless asked for (D-97).
    public var withLedger: Bool
    /// False for a project indexed without `--vault`, whose notes live in its store.
    public var everything: Bool
    public var url: URL { URL(fileURLWithPath: path) }

    public init(name: String, path: String, withLedger: Bool = false, everything: Bool = true) {
        self.name = name
        self.path = path
        self.withLedger = withLedger
        self.everything = everything
    }

    /// Between a bridge's name and the path inside the other vault.
    public static let separator = " › "
    public func label(_ inner: String) -> String { name + Bridge.separator + inner }

    /// A name a path can start with: no slashes, no separator, no control characters, one line.
    public static func cleanName(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && !"/\\›:".unicodeScalars.contains($0) }
        return String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

/// The other vault's files as this one shows them: each path labelled with the bridge's name.
public struct BridgedShelf: Sendable {
    public let bridge: Bridge
    public let files: [MapFile]
    /// The other vault's linked folders, to find a labelled file on disk.
    public let linked: [LinkedFolder]
    /// Why the other vault could not be read, when it couldn't.
    public let problem: String?
}

/// Every vault's bridges, in one file in Burrow's own folder (D-100). Only `burrow bridge`, `burrow unbridge` and the
/// app's Bridges sheet write it, so only the person on this Mac makes a bridge.
struct BridgeStore: Codable {
    /// Bridges by the reading vault's folder, symlinks resolved.
    var vaults: [String: [Bridge]] = [:]
    /// Vaults already told that a bridges file inside their folder is ignored, so each is told once.
    var noticed: [String] = []

    static func file(in folder: URL) -> URL { folder.appendingPathComponent("bridges.json") }

    /// An empty list when there is no file yet. Throws when there is one that can't be read, so a save never writes
    /// over it.
    static func load(in folder: URL) throws -> BridgeStore {
        let url = file(in: folder)
        guard FileManager.default.fileExists(atPath: url.path) else { return BridgeStore() }
        do {
            return try JSONDecoder().decode(BridgeStore.self, from: Data(contentsOf: url))
        } catch {
            throw NoteProblem(description: "Burrow's list of bridges (\(url.path)) can't be read, so it was left as it is: \(error.localizedDescription)")
        }
    }

    func save(in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: Self.file(in: folder), options: .atomic)
    }
}

extension Vault {
    /// This vault's place in Burrow's list of bridges: its folder with symlinks resolved, so two vaults with the same
    /// name in different places never share bridges, and a vault opened through a symlink is the same vault.
    var bridgeKey: String { root.standardizedFileURL.resolvingSymlinksInPath().path }

    /// This vault's bridges, from Burrow's own folder only (D-100). A `bridges.json` inside the vault folder is never
    /// read: a shared, downloaded or cloned vault could carry one pointing at the person's other vaults. A vault read
    /// through a bridge has none: bridges are never followed onwards (D-97).
    public func bridges() -> [Bridge] {
        guard !readOnly, let saved = try? BridgeStore.load(in: stateFolder) else { return [] }
        return saved.vaults[bridgeKey] ?? []
    }

    private func saveBridges(_ all: [Bridge]) throws {
        var saved = try BridgeStore.load(in: stateFolder)
        saved.vaults[bridgeKey] = all.isEmpty ? nil : all
        try saved.save(in: stateFolder)
        database.locked { bridgedVaults = [:] }
    }

    /// A bridges file inside this vault's folder: where bridges were kept before D-100, or where someone else put one.
    /// Burrow never follows it.
    public var bridgesFileInVault: URL? {
        let inside = store.appendingPathComponent("bridges.json")
        return FileManager.default.fileExists(atPath: inside.path) ? inside : nil
    }

    /// Said once per vault, by `burrow bridge list`, when its folder holds a bridges file. Nothing is imported from it:
    /// the person adds the bridges they made again, with `burrow bridge`.
    public func takeBridgesInVaultNotice() -> String? {
        guard !readOnly, let inside = bridgesFileInVault else { return nil }
        let saved = try? BridgeStore.load(in: stateFolder)
        if saved?.noticed.contains(bridgeKey) == true { return nil }
        // Remembered only when the list could be read: an unreadable list is never written over.
        if var known = saved {
            known.noticed.append(bridgeKey)
            try? known.save(in: stateFolder)
        }
        return "Found bridges written inside this vault folder (\(inside.path)). They are ignored: Burrow keeps bridges in its own folder on this Mac, so a vault from someone else can't bring any with it. If you made them, add them again with: burrow bridge \(root.path) <other-vault>"
    }

    /// Lets this vault read another. The other vault is only read: nothing is written into its folder, ever.
    /// Bridging the same vault again changes its name or whether its decisions come over.
    @discardableResult
    public func addBridge(to other: URL, name: String? = nil, withLedger: Bool = false) throws -> Bridge {
        guard !readOnly else { throw NoteProblem(description: "A vault read through a bridge can't have bridges of its own.") }
        let there = other.standardizedFileURL.resolvingSymlinksInPath().path
        let here = root.resolvingSymlinksInPath().path
        guard there != here else { throw NoteProblem(description: "A vault can't bridge to itself.") }
        guard !there.hasPrefix(here + "/"), !here.hasPrefix(there + "/") else {
            throw NoteProblem(description: "One of these vaults is inside the other. Link the folder instead: burrow link.")
        }
        let otherStore = URL(fileURLWithPath: there).appendingPathComponent(".burrow")
        guard FileManager.default.fileExists(atPath: otherStore.appendingPathComponent("index.sqlite").path) else {
            throw NoteProblem(description: "\(there) is not a Burrow vault yet. Make it one first: burrow vault new \(there)")
        }
        var all = bridges()
        let everything = !FileManager.default.fileExists(atPath: otherStore.appendingPathComponent("notes").path)
        let asked = name.map(Bridge.cleanName)
        if let asked, asked.isEmpty { throw NoteProblem(description: "A bridge's name needs some letters.") }
        if let index = all.firstIndex(where: { $0.path == there }) {
            let chosen = asked ?? all[index].name
            if all.contains(where: { $0.name == chosen && $0.path != there }) { throw NoteProblem(description: "There is already a bridge called \(chosen).") }
            all[index] = Bridge(name: chosen, path: there, withLedger: withLedger, everything: everything)
            try saveBridges(all)
            return all[index]
        }
        let base = asked ?? Bridge.cleanName(BurrowConfig.forVault(store: otherStore).value("vault.name") ?? URL(fileURLWithPath: there).lastPathComponent)
        var chosen = base.isEmpty ? "Bridged" : base
        if asked != nil, all.contains(where: { $0.name == chosen }) { throw NoteProblem(description: "There is already a bridge called \(chosen).") }
        var attempt = 2
        while all.contains(where: { $0.name == chosen }) {
            chosen = "\(base) \(attempt)"
            attempt += 1
        }
        let bridge = Bridge(name: chosen, path: there, withLedger: withLedger, everything: everything)
        all.append(bridge)
        try saveBridges(all)
        return bridge
    }

    /// Takes a bridge away. The other vault is not touched.
    @discardableResult
    public func removeBridge(_ name: String) throws -> Bridge {
        let all = bridges()
        guard let gone = all.first(where: { $0.name == name || $0.name.lowercased() == name.lowercased() }) else {
            throw NoteProblem(description: "There is no bridge called \(name).\(all.isEmpty ? "" : " Bridges: " + all.map(\.name).joined(separator: ", "))")
        }
        try saveBridges(all.filter { $0.name != gone.name })
        return gone
    }

    /// The vault behind a bridge, opened to read and kept open. Nil when it can't be read: moved, or never indexed.
    public func bridgedVault(_ bridge: Bridge) -> Vault? {
        let key = bridge.name + "\u{0}" + bridge.path
        return database.locked {
            if let open = bridgedVaults[key] { return open }
            guard let opened = try? Vault(readingOnly: bridge.url, everything: bridge.everything) else { return nil }
            // Its linked folders' approvals are read from the same place as this vault's (D-101).
            opened.stateFolder = stateFolder
            bridgedVaults[key] = opened
            return opened
        }
    }

    /// A labelled path split into its bridge and the path inside that vault. Nil for this vault's own paths, and always
    /// nil in a vault read through a bridge, so `Work › Team › x.md` can never reach a third vault.
    public func bridged(_ path: String) -> (bridge: Bridge, inner: String)? {
        guard !readOnly, let range = path.range(of: Bridge.separator) else { return nil }
        let name = String(path[..<range.lowerBound])
        let inner = String(path[range.upperBound...])
        guard !inner.isEmpty, let bridge = bridges().first(where: { $0.name == name }) else { return nil }
        return (bridge, inner)
    }

    /// Where a labelled path is on disk, for previews and Show in Finder.
    public func bridgedFileURL(_ path: String) -> URL? {
        guard let (bridge, inner) = bridged(path), let other = bridgedVault(bridge) else { return nil }
        return other.location(of: inner)?.url
    }

    /// Every bridged vault's files, labelled, for the app's Library and for opening a labelled path.
    public func bridgedShelves() -> [BridgedShelf] {
        bridges().map { bridge in
            guard let other = bridgedVault(bridge) else {
                return BridgedShelf(bridge: bridge, files: [], linked: [], problem: "\(bridge.path) can't be read: it was moved, or it has no index.")
            }
            do {
                let waiting = other.unapprovedLinkNames()
                let files = try other.projectMap().files.filter { !other.isInUnapprovedLink($0.path, waiting: waiting) }.map { MapFile(path: bridge.label($0.path), isNote: $0.isNote, cluster: bridge.name, chunks: $0.chunks) }
                return BridgedShelf(bridge: bridge, files: files, linked: other.linkedFolders(), problem: nil)
            } catch {
                return BridgedShelf(bridge: bridge, files: [], linked: [], problem: "\(bridge.path) can't be read: \(error)")
            }
        }
    }

    /// Word search over this vault and every bridged one, for the app's search box. Bridged lines come after this vault's.
    public func searchLinesAcrossBridges(_ query: String, scope: String? = nil, limit: Int = 200) throws -> [FoundLine] {
        if let scope, let bridge = bridges().first(where: { $0.name == scope }) {
            guard let other = bridgedVault(bridge) else { return [] }
            return other.withoutUnapprovedLinks((try? other.searchLines(query, limit: limit)) ?? []).map { FoundLine(path: bridge.label($0.path), line: $0.line, text: $0.text) }
        }
        var out = try searchLines(query, scope: scope, limit: limit)
        guard scope == nil else { return out }
        for bridge in bridges() where out.count < limit {
            guard let other = bridgedVault(bridge), let found = try? other.searchLines(query, limit: limit - out.count) else { continue }
            out += other.withoutUnapprovedLinks(found).map { FoundLine(path: bridge.label($0.path), line: $0.line, text: $0.text) }
        }
        return out
    }

    // MARK: Finding through bridges

    /// A bridged vault joins a question's results only when its closest match is within this of the best one, so a
    /// vault that knows nothing about the question does not crowd out one that does.
    static let bridgeMargin: Float = 0.12

    /// Finds what to show the model, here and in every bridged vault (D-97). Each vault is searched by its own index;
    /// the results are taken in turn, best-matching vault first, until the budget is used, and every bridged path is
    /// labelled with its vault. A scope naming a bridge searches that vault alone.
    public func retrieve(_ question: String, mode: Mode, budget: Budget = Budget(), embedder: Embedder? = nil, scope: String? = nil) async throws -> Retrieved {
        let all = bridges()
        guard mode != .none, !all.isEmpty else { return try await retrieveHere(question, mode: mode, budget: budget, embedder: embedder, scope: scope) }
        let started = Date()
        var targets: [(bridge: Bridge, scope: String?)] = []
        var here = true
        if let scope {
            if let whole = all.first(where: { $0.name == scope }) {
                targets = [(whole, nil)]
            } else if let (bridge, inner) = bridged(scope) {
                targets = [(bridge, inner)]
            } else {
                return try await retrieveHere(question, mode: mode, budget: budget, embedder: embedder, scope: scope)
            }
            here = false
        } else {
            targets = all.map { ($0, nil) }
        }

        var sources: [(bridge: Bridge?, found: Retrieved)] = []
        if here { sources.append((nil, try await retrieveHere(question, mode: mode, budget: budget, embedder: embedder, scope: nil))) }
        let width = embedder == nil ? 0 : (try await questionVector(question, embedder: embedder))?.count ?? 0
        for target in targets {
            guard let other = bridgedVault(target.bridge) else { continue }
            // Meaning search only where the other vault's vectors are the same width as the question's.
            let usable = width > 0 && other.vectorDimension() == width
            guard let found = try? await other.retrieveHere(question, mode: mode, budget: budget, embedder: usable ? embedder : nil, scope: target.scope) else { continue }
            sources.append((target.bridge, Self.labelled(other.withoutUnapprovedLinks(found), target.bridge)))
        }
        return Self.merged(sources.map(\.found), budget: budget, mode: mode, seconds: Date().timeIntervalSince(started))
    }

    /// A bridged vault's finds without what its index holds from a linked folder not approved for it on this Mac
    /// (D-101): an index built before approvals existed could still hold one, and a vault read through a bridge is
    /// never changed, so it is left out here instead.
    func withoutUnapprovedLinks(_ found: Retrieved) -> Retrieved {
        let waiting = unapprovedLinkNames()
        guard !waiting.isEmpty else { return found }
        let kept = found.excerpts.filter { piece in
            guard !isInUnapprovedLink(piece.path, waiting: waiting) else { return false }
            if case let .link(from, _, _) = piece.reason { return !isInUnapprovedLink(from, waiting: waiting) }
            return true
        }
        return Retrieved(mode: found.mode, excerpts: kept, seconds: found.seconds, signal: found.signal)
    }

    func withoutUnapprovedLinks(_ lines: [FoundLine]) -> [FoundLine] {
        let waiting = unapprovedLinkNames()
        guard !waiting.isEmpty else { return lines }
        return lines.filter { !isInUnapprovedLink($0.path, waiting: waiting) }
    }

    static func labelled(_ found: Retrieved, _ bridge: Bridge) -> Retrieved {
        let excerpts = found.excerpts.map { piece -> Excerpt in
            let reason: Reason
            switch piece.reason {
            case .search: reason = .search
            case let .link(from, kind, via): reason = .link(from: bridge.label(from), kind: kind, via: via)
            }
            return Excerpt(path: bridge.label(piece.path), startLine: piece.startLine, endLine: piece.endLine, text: piece.text,
                           reason: reason, isNote: piece.isNote, section: piece.section)
        }
        return Retrieved(mode: found.mode, excerpts: excerpts, seconds: found.seconds, signal: found.signal)
    }

    /// Several vaults' results as one: best-matching vault first, one excerpt from each in turn, within the budget.
    static func merged(_ sources: [Retrieved], budget: Budget, mode: Mode, seconds: Double) -> Retrieved {
        let matched = sources.filter { !$0.excerpts.isEmpty }
        let best = matched.compactMap(\.signal.nearest).max()
        let joining = matched.enumerated().filter { _, found in
            guard let best, let nearest = found.signal.nearest else { return true }
            return nearest >= best - bridgeMargin
        }.sorted { a, b in
            switch (a.element.signal.nearest, b.element.signal.nearest) {
            case let (x?, y?) where x != y: return x > y
            default: return a.offset < b.offset
            }
        }.map(\.element)
        var excerpts: [Excerpt] = []
        var used = 0
        var turn = 0
        var more = true
        while more {
            more = false
            for found in joining where turn < found.excerpts.count {
                more = true
                let piece = found.excerpts[turn]
                guard used + piece.text.count <= budget.characters else { continue }
                excerpts.append(piece)
                used += piece.text.count
            }
            turn += 1
        }
        let signal = Signal(nearest: sources.compactMap(\.signal.nearest).max(), wordMatches: sources.reduce(0) { $0 + $1.signal.wordMatches })
        return Retrieved(mode: mode, excerpts: excerpts, seconds: seconds, signal: signal)
    }
}
