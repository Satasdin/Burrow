import BurrowCore
import BurrowTools
import Foundation

let vaultUsage = """
Several vaults, and how much Burrow keeps:
  burrow vault new <folder> [--name N] [--no-embed]               make a folder a vault and build its index
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
    let vault = try Vault(project: URL(fileURLWithPath: path), everything: true)
    meetLinks(vault)
    return vault
}

private func newVault(_ options: Options) async throws {
    guard options.positional.first == "new", options.positional.count > 1 else {
        throw Failure("make a vault with: burrow vault new <folder> [--name N]")
    }
    let path = options.positional[1]
    let url = URL(fileURLWithPath: path).standardizedFileURL
    if FileManager.default.fileExists(atPath: url.appendingPathComponent(".burrow/index.sqlite").path) {
        throw Failure("\(url.path) is a vault already. Open it with burrow tui \(url.path), or rebuild its index with burrow index \(url.path) --vault")
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
    // A folder from someone else can already hold a list of linked folders; none of them was read (D-101).
    meetLinks(vault)
    let name = vault.config.value("vault.name").map { " called \($0)" } ?? ""
    print("\(made ? "made" : "opened") \(url.path) as a vault\(name): \(report.filesSeen) files indexed \(how).")
    print("Next: put notes in it, link a code folder (burrow link \(url.path) <folder>), or bridge it from another vault (burrow bridge <vault> \(url.path)).")
    if let stop = report.storageStop { throw Failure(stop.message) }
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
