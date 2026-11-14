import Foundation

/// How much Burrow's own store holds for one vault (D-98). The person's files are measured apart and never limited.
public struct StorageUsage: Sendable, Equatable {
    /// The index's pages that hold something. Free pages SQLite keeps for reuse are not counted, so removing files
    /// from a vault lowers the figure straight away.
    public var index = 0
    /// The meaning-search block Burrow keeps beside the index (`vectors.bin`), counted at the size it is built to.
    public var vectorCache = 0
    /// Everything else in the store: conversations, the Ledger, model caches, settings.
    public var other = 0
    public var total: Int { index + vectorCache + other }
    public init(index: Int = 0, vectorCache: Int = 0, other: Int = 0) {
        self.index = index
        self.vectorCache = vectorCache
        self.other = other
    }
}

/// A vault's usage beside its limits, for `burrow stats` and the app's bar.
public struct StorageReport: Sendable {
    public let usage: StorageUsage
    public let limit: Int?
    /// Every store Burrow knows, this one included.
    public let allVaults: Int
    public let vaultCount: Int
    public let globalLimit: Int?
    /// The person's own files in the vault folder, outside `.burrow`, when they were measured.
    public let ownFiles: Int?

    /// Share of the limit used, from 0; nil when there is no limit.
    public var share: Double? { limit.map { Double(usage.total) / Double(max(1, $0)) } }
    public var globalShare: Double? { globalLimit.map { Double(allVaults) / Double(max(1, $0)) } }
    /// Past this share the app and `burrow stats` say the limit is near.
    public static let nearShare = 0.85
}

/// Why indexing stopped short, in words a person can act on (D-98).
public struct StorageStop: Sendable, Equatable {
    public enum Which: String, Sendable { case vault, global }
    public let which: Which
    public let limit: Int
    /// What the store, or every store, held when Burrow stopped.
    public let holding: Int
    /// How far over the limit the next step would have gone.
    public let over: Int
    public var filesNotAdded: [String] = []
    public var piecesWithoutMeaning = 0
    /// Roughly what the store, or every store, would hold with everything indexed, when Burrow could work it out.
    public var needed: Int?
    /// Folder and store, to write the command that raises the limit.
    let vaultFolder: String

    public var message: String {
        var lines: [String] = []
        let whose = which == .vault ? "this vault's store" : "all the vaults Burrow knows, together,"
        lines.append("Burrow stopped adding to the index: \(whose) would go over the \(which == .vault ? "" : "global ")storage limit of \(ByteSize.format(limit)) by about \(ByteSize.format(max(1, over))) (\(which == .vault ? "it holds" : "they hold") \(ByteSize.format(holding)) now).")
        if !filesNotAdded.isEmpty {
            let named = filesNotAdded.prefix(3).joined(separator: ", ")
            lines.append("\(filesNotAdded.count) file\(filesNotAdded.count == 1 ? " was" : "s were") not added: \(named)\(filesNotAdded.count > 3 ? " and \(filesNotAdded.count - 3) more" : "").")
        }
        if piecesWithoutMeaning > 0 {
            lines.append("\(piecesWithoutMeaning) piece\(piecesWithoutMeaning == 1 ? " is" : "s are") findable by words only, without meaning search.")
        }
        if let needed, needed > limit {
            lines.append("Indexing all of it would take about \(ByteSize.format(needed)), \(ByteSize.format(needed - limit)) more than the limit.")
        }
        lines.append("Nothing was deleted: your files and the Ledger are as they were, and what is already indexed still works.")
        let size = ByteSize.format(Self.roomier(limit, max(needed ?? 0, holding + over))).replacingOccurrences(of: " ", with: "")
        let raise = which == .vault ? "burrow config \(Self.quoted(vaultFolder)) set storage.limit \(size)" : "burrow config --global set storage.limit \(size)"
        lines.append("To go on, raise the limit (\(raise)), or remove files from the vault or unlink a folder, then run burrow index again.")
        return lines.joined(separator: "\n")
    }

    /// A round size comfortably above what is needed, for the suggested command.
    static func roomier(_ limit: Int, _ needed: Int) -> Int {
        let target = max(limit + limit / 4, needed + needed / 4)
        for step in [1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000, 1_000_000_000] where target <= step * 10 {
            return (target + step - 1) / step * step
        }
        return (target + 999_999_999) / 1_000_000_000 * 1_000_000_000
    }

    static func quoted(_ path: String) -> String {
        path.contains(" ") ? "\"\(path)\"" : path
    }
}

enum StorageMeter {
    static let indexFiles: Set<String> = ["index.sqlite", "index.sqlite-wal", "index.sqlite-shm"]
    static let vectorFile = "vectors.bin"
    /// The vector block's layout (Index.swift): a short header, then an id and the floats for each piece.
    static let vectorHeader = 32
    static func vectorCacheBytes(count: Int, dimension: Int) -> Int { count == 0 ? 0 : vectorHeader + count * (8 + dimension * 4) }

    /// Every file in a store apart from the index and the vector block, which are counted by what they hold.
    static func otherBytes(in store: URL) -> Int {
        guard let walker = FileManager.default.enumerator(at: store, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else { continue }
            if url.deletingLastPathComponent().standardizedFileURL.path == store.standardizedFileURL.path,
               indexFiles.contains(url.lastPathComponent) || url.lastPathComponent == vectorFile { continue }
            total += values.fileSize ?? 0
        }
        return total
    }

    /// Another vault's store, opened only to read: what `storageUsage` gives for its own vault.
    static func usage(of store: URL) -> Int {
        let index = store.appendingPathComponent("index.sqlite")
        guard FileManager.default.fileExists(atPath: index.path) else { return otherBytes(in: store) }
        if let other = try? Vault(readingOnly: store.deletingLastPathComponent(), store: store), let usage = try? other.storageUsage() {
            return usage.total
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: index.path)[.size] as? Int) ?? 0
        return size + otherBytes(in: store)
    }

    /// The person's own files in the vault folder, leaving out Burrow's store.
    static func ownBytes(in root: URL, store: URL) -> Int {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return 0 }
        let skip = store.standardizedFileURL.path
        var total = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if url.standardizedFileURL.path == skip || url.lastPathComponent == ".burrow" { walker.skipDescendants() }
                continue
            }
            if values.isRegularFile == true { total += values.fileSize ?? 0 }
        }
        return total
    }
}

extension Vault {
    /// The index's pages that hold data, read from the open connection, so it counts what a transaction has added.
    func indexBytesInUse() throws -> Int {
        let pages = try database.rows("PRAGMA page_count").first?[0].int ?? 0
        let free = try database.rows("PRAGMA freelist_count").first?[0].int ?? 0
        let size = try database.rows("PRAGMA page_size").first?[0].int ?? 4096
        return max(0, pages - free) * size
    }

    /// How many floats a stored vector has, or 0 when there are none.
    func vectorDimension() -> Int {
        ((try? database.rows("SELECT length(vector) FROM vectors LIMIT 1").first?[0].int) ?? nil).map { $0 / 4 } ?? 0
    }

    /// What Burrow's own store holds for this vault (D-98).
    public func storageUsage() throws -> StorageUsage {
        StorageUsage(index: try indexBytesInUse(),
                     vectorCache: StorageMeter.vectorCacheBytes(count: try count("vectors"), dimension: vectorDimension()),
                     other: StorageMeter.otherBytes(in: store))
    }

    /// Usage beside the limits. `ownFiles` walks the vault folder, so it is asked for only where it is shown.
    public func storageReport(ownFiles: Bool = false) throws -> StorageReport {
        let usage = try storageUsage()
        let others = KnownVaults.list(in: stateFolder).filter { $0.store != store.path }
        let elsewhere = others.reduce(0) { $0 + StorageMeter.usage(of: URL(fileURLWithPath: $1.store)) }
        return StorageReport(usage: usage, limit: config.storageLimit, allVaults: usage.total + elsewhere, vaultCount: others.count + 1,
                             globalLimit: globalConfig.storageLimit, ownFiles: ownFiles ? StorageMeter.ownBytes(in: root, store: store) : nil)
    }
}

/// The limits as indexing meets them: read once when a refresh starts (D-98).
struct StorageGuard {
    let vaultLimit: Int?
    let globalLimit: Int?
    /// This store apart from the index: other files and the vector block as it stood when the refresh began.
    let fixed: Int
    /// Every other store Burrow knows, when a global limit is set.
    let elsewhere: Int
    let vaultFolder: String

    /// Nil when no limit applies, so a vault without one does no measuring at all.
    init?(vault: Vault) {
        let vaultLimit = vault.config.storageLimit
        let globalLimit = vault.globalConfig.storageLimit
        guard vaultLimit != nil || globalLimit != nil else { return nil }
        self.vaultLimit = vaultLimit
        self.globalLimit = globalLimit
        let vectors = (try? vault.count("vectors")) ?? 0
        fixed = StorageMeter.otherBytes(in: vault.store) + StorageMeter.vectorCacheBytes(count: vectors, dimension: vault.vectorDimension())
        if globalLimit != nil {
            elsewhere = KnownVaults.list(in: vault.stateFolder).filter { $0.store != vault.store.path }
                .reduce(0) { $0 + StorageMeter.usage(of: URL(fileURLWithPath: $1.store)) }
        } else {
            elsewhere = 0
        }
        vaultFolder = vault.root.path
    }

    /// The store's size with the index at `index` bytes and `extra` more bytes to come.
    func total(index: Int, extra: Int = 0) -> Int { index + fixed + extra }

    /// The limit `total` would cross, if any: the vault's own first.
    func crossed(_ total: Int) -> StorageStop? {
        if let vaultLimit, total > vaultLimit {
            return StorageStop(which: .vault, limit: vaultLimit, holding: 0, over: total - vaultLimit, vaultFolder: vaultFolder)
        }
        if let globalLimit, total + elsewhere > globalLimit {
            return StorageStop(which: .global, limit: globalLimit, holding: 0, over: total + elsewhere - globalLimit, vaultFolder: vaultFolder)
        }
        return nil
    }

    /// The stop with what the store, or every store, holds now filled in.
    func stop(_ crossed: StorageStop, holdingNow store: Int) -> StorageStop {
        StorageStop(which: crossed.which, limit: crossed.limit, holding: crossed.which == .vault ? store : store + elsewhere,
                    over: crossed.over, filesNotAdded: crossed.filesNotAdded, piecesWithoutMeaning: crossed.piecesWithoutMeaning, needed: crossed.needed, vaultFolder: vaultFolder)
    }
}
