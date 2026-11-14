import Foundation

/// A folder several people share: a git repository each person clones, or a synced folder (iCloud Drive, Dropbox)
/// (D-109). Each person's Burrow opens their own vault and joins the team folder. Its notes are searchable from the
/// vault, labelled with the team's name (`Team › Plans/launch.md`), and its shared Ledger hands every member's programs
/// the decisions teammates chose to share. The list of teams is kept in Burrow's own folder on this Mac, keyed by the
/// vault's real path, like bridges (D-100): nothing in a vault or a team folder can add a team.
public struct Team: Sendable, Hashable, Codable, Identifiable {
    public var id: String { name }
    /// How this vault calls the team. Every path from the team folder starts with it.
    public let name: String
    /// The team folder, symlinks resolved.
    public let path: String
    public var url: URL { URL(fileURLWithPath: path) }
    /// The team's shared Ledger, inside the team folder: one folder per person and Mac, one file per decision.
    public var ledgerFolder: URL { url.appendingPathComponent(".burrow/ledger", isDirectory: true) }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// Who keeps decisions for a team from this Mac: the person's name, set once, and a short random tag for this Mac, so
/// the same person on two Macs writes into two folders and two people never write the same file (D-109).
public struct TeamMember: Sendable, Equatable {
    public let name: String
    public let machine: String
    /// The person's name as plain lowercase letters and digits, for a folder and an id.
    public var slug: String {
        let kept = name.lowercased().unicodeScalars.map { scalar -> Character in
            ("a"..."z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar)) ? Character(scalar) : "-"
        }
        let joined = String(kept).split(separator: "-").joined(separator: "-")
        let short = String(joined.prefix(24)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return short.isEmpty ? "person" : short
    }
    /// The folder this person's decisions go into on this Mac, under the team's Ledger: only this Mac writes there.
    public var folder: String { slug + "-" + machine }
}

/// Every vault's teams, the person's name and this Mac's tag, in one file in Burrow's own folder.
struct TeamStore: Codable {
    var vaults: [String: [Team]] = [:]
    var person: String?
    var machine: String?

    static func file(in folder: URL) -> URL { folder.appendingPathComponent("teams.json") }

    /// An empty list when there is no file yet. Throws when there is one that can't be read, so a save never writes over it.
    static func load(in folder: URL) throws -> TeamStore {
        let url = file(in: folder)
        guard FileManager.default.fileExists(atPath: url.path) else { return TeamStore() }
        do {
            return try JSONDecoder().decode(TeamStore.self, from: Data(contentsOf: url))
        } catch {
            throw NoteProblem(description: "Burrow's list of teams (\(url.path)) can't be read, so it was left as it is: \(error.localizedDescription)")
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
    /// This vault's teams, from Burrow's own folder only. A vault read through a bridge or as a team has none.
    public func teams() -> [Team] {
        guard !readOnly, let saved = try? TeamStore.load(in: stateFolder) else { return [] }
        return saved.vaults[bridgeKey] ?? []
    }

    /// The person keeping team decisions on this Mac, or nil before a name was set with `burrow team join --as`.
    public var teamMember: TeamMember? {
        guard let saved = try? TeamStore.load(in: stateFolder), let name = saved.person, let machine = saved.machine else { return nil }
        return TeamMember(name: name, machine: machine)
    }

    /// The team a command or a tool names: by name, or "team" (or nothing) for the only one. Throws with what to do.
    public func team(named given: String?) throws -> Team {
        let all = teams()
        guard !all.isEmpty else {
            throw NoteProblem(description: "This vault has not joined a team. The person joins one in their own terminal: burrow team join <vault> <team-folder>")
        }
        let asked = given?.trimmingCharacters(in: .whitespaces) ?? ""
        if let found = all.first(where: { $0.name == asked || $0.name.lowercased() == asked.lowercased() }) { return found }
        if ["", "team", "yes", "true"].contains(asked.lowercased()), all.count == 1 { return all[0] }
        throw NoteProblem(description: "Say which team: \(all.map(\.name).joined(separator: ", ")).")
    }

    /// The name a person is known by when none was given: git's user.name in the team folder, else this Mac's full name.
    public static func defaultPersonName(for folder: URL) -> String {
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", folder.path, "config", "user.name"]
        let pipe = Pipe()
        git.standardOutput = pipe
        git.standardError = Pipe()
        if (try? git.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            git.waitUntilExit()
            let name = cleanPersonName(String(decoding: data, as: UTF8.self))
            if git.terminationStatus == 0, !name.isEmpty { return name }
        }
        let full = cleanPersonName(NSFullUserName())
        return full.isEmpty ? cleanPersonName(NSUserName()) : full
    }

    /// A person's name as it is signed: one line, no control or bidi characters, at most 60 characters.
    public static func cleanPersonName(_ text: String) -> String {
        let kept = text.unicodeScalars.filter { !Printable.isControl($0) && !CharacterSet.controlCharacters.contains($0) && !"<>`".unicodeScalars.contains($0) }
        let flat = String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(flat.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    /// Joins a team folder: its notes become searchable from this vault, labelled with the team's name, and its shared
    /// Ledger is handed to every program connected to this vault. Nothing is written into the team folder here. Joining
    /// the same folder again renames it; `person` sets (or changes) the name this person's team decisions are signed with.
    @discardableResult
    public func joinTeam(_ folder: URL, name: String? = nil, person: String? = nil) throws -> Team {
        guard !readOnly else { throw NoteProblem(description: "A vault read through a bridge can't join a team.") }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else {
            throw NoteProblem(description: "\(folder.path) is not a folder.")
        }
        let there = folder.standardizedFileURL.resolvingSymlinksInPath().path
        let here = root.resolvingSymlinksInPath().path
        let storePath = store.resolvingSymlinksInPath().path
        let state = stateFolder.standardizedFileURL.resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        func holds(_ outer: String, _ inner: String) -> Bool { outer == inner || inner.hasPrefix(outer.hasSuffix("/") ? outer : outer + "/") }
        guard there != "/", there != home, !holds(there, home) else {
            throw NoteProblem(description: "\(there) holds your home folder; a team folder is one folder the team shares.")
        }
        guard !holds(there, here), !holds(here, there) else {
            throw NoteProblem(description: "The team folder and this vault can't be inside one another: a team would then read your own vault.")
        }
        guard !holds(there, storePath), !holds(there, state) else {
            throw NoteProblem(description: "\(there) holds Burrow's own files; choose the folder the team shares.")
        }
        var saved = try TeamStore.load(in: stateFolder)
        var all = saved.vaults[bridgeKey] ?? []
        let asked = name.map(Bridge.cleanName)
        if let asked, asked.isEmpty { throw NoteProblem(description: "A team's name needs some letters.") }
        let bridgeNames = Set(storedBridges().map(\.name))
        func taken(_ chosen: String) -> Bool {
            bridgeNames.contains(chosen) || all.contains { $0.name == chosen && $0.path != there }
        }
        let team: Team
        if let index = all.firstIndex(where: { $0.path == there }) {
            let chosen = asked ?? all[index].name
            if taken(chosen) { throw NoteProblem(description: "There is already a bridge or team called \(chosen).") }
            team = Team(name: chosen, path: there)
            all[index] = team
        } else {
            let base = asked ?? Bridge.cleanName(URL(fileURLWithPath: there).lastPathComponent)
            var chosen = base.isEmpty ? "Team" : base
            if asked != nil, taken(chosen) { throw NoteProblem(description: "There is already a bridge or team called \(chosen).") }
            var attempt = 2
            while taken(chosen) {
                chosen = "\(base) \(attempt)"
                attempt += 1
            }
            team = Team(name: chosen, path: there)
            all.append(team)
        }
        if let person {
            let clean = Self.cleanPersonName(person)
            guard !clean.isEmpty else { throw NoteProblem(description: "Your name needs some letters: burrow team join … --as \"Your Name\"") }
            saved.person = clean
        } else if saved.person == nil {
            saved.person = Self.defaultPersonName(for: URL(fileURLWithPath: there))
        }
        if saved.machine == nil { saved.machine = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(4)).lowercased() }
        saved.vaults[bridgeKey] = all
        try saved.save(in: stateFolder)
        database.locked { bridgedVaults = [:] }
        return team
    }

    /// Leaves a team: it is no longer searched or handed over from this vault, and Burrow's own index of it on this Mac
    /// is deleted. The team folder, and every decision in it, is not touched.
    @discardableResult
    public func leaveTeam(_ name: String) throws -> Team {
        var saved = try TeamStore.load(in: stateFolder)
        let all = saved.vaults[bridgeKey] ?? []
        guard let gone = all.first(where: { $0.name == name || $0.name.lowercased() == name.lowercased() }) else {
            throw NoteProblem(description: "There is no team called \(name).\(all.isEmpty ? "" : " Teams: " + all.map(\.name).joined(separator: ", "))")
        }
        let left = all.filter { $0.path != gone.path }
        saved.vaults[bridgeKey] = left.isEmpty ? nil : left
        try saved.save(in: stateFolder)
        database.locked { bridgedVaults = [:] }
        try? FileManager.default.removeItem(at: teamIndexStore(gone))
        return gone
    }

    /// Where Burrow keeps its own index of a team folder on this Mac: in Burrow's own folder, never in the team folder,
    /// so two people's Burrows never write the same index, and nothing in the team folder decides what it holds.
    public func teamIndexStore(_ team: Team) -> URL {
        let key = Scanner.digest(Data((bridgeKey + "\u{0}" + team.path).utf8)).prefix(16)
        return stateFolder.appendingPathComponent("teams", isDirectory: true).appendingPathComponent(String(key), isDirectory: true)
    }

    /// The teams as bridges, so search, read, the Library and Ask cover them the way they cover a bridged vault (D-97):
    /// read-only, never followed onwards. Their decisions are handed over by the team Ledger, not as a bridge's.
    func teamBridges() -> [Bridge] {
        teams().map { Bridge(name: $0.name, path: $0.path, withLedger: false, everything: true, store: teamIndexStore($0).path) }
    }

    /// The team a labelled path or a bridge belongs to, if it is a team.
    public func team(of bridge: Bridge) -> Team? { bridge.isTeam ? teams().first { $0.name == bridge.name } : nil }

    /// Brings Burrow's index of each team folder up to date, touching only what changed; skipped when nothing in the
    /// folder changed since the last time. Returns a line for each team that could not be indexed.
    @discardableResult
    public func refreshTeams(embedder: Embedder? = nil) async -> [String] {
        var problems: [String] = []
        var indexed = false
        for team in teams() {
            let place = teamIndexStore(team)
            let mark = place.appendingPathComponent("tree-fingerprint")
            let now = Self.teamFingerprint(team.url) + (embedder == nil ? "" : "+meaning")
            if (try? String(contentsOf: mark, encoding: .utf8)) == now,
               FileManager.default.fileExists(atPath: place.appendingPathComponent("index.sqlite").path) { continue }
            do {
                // Its store is Burrow's own, so no list of linked folders, bridges or settings in the team folder is read.
                let opened = try Vault(project: team.url, store: place, everything: true)
                opened.stateFolder = stateFolder
                try await opened.refresh(embedder: embedder)
                indexed = true
                try? now.write(to: mark, atomically: true, encoding: .utf8)
            } catch {
                problems.append("\(team.name) could not be indexed: \(error)")
            }
        }
        if indexed { database.locked { bridgedVaults = [:] } }
        return problems
    }

    /// Names, sizes and dates of the files a team index would hold, so an unchanged folder is not read again.
    static func teamFingerprint(_ root: URL) -> String {
        var lines: [String] = []
        for path in Scanner.paths(in: root) {
            let values = try? root.appendingPathComponent(path).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            lines.append("\(path)\t\(values?.fileSize ?? -1)\t\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        return Scanner.digest(Data(lines.joined(separator: "\n").utf8))
    }

    /// A file inside a team folder, by its path there, for hashing what a team decision cites. Nil for anything outside
    /// the folder, through a symlink too, and for anything too large or not text.
    public static func readShared(_ path: String, in root: URL) -> String? {
        let clean = path.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !clean.hasPrefix("/"), !clean.hasPrefix("~"),
              !clean.split(separator: "/").contains(where: { $0 == ".." }) else { return nil }
        return Scanner.read(clean, in: root)?.text
    }
}
