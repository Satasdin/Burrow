import Foundation

// Where vaults are, and which folders are vaults at all (D-114). A folder becomes a vault only when the person makes it
// one: `camr vault new`, `camr index`, or Open or Create a Vault in the app. Every other command opens a vault that
// already exists and refuses any other folder, so a program started in ~/Downloads can't build an index there.

extension Vault {
    /// True when this folder is a vault: CAMR's store for it (`store`, else `<folder>/.camr`) is there. Usually with
    /// its index; a vault shared without its index file (its linked-folder list, its Ledger) is still one.
    public static func hasIndex(_ folder: URL, store: URL? = nil) -> Bool {
        var isFolder: ObjCBool = false
        let place = store ?? CAMRPlaces.store(in: folder)
        return FileManager.default.fileExists(atPath: place.path, isDirectory: &isFolder) && isFolder.boolValue
    }

    /// What a command says when it is given a folder that isn't a vault: nothing was made there, and how to make it one.
    public static func notAVault(_ path: String) -> String {
        "\(path) isn't a CAMR vault, so CAMR made nothing there. To make it one: camr vault new \(Printable.shellWord(path))"
    }
}

/// The vault opened or made last, so `camr` alone and the app's first launch go back to it.
public enum LastVault {
    public static func file(in folder: URL = CAMRPlaces.stateFolder) -> URL { folder.appendingPathComponent("last-vault") }

    /// The folder, when it is still there and still a vault.
    public static func read(in folder: URL = CAMRPlaces.stateFolder) -> String? {
        guard let saved = try? String(contentsOf: file(in: folder), encoding: .utf8) else { return nil }
        let path = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    public static func write(_ path: String, in folder: URL = CAMRPlaces.stateFolder) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? path.write(to: file(in: folder), atomically: true, encoding: .utf8)
    }
}

/// Which vault the app opens when it starts with none open (D-114). The terminal's vaults were invisible to the app: a
/// tester made ~/CAMRTest with `camr vault new` and the app still asked them to choose a folder.
public enum StartingVault {
    public enum Choice: Equatable, Sendable {
        /// Open this vault straight away.
        case open(String)
        /// Show the welcome screen with these vaults to pick from (may be empty).
        case pick([String])
    }

    /// - Parameters:
    ///   - recents: the vaults the app opened before, newest first.
    ///   - last: the vault the terminal made or opened last.
    ///   - known: every vault CAMR knows on this Mac (`vaults.json`).
    ///   - exists: whether a vault's folder still has its index; a test passes its own.
    /// The app's own recents are the person's habit, so they are offered as before. Only an app that has never opened a
    /// vault opens one by itself: the terminal's last vault, else the one vault CAMR knows. Otherwise every vault it
    /// knows is listed, the app's recents first.
    public static func choose(recents: [String], last: String?, known: [String],
                              exists: (String) -> Bool = { Vault.hasIndex(URL(fileURLWithPath: $0)) }) -> Choice {
        let live = known.filter(exists)
        if recents.isEmpty {
            if let last, exists(last) { return .open(last) }
            if live.count == 1 { return .open(live[0]) }
        }
        var all: [String] = []
        for path in recents + live where !all.contains(path) { all.append(path) }
        return .pick(all)
    }
}

/// CAMR indexes on this Mac, for `camr vault list` and `camr vault remove` (D-114): the vaults CAMR knows, and
/// any `.camr` folder found near the top of the home folder that it doesn't, such as one an earlier CAMR made in
/// ~/Downloads when a program was started there.
public enum IndexPlaces {
    public struct Found: Equatable, Sendable {
        public let root: String
        public let store: String
        public let bytes: Int64
        /// True when CAMR's list of vaults names it.
        public let known: Bool
    }

    /// Every file's size under a folder, links not followed.
    public static func size(of folder: URL) -> Int64 {
        var total: Int64 = 0
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }

    /// `.camr` folders with an index, `depth` folders down from `home` at most. Hidden folders, ~/Library and packages
    /// are passed over; a folder that holds a `.camr` isn't looked inside further.
    public static func scan(_ home: URL, depth: Int = 3) -> [URL] {
        var found: [URL] = []
        let files = FileManager.default
        func visit(_ folder: URL, _ level: Int) {
            if Vault.hasIndex(folder) { found.append(folder.standardizedFileURL); return }
            guard level < depth, let children = try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey], options: [.skipsHiddenFiles]) else { return }
            for child in children {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true, values?.isPackage != true else { continue }
                if level == 0, child.lastPathComponent == "Library" { continue }
                visit(child, level + 1)
            }
        }
        visit(home, 0)
        return found
    }

    /// The known vaults, then the indexes found under `home` that CAMR doesn't know, each with its size.
    public static func all(home: URL, state: URL = CAMRPlaces.stateFolder, depth: Int = 3) -> [Found] {
        let known = KnownVaults.list(in: state)
        var out = known.map { Found(root: $0.root, store: $0.store, bytes: size(of: URL(fileURLWithPath: $0.store)), known: true) }
        let knownStores = Set(known.map { Vault.realPath($0.store) })
        for folder in scan(home, depth: depth) {
            let store = CAMRPlaces.store(in: folder)
            guard !knownStores.contains(Vault.realPath(store.path)) else { continue }
            out.append(Found(root: folder.path, store: store.path, bytes: size(of: store), known: false))
        }
        return out
    }
}

extension KnownVaults {
    /// Takes a vault off the list, by its folder. Never fails loudly, as `remember`.
    public static func forget(root: String, in folder: URL = CAMRPlaces.stateFolder) {
        let file = file(in: folder)
        guard let data = try? Data(contentsOf: file), var all = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        let real = Vault.realPath(root)
        all.removeAll { Vault.realPath($0.root) == real }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try? encoder.encode(all).write(to: file, options: .atomic)
    }
}
