import Foundation

/// A folder a vault's list names, as this Mac sees it: whether the person here has said yes to it (D-101).
public struct LinkState: Sendable, Hashable, Identifiable {
    public var id: String { folder.name + "\u{0}" + folder.path }
    /// The entry as the vault's list has it. Its name and path come from a file someone else may have written: print them
    /// only through `Printable.clean` (D-104).
    public let folder: LinkedFolder
    /// True once the person on this Mac approved this folder for this vault, or linked it here themselves, and it is not
    /// a folder Burrow refuses to follow.
    public let approved: Bool
    /// The folder with symlinks resolved: what an approval names, and the only path a reader is given (D-104).
    public let realPath: String
    public let exists: Bool
    /// Why Burrow never follows this entry, approved or not (D-104): the vault itself, a folder inside it, its store or a
    /// folder holding the vault or its store, or a name or path with control characters. Nil for an ordinary folder.
    public let refusal: String?
    /// True when the folder named is a symlink to somewhere else. macOS's own /private prefix (/tmp, /var) doesn't count,
    /// either way round: resolving adds it for /var and takes it off for /private/tmp.
    public var leadsElsewhere: Bool { !Self.samePlace(realPath, folder.path) }

    public static func samePlace(_ one: String, _ other: String) -> Bool {
        one == other || one == "/private" + other || "/private" + one == other
    }
    /// The entry as a reader gets it: its name, and the real path that was checked.
    public var resolved: LinkedFolder { LinkedFolder(name: folder.name, path: realPath) }
}

/// Text from a file someone else may have written, made safe to print to a terminal or show in a window (D-104).
public enum Printable {
    /// True for a character that could move the cursor, rewrite the screen, ring the bell or reorder what is shown:
    /// C0 controls (ESC, BEL, newline and the rest), DEL, C1 controls, Unicode bidi marks, embeddings, overrides and
    /// isolates, and the line and paragraph separators.
    public static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F, 0x7F...0x9F: return true
        case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069, 0x2028, 0x2029: return true
        default: return false
        }
    }

    public static func hasControl(_ text: String) -> Bool { text.unicodeScalars.contains(where: isControl) }

    /// The text with every such character taken out.
    public static func clean(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        out.append(contentsOf: text.unicodeScalars.filter { !isControl($0) })
        return String(out)
    }

    /// A word as a shell reads it back, cleaned: left alone when it is plain, otherwise in single quotes, so a path
    /// pasted from a suggested command can never run anything (`$(…)`, backticks, `;`).
    public static func shellWord(_ text: String) -> String {
        let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./~@%+=:,-")
        let clean = clean(text)
        if !clean.isEmpty, !clean.hasPrefix("~"), clean.unicodeScalars.allSatisfy(plain.contains) { return clean }
        return "'" + clean.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

/// Every vault's approved linked folders, in one file in Burrow's own folder, never in a vault (D-101). A vault's list of
/// linked folders (`.burrow/folders.json`) is a file in its folder, so a vault from someone else can carry one pointing
/// anywhere on this Mac. Burrow follows a folder on that list only when this file says the person here approved it.
struct LinkApprovalStore: Codable {
    /// Approved folders by vault, both with symlinks resolved.
    var vaults: [String: [String]] = [:]

    static func file(in folder: URL) -> URL { folder.appendingPathComponent("linked-folders.json") }

    /// Nothing approved when there is no file yet. Throws when there is one that can't be read, so a save never writes
    /// over it; reading then approves nothing.
    static func load(in folder: URL) throws -> LinkApprovalStore {
        let url = file(in: folder)
        guard FileManager.default.fileExists(atPath: url.path) else { return LinkApprovalStore() }
        do {
            return try JSONDecoder().decode(LinkApprovalStore.self, from: Data(contentsOf: url))
        } catch {
            throw NoteProblem(description: "Burrow's list of approved linked folders (\(url.path)) can't be read, so it was left as it is: \(error.localizedDescription)")
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
    /// A path with symlinks resolved, as approvals name folders and vaults.
    public static func realPath(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path }

    /// True when `path` is `folder` or inside it. Both real paths.
    static func isWithin(_ path: String, _ folder: String) -> Bool {
        path == folder || folder == "/" || path.hasPrefix(folder + "/")
    }

    /// Why Burrow never follows a linked folder at this real path for this vault, or nil (D-104). Reading the vault itself,
    /// a folder inside it, its store (the index and the Ledger), or a folder that holds the vault or the store, would hand
    /// a connected program Burrow's own files or the vault twice over, whoever approved it.
    func refusal(name: String, path: String, real: String) -> String? {
        if Printable.hasControl(name) || Printable.hasControl(path) {
            return "its name or path has control characters"
        }
        let here = Self.realPath(root.path), kept = Self.realPath(store.path)
        if real == here { return "it is this vault itself" }
        if Self.isWithin(here, real) { return "it holds this vault" }
        if Self.isWithin(real, kept) || Self.isWithin(kept, real) { return "it is or holds Burrow's own store for this vault" }
        if Self.isWithin(real, here) { return "it is inside this vault already" }
        return nil
    }

    private var linkedFile: URL { store.appendingPathComponent("folders.json") }

    /// Every folder this vault's list names, approved or not. Read to show the list and to ask, never to open a folder.
    public func listedLinkedFolders() -> [LinkedFolder] {
        guard let data = try? Data(contentsOf: linkedFile) else { return [] }
        return (try? JSONDecoder().decode([LinkedFolder].self, from: data)) ?? []
    }

    /// The folders this vault's list names, each with whether the person on this Mac has approved it for this vault.
    public func linkStates() -> [LinkState] {
        let listed = listedLinkedFolders()
        guard !listed.isEmpty else { return [] }
        let approved = Set((try? LinkApprovalStore.load(in: stateFolder))?.vaults[bridgeKey] ?? [])
        return listed.map { folder in
            let real = Self.realPath(folder.path)
            var isFolder: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: real, isDirectory: &isFolder) && isFolder.boolValue
            let refused = refusal(name: folder.name, path: folder.path, real: real)
            return LinkState(folder: folder, approved: refused == nil && approved.contains(real), realPath: real, exists: exists, refusal: refused)
        }
    }

    /// The linked folders Burrow reads: only those the person on this Mac approved for this vault (D-101). Every reader
    /// goes through this: indexing, search, read, Ask, the MCP tools, `burrow check` and the gate, and the app.
    /// None for a vault read through a bridge (D-100): no file outside its own folder is opened through the bridge.
    /// Each comes with the real path its approval was checked against, never the path the vault's list gives (D-104): a
    /// symlink on the list pointed somewhere else after approval resolves to a folder not approved and is skipped again,
    /// instead of being read through.
    public func linkedFolders() -> [LinkedFolder] {
        guard !readOnly else { return [] }
        return linkStates().filter(\.approved).map(\.resolved)
    }

    /// Folders on this vault's list that the person on this Mac has not approved. They are skipped everywhere.
    public func linksAwaitingApproval() -> [LinkedFolder] {
        linkStates().filter { !$0.approved }.map(\.folder)
    }

    /// The entries on this vault's list that `which` names, by name, listed path or real path, or every one with nil, less
    /// the folders Burrow refuses (D-104). Throws for a name not on the list, or for one Burrow refuses.
    public func linksToApprove(_ which: [String]? = nil) throws -> [LinkState] {
        guard !readOnly else { throw NoteProblem(description: "A vault read through a bridge has no linked folders of its own.") }
        let states = linkStates()
        guard let which else { return states.filter { $0.refusal == nil } }
        func names(_ asked: String, _ state: LinkState) -> Bool {
            asked.lowercased() == state.folder.name.lowercased() || asked == state.folder.path || Self.realPath(asked) == state.realPath
        }
        let chosen = states.filter { state in which.contains { names($0, state) } }
        let missing = which.filter { asked in !chosen.contains { names(asked, $0) } }
        if !missing.isEmpty {
            let listed = states.map { Printable.clean($0.folder.name) }.joined(separator: ", ")
            throw NoteProblem(description: "\(missing.map(Printable.clean).joined(separator: ", ")) is not on this vault's list of linked folders.\(states.isEmpty ? " It links none." : " It links: " + listed)")
        }
        // An entry Burrow refuses is left out, so a planted one naming the same folder can't block approving it; a word
        // that names only refused entries is an error.
        for asked in which where !chosen.contains(where: { names(asked, $0) && $0.refusal == nil }) {
            if let refused = chosen.first(where: { names(asked, $0) }), let why = refused.refusal {
                throw NoteProblem(description: "\(Printable.clean(refused.realPath)) can't be approved: \(why).")
            }
        }
        return chosen.filter { $0.refusal == nil }
    }

    /// Approves exactly these entries, as they were shown to the person: their real paths, and only while the list still
    /// names each with the same real path (D-104). A list changed between showing and saying yes approves nothing.
    @discardableResult
    public func approve(_ shown: [LinkState]) throws -> [LinkState] {
        guard !readOnly else { throw NoteProblem(description: "A vault read through a bridge has no linked folders of its own.") }
        let now = linkStates()
        for state in shown {
            guard let current = now.first(where: { $0.folder == state.folder && $0.realPath == state.realPath }) else {
                throw NoteProblem(description: "This vault's list of linked folders changed since it was shown, so nothing was approved. Look again and approve what it lists now.")
            }
            if let why = current.refusal { throw NoteProblem(description: "\(Printable.clean(current.realPath)) can't be approved: \(why).") }
        }
        try approve(shown.map(\.realPath))
        return shown
    }

    /// Approves folders on this vault's list, by name or path, or every one with nil. Only the person approves: the
    /// command line's `burrow link approve`, run in their own terminal and confirmed there (D-104), and the app's sheet
    /// call this, never a connected program.
    @discardableResult
    public func approveLinks(_ which: [String]? = nil) throws -> [LinkedFolder] {
        try approve(try linksToApprove(which)).map(\.folder)
    }

    /// Writes approvals for this vault to Burrow's own folder.
    func approve(_ realPaths: [String]) throws {
        guard !realPaths.isEmpty else { return }
        var saved = try LinkApprovalStore.load(in: stateFolder)
        var mine = saved.vaults[bridgeKey] ?? []
        for path in realPaths where !mine.contains(path) { mine.append(path) }
        saved.vaults[bridgeKey] = mine.sorted()
        try saved.save(in: stateFolder)
        database.locked { forgetCaches() }
    }

    private func forgetApproval(_ realPath: String) throws {
        var saved = try LinkApprovalStore.load(in: stateFolder)
        guard var mine = saved.vaults[bridgeKey], mine.contains(realPath) else { return }
        mine.removeAll { $0 == realPath }
        saved.vaults[bridgeKey] = mine.isEmpty ? nil : mine
        try saved.save(in: stateFolder)
    }

    /// Adds a folder to the vault under a name of its own. Burrow reads it and never changes it. The person linking it
    /// here approves it in the same step (D-101), so a link made on this Mac works with nothing more to do.
    /// - Parameter expected: the real path shown to the person when they said yes (D-104). If the folder now resolves
    ///   somewhere else, nothing is linked.
    @discardableResult
    public func linkFolder(_ url: URL, expected: String? = nil) throws -> LinkedFolder {
        guard !readOnly else { throw NoteProblem(description: "A vault read through a bridge can't link folders.") }
        var folders = listedLinkedFolders()
        let path = url.standardizedFileURL.path
        let real = Self.realPath(path)
        let here = Self.realPath(root.path)
        guard path != root.path, !path.hasPrefix(root.path + "/"), real != here, !real.hasPrefix(here + "/") else {
            throw NoteProblem(description: "That folder is already inside this vault.")
        }
        if let why = refusal(name: url.lastPathComponent, path: path, real: real) {
            throw NoteProblem(description: "\(Printable.clean(real)) can't be linked: \(why).")
        }
        if let expected, expected != real {
            throw NoteProblem(description: "\(Printable.clean(path)) now leads to \(Printable.clean(real)), not the folder you said yes to, so nothing was linked.")
        }
        if let existing = folders.first(where: { $0.path == path }) {
            try approve([real])
            return existing
        }
        let base = url.lastPathComponent
        var name = base
        var attempt = 2
        let taken = Set(folders.map(\.name))
        while taken.contains(name) || FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path) {
            name = "\(base) \(attempt)"
            attempt += 1
        }
        // Approved first: if Burrow's own folder can't be written, the vault's list is left as it was.
        try approve([real])
        let folder = LinkedFolder(name: name, path: path)
        folders.append(folder)
        try JSONEncoder().encode(folders).write(to: linkedFile, options: .atomic)
        return folder
    }

    public func unlinkFolder(_ name: String) throws {
        let all = listedLinkedFolders()
        for gone in all where gone.name == name {
            // Forgotten only when no other entry on the list names the same folder.
            let real = Self.realPath(gone.path)
            if !all.contains(where: { $0.name != name && Self.realPath($0.path) == real }) { try? forgetApproval(real) }
        }
        try JSONEncoder().encode(all.filter { $0.name != name }).write(to: linkedFile, options: .atomic)
    }

    /// True for a path that would be a folder on this vault's list the person here has not approved: the first part of the
    /// path names it, and the vault folder itself has nothing there. Used to keep such files out of what a bridge shows.
    func isInUnapprovedLink(_ path: String, waiting: Set<String>) -> Bool {
        guard let first = path.split(separator: "/").first, waiting.contains(String(first)) else { return false }
        return !FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    /// Names on this vault's list the person has not approved, less any name an approved folder also uses.
    func unapprovedLinkNames() -> Set<String> {
        let states = linkStates()
        return Set(states.filter { !$0.approved }.map(\.folder.name)).subtracting(states.filter(\.approved).map(\.folder.name))
    }

    /// Takes out of the index every file that came from a linked folder not approved here (D-101). An index built before
    /// approvals existed, or before a folder lost its approval, would otherwise still answer from it. Nothing on disk is
    /// touched, and the vault's list is not changed: once the folder is approved, the next index brings it back.
    @discardableResult
    public func dropUnapprovedFromIndex() throws -> Int {
        guard !readOnly else { return 0 }
        let waiting = unapprovedLinkNames()
        guard !waiting.isEmpty else { return 0 }
        var gone: [String] = []
        try database.transaction {
            for name in waiting {
                let prefix = name + "/"
                let rows = try database.rows("SELECT path FROM files WHERE substr(path, 1, ?) = ?", [.int(Int64(prefix.unicodeScalars.count)), .text(prefix)])
                for row in rows {
                    guard let path = row[0].text, isInUnapprovedLink(path, waiting: waiting) else { continue }
                    try remove(path)
                    gone.append(path)
                }
            }
            if !gone.isEmpty {
                for path in gone { try database.run("DELETE FROM links WHERE source = ? OR target = ?", [.text(path), .text(path)]) }
                try bumpGeneration()
            }
        }
        if !gone.isEmpty { database.locked { forgetCaches() } }
        return gone.count
    }

    /// One plain line for a command that opened this vault and met linked folders the person has not approved, or nil.
    /// - Parameter detailed: true only where the person reads it in their own terminal. Then it names each folder and its
    ///   real path, cleaned of control characters, and how to approve each by its real path (D-104). Otherwise, as where a
    ///   program with a shell reads burrow's stderr, it gives only a count, as `burrow mcp` does: names and paths come from
    ///   a file anyone who shared the vault could have written.
    public func linksAwaitingApprovalLine(detailed: Bool) -> String? {
        let waiting = linkStates().filter { !$0.approved }
        guard !waiting.isEmpty else { return nil }
        let one = waiting.count == 1
        let skipped = "\(one ? "1 linked folder was" : "\(waiting.count) linked folders were") skipped because \(one ? "it isn't" : "they aren't") approved on this Mac"
        guard detailed else {
            return skipped + ". Only you can approve \(one ? "it" : "them"): open this vault in the Burrow app, or run burrow link list \(Printable.shellWord(root.path)) in your own terminal."
        }
        let named = waiting.map { state in
            let name = Printable.clean(state.folder.name)
            if let why = state.refusal { return "\(name) (\(Printable.clean(state.realPath)), never followed: \(why))" }
            return "\(name) (\(Printable.clean(state.realPath)))"
        }.joined(separator: ", ")
        let approvable = waiting.filter { $0.refusal == nil }
        guard !approvable.isEmpty else { return skipped + ": \(named)." }
        let commands = approvable.map { "burrow link approve \(Printable.shellWord(root.path)) \(Printable.shellWord($0.realPath))" }.joined(separator: "; ")
        return skipped + ": \(named). If you linked \(approvable.count == 1 ? "it" : "them") yourself, approve \(approvable.count == 1 ? "it" : "each") in the Burrow app, or here with: \(commands)"
    }
}
