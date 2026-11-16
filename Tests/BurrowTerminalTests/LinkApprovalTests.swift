@testable import BurrowCore
@testable import BurrowTools
import Foundation
import XCTest

/// A vault's list of linked folders is a file in its folder, so a vault from someone else can carry one pointing anywhere
/// on this Mac. Burrow follows a linked folder only once the person on this Mac approved it for that vault (D-101).
final class LinkApprovalTests: XCTestCase {
    private var top: URL!
    /// Burrow's own folder for these tests: where approvals are kept.
    private var state: URL { top.appendingPathComponent("state") }
    private var home: URL { top.appendingPathComponent("Home") }
    private var privateFolder: URL { top.appendingPathComponent("Private") }
    private let secret = "jacaranda-42"

    override func setUp() async throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("link-approval-" + UUID().uuidString)
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

    /// What a shared, downloaded or synced vault could carry: a list of linked folders naming a private folder here.
    private func plant(_ folders: [(String, URL)], in vault: URL) throws {
        let store = vault.appendingPathComponent(".burrow")
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try JSONEncoder().encode(folders.map { LinkedFolder(name: $0.0, path: $0.1.path) }).write(to: store.appendingPathComponent("folders.json"))
    }

    private func listed(_ vault: URL) throws -> Data { try Data(contentsOf: vault.appendingPathComponent(".burrow/folders.json")) }

    // MARK: A planted list reaches nothing

    func testAPlantedListOfLinkedFoldersGivesNoAccess() async throws {
        try plant([("Private", privateFolder)], in: home)
        let before = try listed(home)
        let vault = try open(home)
        // Indexing, and the index.
        try await vault.refresh(embedder: FakeEmbedder())
        XCTAssertFalse(try vault.projectMap().files.contains { $0.path.hasPrefix("Private/") })
        XCTAssertEqual(vault.linkedFolders(), [])
        XCTAssertEqual(vault.linksAwaitingApproval().map(\.name), ["Private"])
        // Find and read, in the library.
        let found = try await vault.retrieve("kitty password diary", mode: .walk, embedder: FakeEmbedder())
        XCTAssertFalse(found.excerpts.contains { $0.text.contains(secret) }, "\(found.paths)")
        XCTAssertNil(vault.text(of: "Private/Diary.md"))
        XCTAssertNil(vault.readLines("Private/Diary.md"))
        XCTAssertFalse(try vault.searchLines("kitty").contains { $0.text.contains(secret) })
        // The tools a connected program and Burrow's own chat use.
        let answerer = FakeAnswerer()
        let tools = VaultTools(vault: vault, embedder: FakeEmbedder()) { _ in answerer }
        let mcpFound = try await tools.call("burrow_find", arguments: ["query": "What is the kitty password in the diary?"])
        XCTAssertFalse(mcpFound.text.contains(secret), mcpFound.text)
        for asked in ["Private/Diary.md", "Private/Diary", "Diary.md"] {
            let read = try await tools.call("burrow_read", arguments: ["path": asked])
            XCTAssertFalse(read.text.contains(secret), "\(asked): \(read.text)")
        }
        let scoped = try await tools.call("burrow_find", arguments: ["query": "diary", "folder": "Private"])
        XCTAssertFalse(scoped.text.contains(secret), scoped.text)
        let folders = try await tools.call("vault_folders", arguments: [:])
        XCTAssertFalse(folders.text.contains("Private"), folders.text)
        _ = try await tools.call("vault_ask", arguments: ["question": "What is the kitty password in the diary?"])
        XCTAssertFalse(answerer.prompts.contains { $0.user.contains(secret) || $0.system.contains(secret) })
        // The note a connected program gets says how many, never which or where.
        let note = tools.linksAwaitingApprovalNote()
        XCTAssertTrue(note.contains("One linked folder in this vault is waiting for the person's approval"), note)
        XCTAssertFalse(note.contains("Private") || note.contains(top.path), note)
        // Nothing was taken off the vault's list.
        XCTAssertEqual(try listed(home), before)
    }

    func testCheckAndTheGateDoNotLookInAnUnapprovedFolder() async throws {
        for arguments in [["init", "-q"], ["add", "-A"], ["-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qm", "start"]] {
            _ = VaultTools.git(privateFolder, arguments)
        }
        try "# Diary\n\nChanged: the new password is \(secret)-b.\n".write(to: privateFolder.appendingPathComponent("Diary.md"), atomically: true, encoding: .utf8)
        try plant([("Private", privateFolder)], in: home)
        let vault = try open(home)
        try await vault.refresh()
        XCTAssertNil(Hooks.place(for: privateFolder, vaultRoot: vault.root, linked: vault.linkedFolders()))
        let tools = VaultTools(vault: vault, embedder: nil) { _ in FakeAnswerer() }
        let checked = try await tools.call("burrow_check", arguments: [:])
        XCTAssertFalse(checked.text.contains("Diary") || checked.text.contains(secret), checked.text)
        XCTAssertTrue(VaultTools.checkReport(vault: vault, ledger: Ledger(vault: vault)).changed.isEmpty)
        // Once the person approves it, the check sees the change: the folder was skipped, not broken.
        try vault.approveLinks()
        XCTAssertNotNil(Hooks.place(for: privateFolder, vaultRoot: vault.root, linked: vault.linkedFolders()))
        XCTAssertEqual(VaultTools.checkReport(vault: vault, ledger: Ledger(vault: vault)).changed, ["Private/Diary.md"])
    }

    /// An index built before approvals existed (the person's own vaults, or one indexed while a planted list was followed)
    /// still holds the folder's files. They are taken out before anything is found, and come back after one yes.
    func testAnIndexBuiltBeforeApprovalForgetsTheFolderUntilApproved() async throws {
        let vault = try open(home)
        try vault.linkFolder(privateFolder)
        try await vault.refresh()
        XCTAssertTrue(try vault.searchLines("kitty").contains { $0.path == "Private/Diary.md" })
        // As it was before D-101: the list is there, Burrow's own folder has no approval for it.
        try FileManager.default.removeItem(at: LinkApprovalStore.file(in: state))
        // `burrow find` does not re-index: what it opens with is taken out first.
        let cli = try burrow(["find", home.path, "kitty password diary", "--vault", "--mode", "search"])
        XCTAssertFalse(cli.out.contains("Private/Diary.md"), cli.out)
        XCTAssertTrue(cli.err.contains("skipped"), cli.err)
        XCTAssertTrue(FileManager.default.fileExists(atPath: privateFolder.appendingPathComponent("Diary.md").path), "nothing on disk is touched")
        XCTAssertEqual(try open(home).linksAwaitingApproval().map(\.name), ["Private"], "and the vault's list is unchanged")
        // In this process, through the same step, without a re-index.
        try vault.linkFolder(privateFolder)
        try await vault.refresh()
        try FileManager.default.removeItem(at: LinkApprovalStore.file(in: state))
        let reopened = try open(home)
        XCTAssertTrue(try reopened.searchLines("kitty").contains { $0.path == "Private/Diary.md" }, "still in the index until taken out")
        XCTAssertEqual(try reopened.dropUnapprovedFromIndex(), 1)
        XCTAssertFalse(try reopened.searchLines("kitty").contains { $0.path == "Private/Diary.md" })
        XCTAssertEqual(try reopened.dropUnapprovedFromIndex(), 0)
        // And connected programs, whose index is kept fresh, never see it either.
        try reopened.approveLinks()
        try await reopened.refresh()
        try FileManager.default.removeItem(at: LinkApprovalStore.file(in: state))
        let tools = VaultTools(vault: reopened, embedder: nil) { _ in FakeAnswerer() }
        let found = try await tools.call("burrow_find", arguments: ["query": "kitty password diary"])
        XCTAssertFalse(found.text.contains(secret), found.text)
        XCTAssertFalse(try reopened.searchLines("kitty").contains { $0.path == "Private/Diary.md" })
        XCTAssertFalse(try reopened.projectMap().files.contains { $0.path.hasPrefix("Private/") })
        // One yes, and the next index brings it back.
        XCTAssertEqual(try reopened.approveLinks(["private"]).map(\.name), ["Private"])
        try await reopened.refresh()
        XCTAssertTrue(try reopened.searchLines("kitty").contains { $0.path == "Private/Diary.md" })
        XCTAssertEqual(reopened.text(of: "Private/Diary.md")?.contains(secret), true)
    }

    /// A folder of the vault's own with the name of an unapproved link is the vault's, and stays in the index.
    func testAVaultFolderNamedLikeAnUnapprovedLinkStays() async throws {
        try "# Plans\n\nPaint the gate blue.\n".write(to: home.appendingPathComponent("Plans.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        try "# Launch\n\nThe launch is in February.\n".write(to: home.appendingPathComponent("Projects/Launch.md"), atomically: true, encoding: .utf8)
        let vault = try open(home)
        try await vault.refresh()
        try plant([("Projects", privateFolder)], in: home)
        XCTAssertEqual(try vault.dropUnapprovedFromIndex(), 0)
        try await vault.refresh()
        XCTAssertTrue(try vault.projectMap().files.contains { $0.path == "Projects/Launch.md" })
        XCTAssertFalse(try vault.projectMap().files.contains { $0.path == "Projects/Diary.md" })
        XCTAssertEqual(vault.text(of: "Projects/Launch.md")?.contains("February"), true)
        XCTAssertNil(vault.text(of: "Projects/Diary.md"))
    }

    // MARK: The person approves

    func testLinkingAFolderApprovesItAndKeepsTheApprovalOutOfTheVault() async throws {
        let vault = try open(home)
        let code = try vault.linkFolder(top.appendingPathComponent("Code"))
        XCTAssertEqual(vault.linkStates().map(\.approved), [true])
        // A reader gets the real path the approval was checked against (D-104).
        XCTAssertEqual(vault.linkedFolders(), [LinkedFolder(name: code.name, path: Vault.realPath(code.path))])
        try await vault.refresh()
        XCTAssertTrue(try vault.projectMap().files.contains { $0.path == "Code/fares.py" })
        let saved = try String(contentsOf: LinkApprovalStore.file(in: state), encoding: .utf8)
        XCTAssertTrue(saved.contains(Vault.realPath(top.appendingPathComponent("Code").path)), saved)
        let insideVault = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(".burrow").path)
        XCTAssertFalse(insideVault.contains("linked-folders.json"))
        // Linking a folder the list already names, which was waiting, approves it.
        try plant([("Code", top.appendingPathComponent("Code")), ("Private", privateFolder)], in: home)
        XCTAssertEqual(vault.linksAwaitingApproval().map(\.name), ["Private"])
        try vault.linkFolder(privateFolder)
        XCTAssertTrue(vault.linksAwaitingApproval().isEmpty)
        // Unlinking forgets the approval, so the same entry planted again asks again.
        try vault.unlinkFolder("Private")
        try plant([("Code", top.appendingPathComponent("Code")), ("Private", privateFolder)], in: home)
        XCTAssertEqual(vault.linksAwaitingApproval().map(\.name), ["Private"])
    }

    func testApproveByNameOrAllAndListTheState() throws {
        try plant([("Code", top.appendingPathComponent("Code")), ("Private", privateFolder)], in: home)
        let vault = try open(home)
        XCTAssertEqual(vault.linkStates().map(\.approved), [false, false])
        XCTAssertThrowsError(try vault.approveLinks(["Nope"]))
        XCTAssertEqual(vault.linkStates().map(\.approved), [false, false], "a name not on the list approves nothing")
        try vault.approveLinks(["code"])
        XCTAssertEqual(vault.linkStates().map(\.approved), [true, false])
        XCTAssertEqual(vault.linkedFolders().map(\.name), ["Code"])
        try vault.approveLinks([privateFolder.path])
        XCTAssertEqual(vault.linkStates().map(\.approved), [true, true])
        try FileManager.default.removeItem(at: LinkApprovalStore.file(in: state))
        try vault.approveLinks()
        XCTAssertEqual(vault.linkStates().map(\.approved), [true, true])
    }

    func testAnUnreadableListOfApprovalsApprovesNothingAndIsNeverWrittenOver() throws {
        try plant([("Code", top.appendingPathComponent("Code"))], in: home)
        let vault = try open(home)
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: LinkApprovalStore.file(in: state))
        XCTAssertEqual(vault.linkedFolders(), [])
        XCTAssertThrowsError(try vault.approveLinks())
        XCTAssertThrowsError(try vault.linkFolder(privateFolder))
        XCTAssertEqual(try String(contentsOf: LinkApprovalStore.file(in: state), encoding: .utf8), "{ not json")
    }

    // MARK: Paths: symlinks, moves, and two vaults with one name

    func testSymlinkedAndMovedPathsResolve() throws {
        let vault = try open(home)
        // A folder linked through a symlink is approved as the folder it leads to.
        let shortcut = top.appendingPathComponent("code-shortcut")
        try FileManager.default.createSymbolicLink(at: shortcut, withDestinationURL: top.appendingPathComponent("Code"))
        try vault.linkFolder(shortcut)
        XCTAssertEqual(vault.linkedFolders().map(\.name), ["code-shortcut"])
        // The vault opened through a symlink to it is the same vault, with the same approval.
        let homeLink = top.appendingPathComponent("home-link")
        try FileManager.default.createSymbolicLink(at: homeLink, withDestinationURL: home)
        XCTAssertEqual(try open(homeLink).linkedFolders().map(\.name), ["code-shortcut"])
        // Pointed somewhere else, the same entry is a different folder, and waits.
        try FileManager.default.removeItem(at: shortcut)
        try FileManager.default.createSymbolicLink(at: shortcut, withDestinationURL: privateFolder)
        XCTAssertEqual(vault.linkedFolders(), [])
        XCTAssertEqual(vault.linksAwaitingApproval().map(\.name), ["code-shortcut"])
        XCTAssertNil(vault.text(of: "code-shortcut/Diary.md"))
        // Pointed back, it is approved again.
        try FileManager.default.removeItem(at: shortcut)
        try FileManager.default.createSymbolicLink(at: shortcut, withDestinationURL: top.appendingPathComponent("Code"))
        XCTAssertEqual(vault.linkedFolders().map(\.name), ["code-shortcut"])
        // A vault moved to another place is asked again: the approval was for the vault where it was.
        let moved = top.appendingPathComponent("Moved/Home")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: home, to: moved)
        XCTAssertEqual(try open(moved).linksAwaitingApproval().map(\.name), ["code-shortcut"])
    }

    func testApprovalForOneVaultDoesNotApplyToAnotherWithTheSameName() throws {
        let other = top.appendingPathComponent("Downloads/Home")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let mine = try open(home)
        try mine.linkFolder(privateFolder)
        // A vault with the same folder name somewhere else, listing the same folder under the same name.
        try plant([("Private", privateFolder)], in: other)
        let theirs = try open(other)
        XCTAssertEqual(mine.linkedFolders().map(\.name), ["Private"])
        XCTAssertEqual(theirs.linkedFolders(), [])
        XCTAssertNil(theirs.text(of: "Private/Diary.md"))
    }

    // MARK: Through a bridge

    func testABridgedVaultsUnapprovedLinkIsLeftOutOfWhatTheBridgeShows() async throws {
        let workFolder = top.appendingPathComponent("Work")
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        try "# Launch\n\nMatatu Pay launches in February.\n".write(to: workFolder.appendingPathComponent("Launch.md"), atomically: true, encoding: .utf8)
        let work = try open(workFolder)
        try work.linkFolder(privateFolder)
        try await work.refresh()
        let homeVault = try open(home)
        try await homeVault.refresh()
        try homeVault.addBridge(to: workFolder)
        XCTAssertTrue(try homeVault.searchLinesAcrossBridges("kitty").contains { $0.path == "Work › Private/Diary.md" })
        // Work's index still holds the folder, but its approval is gone (an index from before D-101).
        try FileManager.default.removeItem(at: LinkApprovalStore.file(in: state))
        XCTAssertFalse(try homeVault.searchLinesAcrossBridges("kitty").contains { $0.text.contains(secret) })
        let found = try await homeVault.retrieve("kitty password diary", mode: .search)
        XCTAssertFalse(found.excerpts.contains { $0.text.contains(secret) }, "\(found.paths)")
        XCTAssertFalse(homeVault.bridgedShelves().flatMap(\.files).contains { $0.path.contains("Diary") })
        XCTAssertTrue(homeVault.bridgedShelves().flatMap(\.files).contains { $0.path == "Work › Launch.md" })
    }

    // MARK: The real binary

    @discardableResult
    private func burrow(_ arguments: [String], input: String? = nil) throws -> (status: Int32, out: String, err: String) {
        let binary = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("burrow")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: binary.path), "build burrow first: \(binary.path)")
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["BURROW_STATE_DIR"] = state.path
        process.environment = environment
        let feed = Pipe(), out = Pipe(), err = Pipe()
        process.standardInput = feed
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: watchdog)
        if let input { feed.fileHandleForWriting.write(Data(input.utf8)) }
        try feed.fileHandleForWriting.close()
        let o = out.fileHandleForReading.readDataToEndOfFile(), e = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self))
    }

    /// `burrow mcp` on Home: what burrow_find and burrow_read hand a connected program, and its instructions.
    private func overMCP() throws -> (find: String, read: String, instructions: String) {
        let lines = [
            DualEraMCPTests.modern(1, "tools/call", #""name":"burrow_find","arguments":{"query":"What is the kitty password in the diary?"}"#),
            DualEraMCPTests.modern(2, "tools/call", #""name":"burrow_read","arguments":{"path":"Private/Diary.md"}"#),
            DualEraMCPTests.modern(3, "server/discover"),
        ]
        let replies = try burrow(["mcp", home.path], input: lines.joined(separator: "\n") + "\n").out
        var texts: [Int: String] = [:]
        for line in replies.split(separator: "\n") {
            guard let reply = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let id = reply["id"] as? Int else { continue }
            let result = reply["result"] as? [String: Any]
            texts[id] = (result?["instructions"] as? String) ?? ((result?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? "\(reply)"
        }
        return (try XCTUnwrap(texts[1], replies), try XCTUnwrap(texts[2], replies), try XCTUnwrap(texts[3], replies))
    }

    func testTheCommandLineAndMCPServerSkipUntilApproved() throws {
        try plant([("Private", privateFolder)], in: home)
        XCTAssertEqual(try burrow(["index", home.path, "--vault", "--no-embed"]).status, 0)
        // find: nothing from the folder, and one plain line saying what was skipped. Through a pipe, where a connected
        // program may be reading, it gives a count and where to approve, never the name or path (D-104).
        let find = try burrow(["find", home.path, "kitty password diary", "--vault"])
        XCTAssertFalse(find.out.contains("Private/Diary.md"), find.out)
        XCTAssertTrue(find.err.contains("1 linked folder was skipped because it isn't approved on this Mac. Only you can approve it"), find.err)
        XCTAssertFalse(find.err.contains("Private") || find.err.contains(privateFolder.path) || find.err.contains("--all"), find.err)
        XCTAssertEqual(find.err.split(separator: "\n").count, 1, find.err)
        // MCP: nothing from it, and the first result and the instructions say how many are waiting, not which.
        var mcp = try overMCP()
        XCTAssertFalse(mcp.find.contains(secret), mcp.find)
        XCTAssertFalse(mcp.read.contains(secret), mcp.read)
        XCTAssertTrue(mcp.find.hasPrefix("One linked folder in this vault is waiting for the person's approval"), mcp.find)
        XCTAssertFalse(mcp.read.contains("waiting for the person's approval"), "said once: \(mcp.read)")
        XCTAssertTrue(mcp.instructions.contains("waiting for the person's approval"), mcp.instructions)
        for text in [mcp.find, mcp.read, mcp.instructions] { XCTAssertFalse(text.contains(privateFolder.path), text) }
        // link list shows it waiting; approve takes it in and indexes it.
        let list = try burrow(["link", "list", home.path])
        XCTAssertTrue(list.out.contains("Private   \(privateFolder.path)   not approved on this Mac"), list.out)
        XCTAssertNotEqual(try burrow(["link", "approve", home.path]).status, 0, "approve says which")
        // Approving needs the person in a terminal, typing yes (D-104).
        XCTAssertNotEqual(try burrow(["link", "approve", home.path, "--all"]).status, 0)
        let approve = try BurrowBinary.inTerminal(["link", "approve", home.path, "--all"], state: state, answer: "yes")
        XCTAssertEqual(approve.status, 0, approve.out)
        XCTAssertTrue(approve.out.contains("approved Private (\(Vault.realPath(privateFolder.path)))"), approve.out)
        XCTAssertTrue(try burrow(["link", "list", home.path]).out.contains("Private   \(privateFolder.path)   approved"))
        let after = try burrow(["find", home.path, "kitty password diary", "--vault"])
        XCTAssertTrue(after.out.contains("Private/Diary.md"), after.out)
        XCTAssertTrue(after.err.isEmpty, after.err)
        mcp = try overMCP()
        XCTAssertTrue(mcp.read.contains(secret), mcp.read)
        XCTAssertFalse(mcp.find.contains("waiting for the person's approval"), mcp.find)
    }

    func testAVaultLinkedWithTheCommandLineNeedsNoOtherStep() throws {
        // The folder is made a vault first: `link` no longer makes one of whatever folder it is given (D-114).
        XCTAssertEqual(try burrow(["vault", "new", home.path, "--no-embed"]).status, 0)
        // Linking approves, so it is asked in the person's terminal too (D-104).
        let link = try BurrowBinary.inTerminal(["link", home.path, top.appendingPathComponent("Code").path], state: state, answer: "yes")
        XCTAssertEqual(link.status, 0, link.out)
        XCTAssertTrue(link.out.contains("approved on this Mac"), link.out)
        XCTAssertEqual(try burrow(["index", home.path, "--vault", "--no-embed"]).status, 0)
        let find = try burrow(["find", home.path, "matatu_fare", "--vault"])
        XCTAssertTrue(find.out.contains("Code/fares.py"), find.out)
        XCTAssertTrue(find.err.isEmpty, find.err)
        XCTAssertTrue(try burrow(["link", "list", home.path]).out.contains("approved"))
    }
}
