import Foundation

/// A folder a vault's list names, as this Mac sees it: whether the person here has said yes to it (D-101).
public struct LinkState: Sendable, Hashable, Identifiable {
    public var id: String { folder.name + "\u{0}" + folder.path }
    public let folder: LinkedFolder
    /// True once the person on this Mac approved this folder for this vault, or linked it here themselves.
    public let approved: Bool
    /// The folder with symlinks resolved: what an approval names.
    public let realPath: String
    public let exists: Bool
    /// True when the folder named is a symlink to somewhere else. macOS's own /private prefix (/tmp, /var) doesn't count.
    public var leadsElsewhere: Bool { realPath != folder.path && "/private" + realPath != folder.path }
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
    static func realPath(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path }

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
            return LinkState(folder: folder, approved: approved.contains(real), realPath: real, exists: exists)
        }
    }

    /// The linked folders Burrow reads: only those the person on this Mac approved for this vault (D-101). Every reader
    /// goes through this: indexing, search, read, Ask, the MCP tools, `burrow check` and the gate, and the app.
    /// None for a vault read through a bridge (D-100): no file outside its own folder is opened through the bridge.
    public func linkedFolders() -> [LinkedFolder] {
        guard !readOnly else { return [] }
        return linkStates().filter(\.approved).map(\.folder)
    }

    /// Folders on this vault's list that the person on this Mac has not approved. They are skipped everywhere.
    public func linksAwaitingApproval() -> [LinkedFolder] {
        linkStates().filter { !$0.approved }.map(\.folder)
    }

    /// Approves folders on this vault's list, by name or path, or every one with nil. Only the person approves: the
    /// command line's `burrow link approve` and the app's sheet call this, never a connected program.
    @discardableResult
    public func approveLinks(_ which: [String]? = nil) throws -> [LinkedFolder] {
        guard !readOnly else { throw NoteProblem(description: "A vault read through a bridge has no linked folders of its own.") }
        let states = linkStates()
        let chosen: [LinkState]
        if let which {
            chosen = states.filter { state in
                which.contains { asked in
                    asked.lowercased() == state.folder.name.lowercased() || asked == state.folder.path
                        || Self.realPath(asked) == state.realPath
                }
            }
            let missing = which.filter { asked in !chosen.contains { $0.folder.name.lowercased() == asked.lowercased() || $0.folder.path == asked || $0.realPath == Self.realPath(asked) } }
            if !missing.isEmpty {
                throw NoteProblem(description: "\(missing.joined(separator: ", ")) is not on this vault's list of linked folders.\(states.isEmpty ? " It links none." : " It links: " + states.map(\.folder.name).joined(separator: ", "))")
            }
        } else {
            chosen = states
        }
        try approve(chosen.map(\.realPath))
        return chosen.map(\.folder)
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
    @discardableResult
    public func linkFolder(_ url: URL) throws -> LinkedFolder {
        guard !readOnly else { throw NoteProblem(description: "A vault read through a bridge can't link folders.") }
        var folders = listedLinkedFolders()
        let path = url.standardizedFileURL.path
        let real = Self.realPath(path)
        let here = Self.realPath(root.path)
        guard path != root.path, !path.hasPrefix(root.path + "/"), real != here, !real.hasPrefix(here + "/") else {
            throw NoteProblem(description: "That folder is already inside this vault.")
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
    public func linksAwaitingApprovalLine() -> String? {
        let waiting = linksAwaitingApproval()
        guard !waiting.isEmpty else { return nil }
        let named = waiting.map { "\($0.name) (\($0.path))" }.joined(separator: ", ")
        let vault = root.path.contains(" ") ? "\"\(root.path)\"" : root.path
        return "\(waiting.count == 1 ? "1 linked folder was" : "\(waiting.count) linked folders were") skipped because you haven't approved \(waiting.count == 1 ? "it" : "them") on this Mac: \(named). If you linked \(waiting.count == 1 ? "it" : "them"), approve with: burrow link approve \(vault) --all"
    }
}
