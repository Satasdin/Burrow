@testable import BurrowCore
@testable import BurrowTools
import Foundation
import XCTest

/// The real `burrow` binary, run the two ways it meets the world: through pipes, as a program connected to Burrow runs it
/// from its own shell tool, and in a pseudo-terminal, as the person runs it in Terminal.
enum BurrowBinary {
    static var url: URL { Bundle(for: LinkApprovalHardeningTests.self).bundleURL.deletingLastPathComponent().appendingPathComponent("burrow") }

    static func environment(_ state: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["BURROW_STATE_DIR"] = state.path
        return environment
    }

    /// Through pipes: stdin, stdout and stderr are none of them a terminal.
    static func piped(_ arguments: [String], state: URL, input: String = "") throws -> (status: Int32, out: String, err: String) {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        process.environment = environment(state)
        let feed = Pipe(), out = Pipe(), err = Pipe()
        process.standardInput = feed
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: watchdog)
        feed.fileHandleForWriting.write(Data(input.utf8))
        try feed.fileHandleForWriting.close()
        let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func add(_ more: Data) { lock.lock(); data.append(more); lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    }

    /// What to type when burrow asks for the one-time code it shows outside the terminal (D-113).
    enum CodeAnswer {
        /// Nothing: the input ends, as if the person walked away.
        case none
        /// The code burrow showed, read through the debug-only BURROW_TEST_CODE_FILE hook, as the person reads it off
        /// the notification or the app.
        case shown
        /// These words, every time it asks.
        case typed(String)
    }

    /// Every variable an agent sets (D-113), taken out: the environment of the person's own Terminal.
    static func personsEnvironment(_ state: URL) -> [String: String] {
        var environment = environment(state)
        for name in PersonPresence.markers.keys { environment[name] = nil }
        return environment
    }

    /// In a pseudo-terminal made by `script`, the same kind of terminal Terminal.app gives a shell. When burrow asks the
    /// person to type yes, `answer` is typed; when it asks for its one-time code, `code`. stdout and stderr arrive
    /// together, as on a screen, with line ends as "\n".
    ///
    /// These tests may themselves run inside an agent (Claude Code runs `swift test`), which burrow refuses (D-113). So
    /// unless `detached` is false, the terminal is started the way a program set on it could: every agent variable taken
    /// out, and `script` detached from this process tree (its parent exits, so launchd adopts it). That is exactly the
    /// path layers 1 and 2 can't stop, which is why the steps that defeat the gate also need the code.
    static func inTerminal(_ arguments: [String], state: URL, answer: String? = nil, code: CodeAnswer = .none,
                           detached: Bool = true, environment extra: [String: String] = [:]) throws -> (status: Int32, out: String) {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path), "build burrow first: \(url.path)")
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        let codeFile = state.appendingPathComponent("shown-code-\(UUID().uuidString)")
        let statusFile = state.appendingPathComponent("status-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: codeFile); try? FileManager.default.removeItem(at: statusFile) }
        let process = Process()
        var environment = detached ? personsEnvironment(state) : environment(state)
        environment["BURROW_TEST_CODE_FILE"] = codeFile.path
        environment["BURROW_TEST_STATUS"] = statusFile.path
        for (key, value) in extra { environment[key] = value }
        process.environment = environment
        let command = ["/usr/bin/script", "-q", "/dev/null", url.path] + arguments
        if detached {
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "exec 3<&0; ( sleep 0.3; \"$@\" <&3; echo $? > \"$BURROW_TEST_STATUS\" ) & exit 0", "sh"] + command
        } else {
            process.executableURL = URL(fileURLWithPath: command[0])
            process.arguments = Array(command.dropFirst())
        }
        let feed = Pipe(), out = Pipe()
        process.standardInput = feed
        process.standardOutput = out
        process.standardError = out
        let collected = Collected()
        let ended = Collected()
        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { ended.add(Data("eof".utf8)); handle.readabilityHandler = nil } else { collected.add(data) }
        }
        try process.run()
        let deadline = Date().addingTimeInterval(60)
        var answered = false, codesTyped = 0, closed = false
        func close() { if !closed { try? feed.fileHandleForWriting.close(); closed = true } }
        while ended.text.isEmpty, Date() < deadline {
            let text = collected.text
            // Typed only once burrow has asked, as a person would.
            let asks = text.components(separatedBy: "Type the code").count - 1
            if asks > codesTyped, !closed {
                codesTyped = asks
                switch code {
                case .none: close()
                case .shown: feed.fileHandleForWriting.write(Data(((try? String(contentsOf: codeFile, encoding: .utf8)) ?? "") .appending("\n").utf8))
                case let .typed(words): feed.fileHandleForWriting.write(Data((words + "\n").utf8))
                }
            }
            if !answered, !closed, let answer, text.contains("Type yes") {
                feed.fileHandleForWriting.write(Data((answer + "\n").utf8))
                answered = true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        close()
        process.waitUntilExit()
        if !detached { return (process.terminationStatus, collected.text.replacingOccurrences(of: "\r\n", with: "\n")) }
        var status: Int32 = -1
        for _ in 0..<40 {
            if let text = try? String(contentsOf: statusFile, encoding: .utf8), let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) { status = value; break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return (status, collected.text.replacingOccurrences(of: "\r\n", with: "\n"))
    }
}

/// D-104: three findings of a security review of D-101's approvals. What a vault's list of linked folders names is printed
/// cleaned; a reader gets the real path the approval was checked against, so a symlink swapped after approval is not
/// followed; Burrow's own store, the vault and folders holding it are never followed; and only a person in their own
/// terminal (or the app's sheet) can approve, never a program running burrow through pipes.
final class LinkApprovalHardeningTests: XCTestCase {
    private var top: URL!
    private var state: URL { top.appendingPathComponent("state") }
    private var home: URL { top.appendingPathComponent("Home") }
    private var code: URL { top.appendingPathComponent("Code") }
    private var privateFolder: URL { top.appendingPathComponent("Private") }
    private let secret = "jacaranda-42"
    /// A name that, printed as it is, would retitle the terminal window, clear the screen, ring the bell and reverse what
    /// follows it on the line.
    private let evilName = "Code\u{1b}]0;pwned\u{07}\u{1b}[2J\u{1b}[1;1H\u{9b}31m\u{202e}txt.exe"

    override func setUp() async throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("link-hardening-" + UUID().uuidString)
        for (path, text) in [
            "Home/Rent.md": "# Rent\n\nRent for the Kilimani flat is due on the fifth.\n",
            "Private/Diary.md": "# Diary\n\nThe kitty password is \(secret). The diary is private.\n",
            "Code/fares.py": "def matatu_fare(stage):\n    return 70 * stage\n",
        ] {
            let url = top.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: top) }

    private func open(_ folder: URL) throws -> Vault {
        let vault = try Vault(project: folder, everything: true)
        vault.stateFolder = state
        return vault
    }

    private func plant(_ folders: [(String, String)], in vault: URL) throws {
        let store = vault.appendingPathComponent(".burrow")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try JSONEncoder().encode(folders.map { LinkedFolder(name: $0.0, path: $0.1) }).write(to: store.appendingPathComponent("folders.json"))
    }

    private func controls(in text: String) -> [String] {
        text.unicodeScalars.filter(Printable.isControl).filter { $0 != "\n" && $0 != "\t" }.map { String(format: "U+%04X", $0.value) }
    }

    private func approvals() -> String { (try? String(contentsOf: LinkApprovalStore.file(in: state), encoding: .utf8)) ?? "" }

    // MARK: 1. Printing what the vault's list says

    func testPrintableTakesOutControlAndBidiCharactersAndQuotesShellWords() {
        XCTAssertEqual(Printable.clean(evilName), "Code]0;pwned[2J[1;1H31mtxt.exe")
        XCTAssertEqual(Printable.clean("a\u{2066}b\u{2069}c\u{200f}d\u{2028}e\u{7f}f\u{0}g"), "abcdefg")
        XCTAssertEqual(Printable.clean("Café 👩‍💻 Ünïcödé"), "Café 👩‍💻 Ünïcödé", "ordinary text, emoji joiners included, is left alone")
        XCTAssertEqual(Printable.shellWord("/Users/me/code/matatu"), "/Users/me/code/matatu")
        XCTAssertEqual(Printable.shellWord("/tmp/x$(touch /tmp/pwned)"), "'/tmp/x$(touch /tmp/pwned)'")
        XCTAssertEqual(Printable.shellWord("/tmp/it's here"), #"'/tmp/it'\''s here'"#)
        XCTAssertEqual(Printable.shellWord("~/notes"), "'~/notes'", "never expanded by the shell into another folder")
    }

    func testTheSkippedLineIsCleanNamesByRealPathAndNeverSuggestsAll() throws {
        try plant([(evilName, code.path), ("Private", privateFolder.path)], in: home)
        let vault = try open(home)
        let detailed = try XCTUnwrap(vault.linksAwaitingApprovalLine(detailed: true))
        XCTAssertEqual(controls(in: detailed), [], detailed)
        XCTAssertFalse(detailed.contains("--all"), detailed)
        // A name with control characters is never followed; the ordinary one is offered by its real path.
        XCTAssertTrue(detailed.contains("never followed: its name or path has control characters"), detailed)
        XCTAssertTrue(detailed.contains("burrow link approve \(Printable.shellWord(home.path)) \(Printable.shellWord(Vault.realPath(privateFolder.path)))"), detailed)
        XCTAssertTrue(detailed.contains("in the Burrow app"), detailed)
        // Where a program may be reading: a count, no name, no path.
        let counted = try XCTUnwrap(vault.linksAwaitingApprovalLine(detailed: false))
        XCTAssertTrue(counted.hasPrefix("2 linked folders were skipped because they aren't approved on this Mac. Only you can approve them"), counted)
        for leak in ["Code", "Private", privateFolder.path, Vault.realPath(privateFolder.path), "--all"] { XCTAssertFalse(counted.contains(leak), counted) }
        XCTAssertEqual(controls(in: counted), [])
    }

    func testTheCommandLinePrintsAPlantedNameCleanlyInATerminalAndThroughAPipe() throws {
        try plant([(evilName, code.path), ("Private", privateFolder.path)], in: home)
        XCTAssertEqual(try BurrowBinary.piped(["index", home.path, "--vault", "--no-embed"], state: state).status, 0)
        // Through a pipe (a connected program's shell): a count, nothing from the file.
        let piped = try BurrowBinary.piped(["find", home.path, "matatu fare", "--vault"], state: state)
        XCTAssertTrue(piped.err.contains("2 linked folders were skipped"), piped.err)
        XCTAssertFalse(piped.err.contains("pwned") || piped.err.contains("Private"), piped.err)
        XCTAssertEqual(controls(in: piped.err + piped.out), [])
        // In the person's terminal: named, cleaned.
        let shown = try BurrowBinary.inTerminal(["find", home.path, "matatu fare", "--vault"], state: state)
        XCTAssertTrue(shown.out.contains("Code]0;pwned[2J[1;1H31mtxt.exe (\(Vault.realPath(code.path)), never followed"), shown.out)
        XCTAssertEqual(controls(in: shown.out), [], shown.out)
        // link list, both ways.
        for list in [try BurrowBinary.piped(["link", "list", home.path], state: state).out,
                     try BurrowBinary.inTerminal(["link", "list", home.path], state: state).out] {
            XCTAssertEqual(controls(in: list), [], list)
            XCTAssertTrue(list.contains("never followed: its name or path has control characters"), list)
            XCTAssertTrue(list.contains("burrow link approve \(Printable.shellWord(home.path)) \(Printable.shellWord(Vault.realPath(privateFolder.path)))"), list)
            XCTAssertFalse(list.contains("--all"), list)
        }
    }

    // MARK: 2. The real path, checked and used

    func testReadersGetTheCheckedRealPathAndASwappedSymlinkIsNotFollowed() async throws {
        let shortcut = top.appendingPathComponent("shortcut")
        try FileManager.default.createSymbolicLink(at: shortcut, withDestinationURL: code)
        try plant([("shortcut", shortcut.path)], in: home)
        let vault = try open(home)
        try vault.approveLinks([Vault.realPath(code.path)])
        XCTAssertEqual(vault.linkedFolders(), [LinkedFolder(name: "shortcut", path: Vault.realPath(code.path))], "the real path, never the symlink")
        try await vault.refresh()
        XCTAssertTrue(try vault.projectMap().files.contains { $0.path == "shortcut/fares.py" })
        let shown = vault.linkStates()
        // After approval, the symlink is pointed at the private folder.
        try FileManager.default.removeItem(at: shortcut)
        try FileManager.default.createSymbolicLink(at: shortcut, withDestinationURL: privateFolder)
        XCTAssertEqual(vault.linkedFolders(), [], "unapproved again")
        XCTAssertEqual(vault.linksAwaitingApproval().map(\.name), ["shortcut"])
        XCTAssertNil(vault.text(of: "shortcut/Diary.md"))
        try await vault.refresh()
        XCTAssertFalse(try vault.projectMap().files.contains { $0.path.hasPrefix("shortcut/") })
        XCTAssertFalse(try vault.searchLines("kitty").contains { $0.text.contains(secret) })
        let tools = VaultTools(vault: vault, embedder: nil) { _ in FakeAnswerer() }
        let read = try await tools.call("burrow_read", arguments: ["path": "shortcut/Diary.md"])
        XCTAssertFalse(read.text.contains(secret), read.text)
        // What the person was shown before the swap is not what the list says now: approving it approves nothing.
        XCTAssertThrowsError(try vault.approve(shown))
        XCTAssertFalse(approvals().contains(Vault.realPath(privateFolder.path)), approvals())
        // Pointed back, the first approval holds again.
        try FileManager.default.removeItem(at: shortcut)
        try FileManager.default.createSymbolicLink(at: shortcut, withDestinationURL: code)
        XCTAssertEqual(vault.linkedFolders().map(\.name), ["shortcut"])
    }

    func testTheVaultItsStoreAndFoldersHoldingThemAreNeverFollowed() throws {
        let store = home.appendingPathComponent(".burrow")
        try FileManager.default.createDirectory(at: store.appendingPathComponent("ledger"), withIntermediateDirectories: true)
        let refused = [("Itself", home.path), ("Store", store.path), ("Ledger", store.appendingPathComponent("ledger").path),
                       ("Above", top.path), ("Root", "/")]
        try plant(refused + [("Code", code.path)], in: home)
        let vault = try open(home)
        let states = Dictionary(uniqueKeysWithValues: vault.linkStates().map { ($0.folder.name, $0) })
        XCTAssertEqual(states["Itself"]?.refusal, "it is this vault itself")
        XCTAssertEqual(states["Store"]?.refusal, "it is or holds Burrow's own store for this vault")
        XCTAssertEqual(states["Ledger"]?.refusal, "it is or holds Burrow's own store for this vault")
        XCTAssertEqual(states["Above"]?.refusal, "it holds this vault")
        XCTAssertEqual(states["Root"]?.refusal, "it holds this vault")
        XCTAssertNil(states["Code"]?.refusal)
        // "Every one" leaves them out; by name, they are refused.
        XCTAssertEqual(try vault.approveLinks().map(\.name), ["Code"])
        for (name, _) in refused { XCTAssertThrowsError(try vault.approveLinks([name]), name) }
        // Even with an approval on file (written by hand, or before D-104), they are not followed.
        try vault.approve(refused.map { Vault.realPath($0.1) })
        XCTAssertEqual(vault.linkedFolders().map(\.name), ["Code"])
        // Linking one by hand is refused too.
        XCTAssertThrowsError(try vault.linkFolder(top))
        XCTAssertThrowsError(try vault.linkFolder(URL(fileURLWithPath: "/")))
        // A store kept outside the vault is protected the same way.
        let elsewhere = top.appendingPathComponent("Stores/home")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let outside = try Vault(project: home, store: elsewhere, everything: true)
        outside.stateFolder = state
        try JSONEncoder().encode([LinkedFolder(name: "Index", path: elsewhere.path), LinkedFolder(name: "Stores", path: top.appendingPathComponent("Stores").path)])
            .write(to: elsewhere.appendingPathComponent("folders.json"))
        XCTAssertEqual(outside.linkStates().map(\.refusal), ["it is or holds Burrow's own store for this vault", "it is or holds Burrow's own store for this vault"])
    }

    /// Found in the real run: a planted entry Burrow refuses, naming the same folder as a real one, made approving that
    /// folder by its real path fail. Refused entries are left out of what a word approves instead.
    func testARefusedEntryNamingTheSameFolderDoesNotBlockApprovingIt() throws {
        let shortcut = top.appendingPathComponent("shortcut")
        try FileManager.default.createSymbolicLink(at: shortcut, withDestinationURL: code)
        try plant([(evilName, code.path), ("shortcut", shortcut.path)], in: home)
        let vault = try open(home)
        XCTAssertEqual(try vault.approveLinks([code.path]).map(\.name), ["shortcut"])
        XCTAssertEqual(vault.linkedFolders().map(\.name), ["shortcut"])
        XCTAssertEqual(vault.linksAwaitingApproval().map(\.name), [evilName], "the refused one stays out, approval or not")
        XCTAssertThrowsError(try vault.approveLinks([evilName]))
    }

    // MARK: 3. Only a person approves

    func testApprovingThroughAPipeIsRefusedAndApprovesNothing() throws {
        try plant([("Private", privateFolder.path)], in: home)
        for arguments in [["link", "approve", home.path, privateFolder.path], ["link", "approve", home.path, "--all"],
                          ["link", "approve", home.path, "Private"]] {
            let run = try BurrowBinary.piped(arguments, state: state, input: "yes\n")
            XCTAssertNotEqual(run.status, 0, run.out)
            XCTAssertTrue(run.err.contains("only you can approve a linked folder: approve it in the Burrow app, or run this in your own terminal"), run.err)
            XCTAssertFalse(run.out.contains("approved"), run.out)
        }
        // Linking approves, so it is refused through a pipe as well, and the vault's list is not touched.
        let link = try BurrowBinary.piped(["link", home.path, code.path], state: state, input: "yes\n")
        XCTAssertNotEqual(link.status, 0)
        XCTAssertTrue(link.err.contains("only you can approve a linked folder"), link.err)
        XCTAssertEqual(approvals(), "")
        XCTAssertEqual(try open(home).listedLinkedFolders().map(\.name), ["Private"])
        XCTAssertEqual(try open(home).linkedFolders(), [])
    }

    func testInATerminalThePersonSeesTheRealPathAndMustTypeYes() throws {
        let shortcut = top.appendingPathComponent("innocent")
        try FileManager.default.createSymbolicLink(at: shortcut, withDestinationURL: privateFolder)
        try plant([("innocent", shortcut.path)], in: home)
        // Anything but yes approves nothing.
        let no = try BurrowBinary.inTerminal(["link", "approve", home.path, "innocent"], state: state, answer: "y")
        XCTAssertNotEqual(no.status, 0, no.out)
        XCTAssertTrue(no.out.contains("nothing was approved"), no.out)
        XCTAssertEqual(try open(home).linkedFolders(), [])
        // The question shows where the folder really is, and what it was listed as.
        XCTAssertTrue(no.out.contains("innocent   \(Vault.realPath(privateFolder.path)) (listed as \(shortcut.path))"), no.out)
        XCTAssertTrue(no.out.contains("Approve only folders you linked yourself"), no.out)
        let yes = try BurrowBinary.inTerminal(["link", "approve", home.path, Vault.realPath(privateFolder.path)], state: state, answer: "yes")
        XCTAssertEqual(yes.status, 0, yes.out)
        XCTAssertTrue(yes.out.contains("approved innocent (\(Vault.realPath(privateFolder.path)))"), yes.out)
        XCTAssertEqual(try open(home).linkedFolders().map(\.path), [Vault.realPath(privateFolder.path)])
        // Linking a folder in a terminal asks too, showing the real path.
        let link = try BurrowBinary.inTerminal(["link", home.path, code.path], state: state, answer: "yes")
        XCTAssertEqual(link.status, 0, link.out)
        XCTAssertTrue(link.out.contains("Link this folder into \(home.path) and approve it on this Mac?\n  \(Vault.realPath(code.path))"), link.out)
        XCTAssertEqual(Set(try open(home).linkedFolders().map(\.name)), ["innocent", "Code"])
    }
}
