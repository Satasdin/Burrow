import BurrowCore
import BurrowTools
import Foundation

let vaultUsage = """
Several vaults, and how much Burrow keeps:
  burrow vault new <folder> [--name N] [--no-embed]               make a folder a vault and build its index
  burrow vault list                                               the vaults and indexes Burrow has on this Mac, with their sizes
  burrow vault remove <folder>                                    move a folder's Burrow index (.burrow) to the Trash; your files stay
  burrow bridge <vault> <other-vault> [--name N] [--notes-only | --with-ledger]
                                                                  let <vault> read <other-vault>, one way and read-only
  burrow bridge list <vault>
  burrow unbridge <vault> <name>
  burrow config <vault> list | get <key> | set <key> <value> | unset <key>
  burrow config --global list | get <key> | set <key> <value> | unset <key>
                                                                  storage.limit (e.g. 2GB, 500MB), index.maxFileSize, vault.name
"""

/// `vault`, `bridge`, `unbridge` and `config` (D-97, D-98). Returns false for any other command.
func runVaultCommand(_ arguments: [String]) async throws -> Bool {
    guard let command = arguments.first, ["vault", "bridge", "unbridge", "config"].contains(command) else { return false }
    let options = try Options(Array(arguments.dropFirst()))
    switch command {
    case "vault": try await newVault(options)
    case "bridge": try bridge(options)
    case "unbridge": try unbridge(options)
    default: try config(options)
    }
    return true
}

private func folderExists(_ path: String) -> Bool {
    var isFolder: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && isFolder.boolValue
}

/// A vault folder given on the command line, which must already exist.
private func existingVault(_ path: String?, _ what: String) throws -> Vault {
    guard let path else { throw Failure("\(what) needs a vault folder. Run burrow help for every command.") }
    guard folderExists(path) else { throw Failure("\(path) is not a folder") }
    guard Vault.hasIndex(URL(fileURLWithPath: path)) else { throw Failure(Vault.notAVault(path)) }
    let vault = try Vault(project: URL(fileURLWithPath: path), everything: true)
    meetLinks(vault)
    return vault
}

private func newVault(_ options: Options) async throws {
    switch options.positional.first {
    case "list": return listIndexes()
    case "remove": return try removeIndex(options.positional.dropFirst().first)
    default: break
    }
    guard options.positional.first == "new", options.positional.count > 1 else {
        throw Failure("make a vault with: burrow vault new <folder> [--name N]")
    }
    let path = options.positional[1]
    let url = URL(fileURLWithPath: path).standardizedFileURL
    // Already a vault: said, and the setup carries on (exit 0), since what was asked for is already true (D-114).
    if Vault.hasIndex(url) {
        let vault = try Vault(project: url, everything: true)
        KnownVaults.remember(vault)
        LastVault.write(url.path)
        meetLinks(vault)
        let files = (try? vault.stats().files).map { ", \($0) files indexed" } ?? ""
        print("\(url.path) is a vault already\(files); nothing was changed. Open it in the app, or with: burrow tui \(Printable.shellWord(url.path))")
        return
    }
    if FileManager.default.fileExists(atPath: url.path), !folderExists(url.path) { throw Failure("\(url.path) is a file, not a folder") }
    let made = !FileManager.default.fileExists(atPath: url.path)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let vault = try Vault(project: url, everything: true)
    if let name = options.values["--name"] {
        var settings = vault.config
        try settings.set("vault.name", name)
    }
    var report: IndexReport
    var how = "with meaning search"
    if options.flags.contains("--no-embed") {
        report = try await vault.refresh()
        how = "by words only"
    } else {
        do {
            report = try await vault.refresh(embedder: Ollama().embedder())
        } catch where OllamaReach.isUnreachable(error) {
            report = try await vault.refresh()
            how = "by words only, because Ollama isn't running; run burrow index \(url.path) --vault later for meaning search"
        }
    }
    KnownVaults.remember(vault)
    // The app's first launch and `burrow` alone open this one (D-114).
    LastVault.write(url.path)
    // A folder from someone else can already hold a list of linked folders; none of them was read (D-101).
    meetLinks(vault)
    let name = vault.config.value("vault.name").map { " called \($0)" } ?? ""
    print("\(made ? "made" : "opened") \(url.path) as a vault\(name): \(report.filesSeen) files indexed \(how).")
    print("Next: put notes in it, link a code folder (burrow link \(url.path) <folder>), or bridge it from another vault (burrow bridge <vault> \(url.path)).")
    if let stop = report.storageStop { throw Failure(stop.message) }
}

/// `burrow vault list`: every vault Burrow knows, and any index found near the top of the home folder that it doesn't
/// (one an earlier Burrow made in a folder a program was started in), with sizes and how to remove each (D-114).
private func listIndexes() {
    let home = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory())
    let all = IndexPlaces.all(home: home)
    let known = all.filter(\.known), stray = all.filter { !$0.known }
    if known.isEmpty { print("Burrow knows no vaults on this Mac yet. Make one with: burrow vault new <folder>") }
    else {
        print("Vaults Burrow knows:")
        for found in known { print("  \(Printable.clean(found.root))   \(ByteSize.format(Int(found.bytes)))") }
    }
    if !stray.isEmpty {
        print("\nIndexes Burrow found that are not on its list (made in a folder no one chose as a vault?):")
        for found in stray { print("  \(Printable.clean(found.root))   \(ByteSize.format(Int(found.bytes)))") }
    }
    if !all.isEmpty { print("\nTo remove one (your own files stay; the index goes to the Trash): burrow vault remove <folder>") }
}

/// `burrow vault remove <folder>`: the folder's `.burrow` goes to the Trash, so it can still be put back, and the folder
/// leaves Burrow's list. The person's own files are never touched. Only in the person's own terminal, typing yes, since
/// the index holds the vault's Ledger and conversations (D-104, D-114).
private func removeIndex(_ path: String?) throws {
    guard let path else { throw Failure("remove needs a folder: burrow vault remove <folder>") }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let store = url.appendingPathComponent(".burrow")
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: store.path, isDirectory: &isFolder), isFolder.boolValue else {
        KnownVaults.forget(root: url.path)
        throw Failure("\(url.path) has no Burrow index (.burrow), so there is nothing to remove")
    }
    guard (try? FileManager.default.attributesOfItem(atPath: store.path)[.type] as? FileAttributeType) != .typeSymbolicLink else {
        throw Failure("\(store.path) is a link, so Burrow left it alone")
    }
    let commits = ((try? FileManager.default.contentsOfDirectory(atPath: store.appendingPathComponent("ledger").path)) ?? []).count
    try askThePerson([
        "Move Burrow's index for \(Printable.clean(url.path)) to the Trash?",
        "  \(Printable.clean(store.path))   \(ByteSize.format(Int(IndexPlaces.size(of: store))))"
            + (commits > 0 ? "   (it holds this vault's Ledger and conversations)" : ""),
        "Your own files in the folder are not touched. You can put it back from the Trash.",
    ], refusal: "only you can remove a vault's index: run this in your own terminal and type yes. It can't be done through a pipe or by a program you've connected to Burrow.")
    try FileManager.default.trashItem(at: store, resultingItemURL: nil)
    KnownVaults.forget(root: url.path)
    if LastVault.read().map({ Vault.realPath($0) == Vault.realPath(url.path) }) == true { try? FileManager.default.removeItem(at: LastVault.file()) }
    print("moved \(store.path) to the Trash; \(url.path) is no longer a vault")
}

private func bridge(_ options: Options) throws {
    if options.positional.first == "list" {
        let vault = try existingVault(options.positional.dropFirst().first, "bridge list")
        // Bridges live only in Burrow's own folder (D-100); one written inside the vault folder is pointed out once, never followed.
        if let notice = vault.takeBridgesInVaultNotice() { print(notice) }
        let all = vault.bridges()
        guard !all.isEmpty else {
            print("\(vault.root.path) has no bridges. Add one with: burrow bridge \(vault.root.path) <other-vault>")
            return
        }
        for shelf in vault.bridgedShelves() {
            let what = shelf.bridge.isTeam ? "team folder (burrow team list)" : shelf.bridge.withLedger ? "notes and decisions in force" : "notes only"
            let state = shelf.problem ?? "\(shelf.files.count) files"
            print("\(shelf.bridge.name)   \(shelf.bridge.path)   \(what), read-only, \(state)")
        }
        return
    }
    guard options.positional.count >= 2 else {
        throw Failure("bridge needs two vaults: burrow bridge <vault> <other-vault> [--name N] [--notes-only | --with-ledger]")
    }
    if options.flags.contains("--notes-only"), options.flags.contains("--with-ledger") {
        throw Failure("choose one of --notes-only and --with-ledger")
    }
    let vault = try existingVault(options.positional[0], "bridge")
    let otherPath = options.positional[1]
    guard folderExists(otherPath) else { throw Failure("\(otherPath) is not a folder") }
    let bridge: Bridge
    do {
        bridge = try vault.addBridge(to: URL(fileURLWithPath: otherPath), name: options.values["--name"], withLedger: options.flags.contains("--with-ledger"))
    } catch let problem as NoteProblem {
        throw Failure(problem.description)
    }
    KnownVaults.remember(vault)
    print("bridged \(vault.root.lastPathComponent) to \(bridge.path) as \(bridge.name): \(vault.root.lastPathComponent) now reads \(bridge.name), read-only, one way.")
    print(bridge.withLedger ? "Its decisions in force come over too, labelled \(bridge.name)." : "Notes only: its Ledger stays private. Add --with-ledger to share its decisions in force.")
    print("Paths from it read like \"\(bridge.label("notes/plan.md"))\". Remove it with: burrow unbridge \(vault.root.path) \(bridge.name.contains(" ") ? "\"\(bridge.name)\"" : bridge.name)")
}

private func unbridge(_ options: Options) throws {
    guard options.positional.count >= 2 else { throw Failure("unbridge needs a vault and a bridge name: burrow unbridge <vault> <name>") }
    let vault = try existingVault(options.positional[0], "unbridge")
    do {
        let gone = try vault.removeBridge(options.positional[1])
        print("removed the bridge to \(gone.name) (\(gone.path)). Nothing in either vault was changed.")
    } catch let problem as NoteProblem {
        throw Failure(problem.description)
    }
}

private func config(_ options: Options) throws {
    let global = options.flags.contains("--global")
    var words = options.positional
    var settings: BurrowConfig
    var vault: Vault?
    if global {
        settings = BurrowConfig.global()
    } else {
        guard let folder = words.first else { throw Failure("config needs a vault folder, or --global") }
        words.removeFirst()
        let opened = try existingVault(folder, "config")
        vault = opened
        settings = opened.config
    }
    let action = words.first ?? "list"
    let whose = global ? "every vault" : vault!.root.path
    switch action {
    case "list":
        for key in BurrowConfig.keys where global ? key.scope != .vault : key.scope != .global {
            print("\(key.name) = \(settings.value(key.name) ?? "(not set)")\n    \(key.help)")
        }
        print("Kept in \(settings.file.path).")
    case "get":
        guard words.count >= 2 else { throw Failure("config get needs a key") }
        print(settings.value(words[1]) ?? "(not set)")
    case "set":
        guard words.count >= 3 else { throw Failure("config set needs a key and a value, such as: set storage.limit 2GB") }
        do { try settings.set(words[1], words[2...].joined(separator: " ")) } catch let problem as ConfigProblem { throw Failure(problem.description) }
        let key = words[1].lowercased()
        print("\(key) = \(settings.value(words[1]) ?? "") for \(whose).")
        if key == "storage.limit", let bytes = settings.storageLimit {
            if let vault {
                KnownVaults.remember(vault)
                let used = try vault.storageUsage().total
                print("Burrow's store for this vault holds \(ByteSize.format(used)) of \(ByteSize.format(bytes)). Your own files are never counted.")
            } else {
                print("That is for Burrow's stores of all the vaults it knows together (\(KnownVaults.list().count) so far). Your own files are never counted.")
            }
        }
    case "unset":
        guard words.count >= 2 else { throw Failure("config unset needs a key") }
        do {
            let had = try settings.unset(words[1])
            print(had ? "\(words[1]) removed for \(whose)." : "\(words[1]) was not set for \(whose).")
        } catch let problem as ConfigProblem { throw Failure(problem.description) }
    default:
        throw Failure("config takes list, get, set or unset")
    }
}

/// The storage lines `burrow stats` ends with (D-98).
func storageLines(_ vault: Vault) throws -> [String] {
    let report = try vault.storageReport(ownFiles: true)
    let usage = report.usage
    var lines: [String] = []
    let parts = "index \(ByteSize.format(usage.index)), meaning search \(ByteSize.format(usage.vectorCache)), conversations, Ledger and the rest \(ByteSize.format(usage.other))"
    if let limit = report.limit, let share = report.share {
        lines.append("Burrow's store for this vault: \(ByteSize.format(usage.total)) of its \(ByteSize.format(limit)) limit (\(Int((share * 100).rounded()))%): \(parts)")
        if share >= 1 { lines.append("  Over the limit: indexing adds nothing more until it is raised or files are removed.") }
        else if share >= StorageReport.nearShare { lines.append("  Near the limit: \(ByteSize.format(limit - usage.total)) left.") }
    } else {
        lines.append("Burrow's store for this vault: \(ByteSize.format(usage.total)), no limit set: \(parts)")
    }
    let vaults = "\(report.vaultCount) vault\(report.vaultCount == 1 ? "" : "s")"
    if let globalLimit = report.globalLimit, let share = report.globalShare {
        lines.append("All \(vaults) Burrow knows: \(ByteSize.format(report.allVaults)) of the global \(ByteSize.format(globalLimit)) limit (\(Int((share * 100).rounded()))%)"
            + (share >= 1 ? ", full: indexing adds nothing more until it is raised" : share >= StorageReport.nearShare ? ", near the limit" : ""))
    } else {
        lines.append("All \(vaults) Burrow knows: \(ByteSize.format(report.allVaults)), no global limit set")
    }
    if let own = report.ownFiles { lines.append("Your own files in the vault folder: \(ByteSize.format(own)), never counted against a limit and never deleted") }
    for shelf in vault.bridgedShelves() {
        lines.append("Bridged to \(shelf.bridge.name) (\(shelf.bridge.path)), read-only, \(shelf.bridge.withLedger ? "with its decisions" : "notes only"): \(shelf.problem ?? "\(shelf.files.count) files"); it costs this vault no storage")
    }
    return lines
}
