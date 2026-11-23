import Foundation

/// Where CAMR keeps what belongs to no one vault: the last vault opened, the global config, the vaults it knows.
public enum CAMRPlaces {
    /// `~/Library/Application Support/CAMR`, or `CAMR_STATE_DIR` when it is set (tests and demonstrations use it,
    /// so they never touch the person's own settings).
    public static var stateFolder: URL {
        let folder: URL
        let environment = ProcessInfo.processInfo.environment
        // BURROW_STATE_DIR is the name before the rename (D-124); a program set up then may still pass it.
        if let set = [environment["CAMR_STATE_DIR"], environment["BURROW_STATE_DIR"]].compactMap({ $0 }).first(where: { !$0.isEmpty }) {
            folder = URL(fileURLWithPath: set)
        } else {
            folder = settledStateFolder(in: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])
        }
        makePrivate(folder)
        return folder
    }

    /// `<support>/CAMR`. Before the rename (D-124) it was `<support>/Burrow`: the first time CAMR finds that one and no
    /// CAMR folder, it moves it across whole (approvals, kept sessions, the vaults it knows) and leaves a link at the old
    /// name, so a program still running the older version, or a setting that wrote the old path, finds the same folder.
    /// If the move can't be made, the old folder is used where it is.
    public static func settledStateFolder(in support: URL) -> URL {
        let current = support.appendingPathComponent("CAMR"), older = support.appendingPathComponent("Burrow")
        let files = FileManager.default
        if files.fileExists(atPath: current.path) { return current }
        // Only a real folder is moved: a link there is one this method left, or one the person made.
        guard (try? files.attributesOfItem(atPath: older.path)[.type] as? FileAttributeType) == .typeDirectory else { return current }
        do {
            try files.moveItem(at: older, to: current)
            try? files.createSymbolicLink(at: older, withDestinationURL: current)
            return current
        } catch {
            // Another CAMR process may have moved it a moment ago.
            return files.fileExists(atPath: current.path) ? current : older
        }
    }

    /// The hidden folder inside a vault that holds its index, Ledger and settings: `.camr`. Vaults made before the rename
    /// (D-124) have `.burrow`, which is read where it is and never moved: a Team's Ledger lives in it inside a synced
    /// folder, shared with people who may still run the older version.
    public static func store(in folder: URL) -> URL {
        let current = folder.appendingPathComponent(".camr"), older = folder.appendingPathComponent(".burrow")
        var isFolder: ObjCBool = false
        if !FileManager.default.fileExists(atPath: current.path),
           FileManager.default.fileExists(atPath: older.path, isDirectory: &isFolder), isFolder.boolValue { return older }
        return current
    }

    /// Both names a vault's hidden folder can have, for walks that must step over it.
    public static let storeNames: Set<String> = [".camr", ".burrow"]

    /// The state folder holds approvals, bridges, team shares waiting for the person and session folds, so only the
    /// person's own account may open it: made 0700 when CAMR creates it, and tightened to 0700 if it was made looser
    /// (an earlier CAMR created it at 0755). Done once per folder per process (D-113).
    private static let privateLock = NSLock()
    nonisolated(unsafe) private static var madePrivate = Set<String>()

    static func makePrivate(_ folder: URL) {
        privateLock.lock(); defer { privateLock.unlock() }
        guard madePrivate.insert(folder.path).inserted else { return }
        let files = FileManager.default
        var isFolder: ObjCBool = false
        if files.fileExists(atPath: folder.path, isDirectory: &isFolder) {
            // Never through a link: a state folder that is a symlink is left as it is, not chmod'ed where it points.
            guard isFolder.boolValue, (try? files.attributesOfItem(atPath: folder.path)[.type] as? FileAttributeType) != .typeSymbolicLink,
                  let mode = (try? files.attributesOfItem(atPath: folder.path))?[.posixPermissions] as? Int, mode & 0o077 != 0 else { return }
            try? files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        } else {
            try? files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
}

/// Sizes as people write them: 500MB, 2 GB, 1.5gb, 800k, or a plain number of bytes (D-98).
/// KB, MB, GB and TB are thousands, as the Finder counts; KiB, MiB and GiB are 1024s for anyone who wants them.
public enum ByteSize {
    public static func parse(_ text: String) -> Int? {
        let clean = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "")
        guard !clean.isEmpty else { return nil }
        let digits = clean.prefix { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, let number = Double(digits), number >= 0 else { return nil }
        let units: [String: Double] = [
            "": 1, "b": 1, "byte": 1, "bytes": 1,
            "k": 1e3, "kb": 1e3, "m": 1e6, "mb": 1e6, "g": 1e9, "gb": 1e9, "t": 1e12, "tb": 1e12,
            "kib": 1024, "mib": 1_048_576, "gib": 1_073_741_824, "tib": 1_099_511_627_776,
        ]
        guard let scale = units[String(clean.dropFirst(digits.count))] else { return nil }
        let bytes = number * scale
        guard bytes < 9e18 else { return nil }
        return Int(bytes.rounded())
    }

    /// "312 KB", "1.9 MB", "2 GB": one decimal where it helps, none where it doesn't.
    public static func format(_ bytes: Int) -> String {
        let value = Double(max(0, bytes))
        if value < 1_000 { return "\(Int(value)) bytes" }
        for (unit, scale) in [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3)] where value >= scale {
            let amount = value / scale
            let shown = amount >= 100 || amount == amount.rounded() ? String(format: "%.0f", amount) : String(format: "%.1f", amount)
            return "\(shown) \(unit)"
        }
        return "\(Int(value)) bytes"
    }
}

public struct ConfigProblem: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// Settings kept as plain JSON: one file in a vault's store, and one global file in CAMR's own folder (D-98).
/// A vault's file lives in that vault, so nothing another vault does can change it.
public struct CAMRConfig {
    public enum Scope: Sendable { case vault, global, both }

    public struct Key: Sendable {
        public let name: String
        public let scope: Scope
        public let help: String
        let normalise: @Sendable (String) throws -> String
    }

    private static func size(_ name: String) -> @Sendable (String) throws -> String {
        { text in
            guard let bytes = ByteSize.parse(text) else {
                throw ConfigProblem("\(name) takes a size such as 500MB, 2GB or 800KB, not \"\(text)\".")
            }
            guard bytes > 0 else { throw ConfigProblem("\(name) must be more than nothing. To remove it, use unset.") }
            return text.trimmingCharacters(in: .whitespaces)
        }
    }

    public static let keys: [Key] = [
        Key(name: "storage.limit", scope: .both,
            help: "How much CAMR's own store may hold: for this vault, or with --global for every vault CAMR knows together. Your own files are never counted against it.",
            normalise: size("storage.limit")),
        Key(name: "index.maxFileSize", scope: .both,
            help: "Files larger than this are left out of the index. A vault's setting wins over the global one.",
            normalise: size("index.maxFileSize")),
        Key(name: "vault.name", scope: .vault,
            help: "The vault's name, used when another vault bridges to it.",
            normalise: { text in
                let clean = Bridge.cleanName(text)
                guard !clean.isEmpty else { throw ConfigProblem("vault.name needs some letters.") }
                return clean
            }),
    ]

    public let file: URL
    public let isGlobal: Bool
    public private(set) var values: [String: String]

    public init(file: URL, isGlobal: Bool) {
        self.file = file
        self.isGlobal = isGlobal
        values = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))) ?? [:]
    }

    public static func forVault(store: URL) -> CAMRConfig { CAMRConfig(file: store.appendingPathComponent("config.json"), isGlobal: false) }
    public static func global(in folder: URL = CAMRPlaces.stateFolder) -> CAMRConfig {
        CAMRConfig(file: folder.appendingPathComponent("config.json"), isGlobal: true)
    }

    public func value(_ name: String) -> String? { values[name] }

    static func key(_ name: String, global: Bool) throws -> Key {
        guard let key = keys.first(where: { $0.name.lowercased() == name.lowercased() }) else {
            throw ConfigProblem("CAMR has no setting called \(name). Settings: \(keys.map(\.name).joined(separator: ", ")).")
        }
        if global, key.scope == .vault { throw ConfigProblem("\(key.name) belongs to one vault, so it can't be set with --global.") }
        if !global, key.scope == .global { throw ConfigProblem("\(key.name) is only global: use --global.") }
        return key
    }

    public mutating func set(_ name: String, _ value: String) throws {
        let key = try Self.key(name, global: isGlobal)
        values[key.name] = try key.normalise(value)
        try save()
    }

    @discardableResult
    public mutating func unset(_ name: String) throws -> Bool {
        let key = try Self.key(name, global: isGlobal)
        let had = values.removeValue(forKey: key.name) != nil
        try save()
        return had
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(values).write(to: file, options: .atomic)
    }

    public var storageLimit: Int? { values["storage.limit"].flatMap(ByteSize.parse) }
    public var largestFile: Int? { values["index.maxFileSize"].flatMap(ByteSize.parse) }
}

/// The vaults CAMR has been pointed at on this Mac, for the global storage limit (D-98). A plain list of folders in
/// CAMR's own folder; one that no longer has a store is passed over.
public enum KnownVaults {
    public struct Entry: Codable, Hashable, Sendable {
        public let root: String
        public let store: String
    }

    static func file(in folder: URL) -> URL { folder.appendingPathComponent("vaults.json") }

    public static func list(in folder: URL = CAMRPlaces.stateFolder) -> [Entry] {
        let all = (try? JSONDecoder().decode([Entry].self, from: Data(contentsOf: file(in: folder)))) ?? []
        var seen = Set<String>()
        // A list written before entries were compared as real paths can name one vault twice; it is counted once.
        return all.filter { FileManager.default.fileExists(atPath: $0.store) && seen.insert(Vault.realPath($0.store)).inserted }
    }

    /// Adds a vault to the list. Never fails loudly: a list that can't be written only leaves the global count short.
    public static func remember(_ vault: Vault) {
        guard !vault.readOnly else { return }
        let folder = vault.stateFolder
        var all = list(in: folder)
        let entry = Entry(root: vault.root.path, store: vault.store.path)
        // Compared as real paths: /tmp/x and /private/tmp/x, or a folder reached through a link, are one vault (D-114).
        let real = Vault.realPath(entry.store)
        guard !all.contains(where: { Vault.realPath($0.store) == real }) else { return }
        all.append(entry)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try? encoder.encode(all).write(to: file(in: folder), options: .atomic)
    }
}

extension Vault {
    /// This vault's own settings, in its store.
    public var config: CAMRConfig { CAMRConfig.forVault(store: store) }
    /// The settings for every vault, in CAMR's own folder.
    public var globalConfig: CAMRConfig { CAMRConfig.global(in: stateFolder) }

    /// The largest file the index takes: the vault's setting, else the global one, else none beyond the scanner's own.
    var largestFileSetting: Int? { config.largestFile ?? globalConfig.largestFile }
}
