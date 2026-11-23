import CAMRChat
import CAMRCore
import CAMRMCP
import CAMRTUI
import CAMRTools
import Foundation

func logToStandardError(_ line: String) {
    FileHandle.standardError.write(Data("camr: \(line)\n".utf8))
}

/// Opens a vault of everything. The folder has to exist already, so a mistyped path doesn't quietly become a new vault.
/// - Parameter sayLinks: false where the line about unapproved linked folders would reach a model rather than the
///   person (Claude Code reads a hook's stderr), or where the command is about those folders itself.
func openVault(_ path: String, store: String?, sayLinks: Bool = true) throws -> Vault {
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else {
        throw Failure("\(path) is not a folder")
    }
    // Only a folder the person made a vault is opened; any other is refused before anything is written (D-114).
    guard Vault.hasIndex(URL(fileURLWithPath: path), store: store.map { URL(fileURLWithPath: $0) }) else { throw Failure(Vault.notAVault(path)) }
    let vault = try Vault(project: URL(fileURLWithPath: path), store: store.map { URL(fileURLWithPath: $0) }, everything: true)
    meetLinks(vault, say: sayLinks)
    return vault
}

/// Every command that opens a vault: a linked folder the person on this Mac has not approved is taken out of the index
/// and skipped (D-101), and the person is told once, in one plain line, how to approve it. Names and paths only when
/// stderr is a terminal; through a pipe, where a connected program with a shell may be the reader, only a count (D-104).
func meetLinks(_ vault: Vault, say: Bool = true) {
    do { try vault.dropUnapprovedFromIndex() } catch { logToStandardError("could not take unapproved linked folders out of the index: \(error)") }
    if say, let line = vault.linksAwaitingApprovalLine(detailed: isatty(STDERR_FILENO) == 1) { logToStandardError(line) }
}

/// Why camr won't take this as the person in their own terminal, or nil when nothing says otherwise (D-104, D-113):
/// stdin and stderr must be terminals (a program's shell tool gives pipes), no agent's variables may be set, and no
/// agent may be among camr's parents or own the session its terminal belongs to (`PersonPresence`).
func whyNotThePerson() -> String? {
    guard isatty(STDIN_FILENO) == 1, isatty(STDERR_FILENO) == 1 else { return "it isn't running in a terminal" }
    return PersonPresence.refusal()?.reason
}

/// True when camr runs in a person's own terminal, where what it asks is shown and the answer is typed, and nothing
/// says a program connected to CAMR is the one running it (D-104, D-113).
func inPersonsTerminal() -> Bool { whyNotThePerson() == nil }

/// Said when a step only the person may take is run without a terminal (D-104). Each step says what it is: a refusal
/// that names another step (every yes-prompt once said "approve a linked folder") misleads the person (D-115).
let needsThePerson = "only you can allow this: run it in your own terminal and type yes. It can't be done through a pipe or by a program you've connected to CAMR."
/// The same for approving or linking a folder, which the CAMR app can also do.
let linkNeedsThePerson = "only you can approve a linked folder: approve it in the CAMR app, or run this in your own terminal. It can't be done through a pipe or by a program you've connected to CAMR."

/// The one call for every step only the person may take (D-113): throws `refusal`, with the reason, unless camr is in
/// the person's own terminal and nothing says an agent is running it.
func requireThePerson(_ refusal: String = needsThePerson) throws {
    if let why = whyNotThePerson() { throw Failure("\(refusal) Refused because \(why).") }
}

/// Layer 3 (D-113), for a step that defeats the gate: this process makes an eight-digit code, shows it in a macOS
/// notification, and the person types it here; the comparison is in this process's memory, so nothing written to disk
/// can make a code valid. Never printed, so a program driving this terminal can't read it. Throws unless the right
/// code is typed within 2 minutes, in at most 3 tries.
func askForCode(_ action: String) throws {
    let state = CAMRPlaces.stateFolder
    let challenge: PersonCode.Challenge
    do { challenge = try PersonCode.issue(action: action, state: state) } catch { throw Failure("\(error)") }
    defer { PersonCode.record(challenge, state: state) }
    let place: String
    switch PersonCode.show(challenge) {
    case .notification: place = "in a notification (top right of your screen)"
    case .testHook: place = "in the test's code file"
    case .nowhere:
        challenge.abandon()
        throw Failure("CAMR could not show a code outside this terminal (the notification failed; allow notifications for Script Editor in System Settings). Nothing was allowed.")
    }
    FileHandle.standardError.write(Data("CAMR showed an \(PersonCode.digits)-digit code \(place). It is never printed here, so a program running this terminal can't see it.\n".utf8))
    while true {
        FileHandle.standardError.write(Data("Type the code (valid 2 minutes): ".utf8))
        guard let typed = readLine(strippingNewline: true) else {
            challenge.abandon()
            throw Failure("no code was typed: nothing was allowed")
        }
        switch challenge.verify(typed) {
        case .accepted: return
        case let .wrong(left): FileHandle.standardError.write(Data("That isn't the code. \(left) \(left == 1 ? "try" : "tries") left.\n".utf8))
        case .expired: throw Failure("the code expired: nothing was allowed. Run the command again for a new one.")
        case .spent: throw Failure("that code can't be used any more: nothing was allowed. Run the command again for a new one.")
        }
    }
}

/// Shows the person what they are about to allow and waits for them to type yes. Throws for anything else. With
/// `code`, the person first types the code CAMR showed outside the terminal (D-113); the typed yes is always last.
func askThePerson(_ lines: [String], code action: String? = nil, refusal: String = needsThePerson) throws {
    try requireThePerson(refusal)
    FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    if let action { try askForCode(action) }
    FileHandle.standardError.write(Data("Type yes to allow, anything else to stop: ".utf8))
    let answer = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces).lowercased()
    guard answer == "yes" else { throw Failure("nothing was approved") }
}

/// A linked folder as the person is asked about it: its name, and the real path CAMR would read.
private func shownForApproval(_ state: LinkState) -> String {
    let real = Printable.clean(state.realPath)
    let listed = state.leadsElsewhere ? " (listed as \(Printable.clean(state.folder.path)))" : ""
    return "  \(Printable.clean(state.folder.name))   \(real)\(listed)\(state.exists ? "" : "   (folder not found)")"
}

/// This folder if it already has a CAMR index, or else the vault opened or made last. Never a folder CAMR hasn't been pointed at.
private func defaultVault() -> String? {
    let here = FileManager.default.currentDirectoryPath
    if Vault.hasIndex(URL(fileURLWithPath: here)) { return here }
    return LastVault.read().flatMap { Vault.hasIndex(URL(fileURLWithPath: $0)) ? $0 : nil }
}

private func runFullScreen(_ folder: String, store: String?, model: String) throws {
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder, isDirectory: &isFolder), isFolder.boolValue else { throw Failure("\(folder) is not a folder") }
    let url = URL(fileURLWithPath: folder).standardizedFileURL
    // Said before the full screen starts, so it is still there when it ends; the screen shows it too.
    _ = try openVault(folder, store: store)
    do {
        let app = try TerminalApp(vaultFolder: url, store: store.map { URL(fileURLWithPath: $0) }, modelName: model)
        LastVault.write(url.path)
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
            throw Failure("no vault here yet. Open one with: camr tui <vault-folder>\n\n\(usage)")
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
    // `camr link list <vault>` and `camr link approve <vault> …` (D-101). A vault folder called "list" or "approve"
    // is named ./list.
    if command == "link", ["list", "approve"].contains(folder) {
        try await linkApprovals(folder, Array(options.positional.dropFirst()), all: options.flags.contains("--all"), store: options.values["--store"])
        return true
    }
    let vault = try openVault(folder, store: options.values["--store"], sayLinks: command != "link")
    switch command {
    case "mcp":
        // Whatever this server starts (a decision check through camr_check) is never taken for the person (D-113).
        setenv(PersonPresence.mcpMarker, "1", 1)
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
        // With --llama, a llama.cpp server answers, and a resumed session's working memory is saved and loaded (D-118).
        let llama = options.values["--llama"].flatMap { URL(string: $0) }
        let backend: ChatBackend
        if let llama { backend = LlamaChat(base: llama, model: options.values["--model"] ?? "llama.cpp") } else {
            let ollama = OllamaChat(model: model)
            // Loaded while the vault is read and the first question typed, with the window chat answers in (D-114).
            let window = ollama.contextWords
            Task.detached { try? await Ollama().warm(model: model, contextWords: window) }
            backend = ollama
        }
        let session = ChatSession(tools: tools, backend: backend, settings: settings)
        var cache: ChatREPL.Cache?
        // --resume picks up any archived session, from Claude Code, Codex or anywhere else CAMR keeps (D-117).
        if let name = options.values["--resume"] {
            let places = SessionHooks.Places()
            let found = places.archive.find(name)
            guard let meta = found.first else { throw Failure("no archived session matches \(name); camr session lists them") }
            guard found.count == 1 || meta.id.lowercased().hasPrefix(name.lowercased()) else {
                throw Failure("\(found.count) sessions match \(name); give one id from camr session")
            }
            let pack = SessionTools.session(meta.id, find: nil, timeline: nil, ref: nil, client: nil, places: places)
            session.resumed = pack.text
            logToStandardError("resuming session \(meta.id.prefix(8)): \"\(meta.name)\" (\(pack.text.count) characters handed over)")
            if let llama { cache = ChatREPL.Cache(shelf: KVShelf(vault: vault), server: llama, conversation: "session-" + meta.id) }
        }
        await ChatREPL(session: session, tools: tools, backend: backend, cache: cache).run()
    case "link":
        guard options.positional.count > 1 else { throw Failure("link needs a code folder") }
        let target = URL(fileURLWithPath: options.positional[1])
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isFolder), isFolder.boolValue else { throw Failure("\(target.path) is not a folder") }
        // Linking here approves the folder, so it needs the person in their own terminal too (D-104): otherwise a
        // connected program could link, and so approve, any folder on this Mac.
        try requireThePerson(linkNeedsThePerson)
        let real = Vault.realPath(target.path)
        let path = target.standardizedFileURL.path
        try askThePerson([
            "Link this folder into \(Printable.clean(vault.root.path)) and approve it on this Mac?",
            "  \(Printable.clean(real))\(!LinkState.samePlace(real, path) ? " (you named \(Printable.clean(path)))" : "")",
            "CAMR reads it where it is and never changes it. Search, Ask and every program you connect to this vault can read it.",
        ])
        let linked: LinkedFolder
        do { linked = try vault.linkFolder(target, expected: real) } catch let problem as NoteProblem { throw Failure(problem.description) }
        print("linked \(Printable.clean(linked.path)) as \(Printable.clean(linked.name)), read-only, approved on this Mac")
        if let line = vault.linksAwaitingApprovalLine(detailed: true) { logToStandardError(line) }
    default: break
    }
    return true
}

/// Shows which linked folders the person on this Mac has approved, or approves some (D-101). Approving brings them back
/// into the index at once, so a link made before approvals existed works again after this one step.
private func linkApprovals(_ action: String, _ words: [String], all: Bool, store: String?) async throws {
    guard let folder = words.first else {
        throw Failure(action == "list" ? "link list needs a vault folder: camr link list <vault>"
                                       : "link approve needs a vault folder: camr link approve <vault> <folder>")
    }
    // Approving needs the person in their own terminal (D-104), checked before anything is opened.
    if action == "approve" { try requireThePerson(linkNeedsThePerson) }
    let vault = try openVault(folder, store: store, sayLinks: false)
    // Everything printed from the vault's list is cleaned of control characters, since anyone who shared the vault could
    // have written it (D-104), and every suggested command quotes its words so a pasted path can't run anything.
    let shown = Printable.shellWord(vault.root.path)
    let states = vault.linkStates()
    if action == "list" {
        guard !states.isEmpty else {
            print("\(Printable.clean(vault.root.path)) links no folders. Link one with: camr link \(shown) <folder>")
            return
        }
        for state in states {
            let place = state.leadsElsewhere ? "\(Printable.clean(state.folder.path)) -> \(Printable.clean(state.realPath))" : Printable.clean(state.folder.path)
            let missing = state.exists ? "" : " (folder not found)"
            let name = Printable.clean(state.folder.name)
            if let why = state.refusal {
                print("\(name)   \(place)\(missing)   never followed: \(why)")
            } else if state.approved {
                print("\(name)   \(place)\(missing)   approved")
            } else {
                print("\(name)   \(place)\(missing)   not approved on this Mac, so skipped. If you linked it yourself, approve it in the CAMR app, or in your own terminal with: camr link approve \(shown) \(Printable.shellWord(state.realPath))")
            }
        }
        return
    }
    let names = Array(words.dropFirst())
    guard all || !names.isEmpty else {
        throw Failure("say which to approve, by its path from camr link list \(shown): camr link approve \(shown) <folder>")
    }
    guard !states.isEmpty else {
        print("\(Printable.clean(vault.root.path)) links no folders, so there is nothing to approve.")
        return
    }
    let chosen: [LinkState]
    do { chosen = try vault.linksToApprove(all ? nil : names) } catch let problem as NoteProblem { throw Failure(problem.description) }
    guard !chosen.isEmpty else {
        print("Nothing on \(Printable.clean(vault.root.path))'s list of linked folders can be approved. See camr link list \(shown)")
        return
    }
    // The real paths are what is approved, and what the person is shown; the list changing before they answer approves
    // nothing (Vault.approve).
    try askThePerson([
        "Approve \(chosen.count == 1 ? "this folder" : "these \(chosen.count) folders") for \(Printable.clean(vault.root.path)) on this Mac?"]
        + chosen.map(shownForApproval)
        + ["A vault's list of linked folders can come from whoever shared the vault with you. Approve only folders you linked yourself.",
           "Approved, CAMR reads \(chosen.count == 1 ? "it" : "them") where \(chosen.count == 1 ? "it is" : "they are"), and search, Ask and every program you connect to this vault can read \(chosen.count == 1 ? "it" : "them")."])
    let approved: [LinkState]
    do { approved = try vault.approve(chosen) } catch let problem as NoteProblem { throw Failure(problem.description) }
    for state in approved { print("approved \(Printable.clean(state.folder.name)) (\(Printable.clean(state.realPath))) for \(Printable.clean(vault.root.lastPathComponent)) on this Mac") }
    // Back into the index now, by meaning too when the vault already searches by meaning.
    let ollama = Ollama()
    var report: IndexReport
    var how = ""
    do {
        report = try await vault.refresh(embedder: try embedderIfIndexed(vault, ollama))
    } catch where OllamaReach.isUnreachable(error) {
        report = try await vault.refresh()
        how = " by words only, because Ollama isn't running; run camr index \(shown) --vault later for meaning search"
    }
    print("indexed again\(how): \(report.filesChanged) files added or changed, \(report.chunks) chunks in all.")
    if let stop = report.storageStop { throw Failure(stop.message) }
}
