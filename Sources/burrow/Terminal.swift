import BurrowChat
import BurrowCore
import BurrowMCP
import BurrowTUI
import BurrowTools
import Foundation

func logToStandardError(_ line: String) {
    FileHandle.standardError.write(Data("burrow: \(line)\n".utf8))
}

/// Opens a vault of everything. The folder has to exist already, so a mistyped path doesn't quietly become a new vault.
/// - Parameter sayLinks: false where the line about unapproved linked folders would reach a model rather than the
///   person (Claude Code reads a hook's stderr), or where the command is about those folders itself.
func openVault(_ path: String, store: String?, sayLinks: Bool = true) throws -> Vault {
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else {
        throw Failure("\(path) is not a folder")
    }
    let vault = try Vault(project: URL(fileURLWithPath: path), store: store.map { URL(fileURLWithPath: $0) }, everything: true)
    meetLinks(vault, say: sayLinks)
    return vault
}

/// Every command that opens a vault: a linked folder the person on this Mac has not approved is taken out of the index
/// and skipped (D-101), and the person is told once, in one plain line, how to approve it.
func meetLinks(_ vault: Vault, say: Bool = true) {
    do { try vault.dropUnapprovedFromIndex() } catch { logToStandardError("could not take unapproved linked folders out of the index: \(error)") }
    if say, let line = vault.linksAwaitingApprovalLine() { logToStandardError(line) }
}

/// Where the last-opened vault is remembered, so `burrow` alone can go back to it.
private func stateFile() -> URL {
    if let folder = ProcessInfo.processInfo.environment["BURROW_STATE_DIR"] {
        return URL(fileURLWithPath: folder).appendingPathComponent("last-vault")
    }
    return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Burrow/last-vault")
}

/// This folder if it already has a Burrow index, or else the vault opened last. Never a folder Burrow hasn't been pointed at.
private func defaultVault() -> String? {
    let here = FileManager.default.currentDirectoryPath
    if FileManager.default.fileExists(atPath: here + "/.burrow/index.sqlite") { return here }
    guard let saved = try? String(contentsOf: stateFile(), encoding: .utf8) else { return nil }
    let path = saved.trimmingCharacters(in: .whitespacesAndNewlines)
    return FileManager.default.fileExists(atPath: path) ? path : nil
}

private func runFullScreen(_ folder: String, store: String?, model: String) throws {
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder, isDirectory: &isFolder), isFolder.boolValue else { throw Failure("\(folder) is not a folder") }
    let url = URL(fileURLWithPath: folder).standardizedFileURL
    // Said before the full screen starts, so it is still there when it ends; the screen shows it too.
    _ = try openVault(folder, store: store)
    do {
        let app = try TerminalApp(vaultFolder: url, store: store.map { URL(fileURLWithPath: $0) }, modelName: model)
        try? FileManager.default.createDirectory(at: stateFile().deletingLastPathComponent(), withIntermediateDirectories: true)
        try? url.path.write(to: stateFile(), atomically: true, encoding: .utf8)
        app.run()
    } catch let problem as TerminalApp.Failure {
        throw Failure(problem.description)
    }
}

/// The commands that keep a whole vault open. Returns false for anything the older commands should handle.
func runTerminalCommand(_ arguments: [String]) async throws -> Bool {
    if arguments.isEmpty {
        // A pipe or a script keeps getting the plain usage text, as it always has.
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else { return false }
        guard let folder = defaultVault() else {
            throw Failure("no vault here yet. Open one with: burrow tui <vault-folder>\n\n\(usage)")
        }
        try runFullScreen(folder, store: nil, model: Ollama.defaultModel)
        return true
    }
    let command = arguments[0]
    guard ["mcp", "link", "chat", "tui"].contains(command) else { return false }
    let options = try Options(Array(arguments.dropFirst()))
    guard let folder = options.positional.first else { throw Failure(usage) }
    if command == "tui" {
        try runFullScreen(folder, store: options.values["--store"], model: options.values["--model"] ?? Ollama.defaultModel)
        return true
    }
    // `burrow link list <vault>` and `burrow link approve <vault> …` (D-101). A vault folder called "list" or "approve"
    // is named ./list.
    if command == "link", ["list", "approve"].contains(folder) {
        try await linkApprovals(folder, Array(options.positional.dropFirst()), all: options.flags.contains("--all"), store: options.values["--store"])
        return true
    }
    let vault = try openVault(folder, store: options.values["--store"], sayLinks: command != "link")
    switch command {
    case "mcp":
        let output = ProtocolOutput()
        let tools = VaultTools.onThisMac(vault: vault, model: options.values["--model"] ?? Ollama.defaultModel, log: logToStandardError)
        logToStandardError("MCP server for \(vault.root.path)")
        let server = MCPServer(tools: tools, keepsSessions: !options.flags.contains("--no-sessions"), log: logToStandardError)
        guard let set = ToolSet(rawValue: options.values["--tools"] ?? "door") else { throw Failure("--tools takes door, full or classic") }
        server.toolSet = set
        server.endsOnSignals = true
        // Baseline arms of Evaluation 3 only: the search without the trust line, or without Ledger notes.
        if options.flags.contains("--no-trust") { tools.trustLinesOn = false }
        if options.flags.contains("--no-ledger-notes") { tools.ledgerNotesOn = false }
        if let address = options.values["--llama"], let url = URL(string: address) {
            // Whatever a lookup returns is also read into the model's cache on a spare slot, after the reply (D-60).
            let store = options.values["--store"]
            let warmer = KVWarmer(settings: KVWarmer.Settings(server: url), open: { try openVault(folder, store: store, sayLinks: false) }, log: logToStandardError)
            if case let .ready(model, _, window) = await warmer.connect() { tools.packWindow = window; tools.servingModel = model }
            server.afterCall = { name, arguments, result in
                if name == "vault_pack" {
                    let part = (arguments["part"] as? NSNumber)?.intValue ?? Int("\(arguments["part"] ?? 1)") ?? 1
                    warmer.asked(scope: (arguments["folder"] as? String) ?? "", part: part)
                } else {
                    warmer.noticed(result.sources.map(\.path))
                }
            }
        }
        await server.serve(readLine: { Swift.readLine() }, write: output.write)
    case "chat":
        let model = options.values["--model"] ?? Ollama.defaultModel
        // Half the usual search allowance, so two searches and a read still fit in the model's context.
        let tools = VaultTools.onThisMac(vault: vault, model: model, searchCharacters: 6_000, log: { _ in })
        if let folder = options.values["--folder"] {
            await tools.freshen(checkNow: true)
            let clean = folder.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
            guard try tools.folderNames().contains(clean) else { throw Failure("there is no folder called \(clean) in this vault") }
            tools.fixedFolder = clean
        }
        var settings = ChatSession.Settings()
        settings.alwaysSearchFirst = !options.flags.contains("--tools-only")
        let backend = OllamaChat(model: model)
        await ChatREPL(session: ChatSession(tools: tools, backend: backend, settings: settings), tools: tools, backend: backend).run()
    case "link":
        guard options.positional.count > 1 else { throw Failure("link needs a code folder") }
        let target = URL(fileURLWithPath: options.positional[1])
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isFolder), isFolder.boolValue else { throw Failure("\(target.path) is not a folder") }
        let linked: LinkedFolder
        do { linked = try vault.linkFolder(target) } catch let problem as NoteProblem { throw Failure(problem.description) }
        print("linked \(linked.path) as \(linked.name), read-only, approved on this Mac")
        if let line = vault.linksAwaitingApprovalLine() { logToStandardError(line) }
    default: break
    }
    return true
}

/// Shows which linked folders the person on this Mac has approved, or approves some (D-101). Approving brings them back
/// into the index at once, so a link made before approvals existed works again after this one step.
private func linkApprovals(_ action: String, _ words: [String], all: Bool, store: String?) async throws {
    guard let folder = words.first else {
        throw Failure(action == "list" ? "link list needs a vault folder: burrow link list <vault>"
                                       : "link approve needs a vault folder: burrow link approve <vault> --all | <folder>")
    }
    let vault = try openVault(folder, store: store, sayLinks: false)
    let shown = vault.root.path.contains(" ") ? "\"\(vault.root.path)\"" : vault.root.path
    let states = vault.linkStates()
    if action == "list" {
        guard !states.isEmpty else {
            print("\(vault.root.path) links no folders. Link one with: burrow link \(shown) <folder>")
            return
        }
        for state in states {
            let place = state.leadsElsewhere ? "\(state.folder.path) -> \(state.realPath)" : state.folder.path
            let missing = state.exists ? "" : " (folder not found)"
            if state.approved {
                print("\(state.folder.name)   \(place)\(missing)   approved")
            } else {
                let name = state.folder.name.contains(" ") ? "\"\(state.folder.name)\"" : state.folder.name
                print("\(state.folder.name)   \(place)\(missing)   not approved on this Mac, so skipped. Approve it with: burrow link approve \(shown) \(name)")
            }
        }
        return
    }
    let names = Array(words.dropFirst())
    guard all || !names.isEmpty else {
        throw Failure("say which to approve: burrow link approve \(shown) --all, or a folder's name from burrow link list \(shown)")
    }
    guard !states.isEmpty else {
        print("\(vault.root.path) links no folders, so there is nothing to approve.")
        return
    }
    let approved: [LinkedFolder]
    do { approved = try vault.approveLinks(all ? nil : names) } catch let problem as NoteProblem { throw Failure(problem.description) }
    for folder in approved { print("approved \(folder.name) (\(folder.path)) for \(vault.root.lastPathComponent) on this Mac") }
    // Back into the index now, by meaning too when the vault already searches by meaning.
    let ollama = Ollama()
    var report: IndexReport
    var how = ""
    do {
        report = try await vault.refresh(embedder: try embedderIfIndexed(vault, ollama))
    } catch where OllamaReach.isUnreachable(error) {
        report = try await vault.refresh()
        how = " by words only, because Ollama isn't running; run burrow index \(shown) --vault later for meaning search"
    }
    print("indexed again\(how): \(report.filesChanged) files added or changed, \(report.chunks) chunks in all.")
    if let stop = report.storageStop { throw Failure(stop.message) }
}
