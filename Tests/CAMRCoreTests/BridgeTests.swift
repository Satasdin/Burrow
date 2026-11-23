@testable import CAMRCore
import Foundation
import XCTest

/// Vault bridges (D-97): one vault reads another, one way, read-only, never onwards.
final class BridgeTests: XCTestCase {
    private var top: URL!

    override func setUpWithError() throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("bridges-" + UUID().uuidString)
        try write("Home/Kitchen/Pilau.md", "# Pilau\n\nBrown the onions slowly, then the cumin and cardamom.\n")
        try write("Home/Money/Rent.md", "# Rent\n\nRent for the Kilimani flat is due on the fifth.\n")
        try write("Work/Projects/Launch.md", "# Matatu Pay launch\n\nMatatu Pay launches on 2 February 2027. Amina leads QA.\n")
        try write("Work/Team/Standup.md", "# Standup\n\nOtieno is on leave from 20 November.\n")
        try write("Team/Shared/Secret.md", "# Shared\n\nThe zanzibar offsite password list lives here.\n")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: top) }

    private func write(_ path: String, _ text: String) throws {
        let url = top.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func vault(_ name: String) async throws -> Vault {
        let opened = try Vault(project: top.appendingPathComponent(name), everything: true)
        opened.stateFolder = top.appendingPathComponent("state")
        try await opened.refresh()
        return opened
    }

    /// Every file under a folder with its bytes, CAMR's store included.
    private func snapshot(_ folder: String) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let base = top.appendingPathComponent(folder)
        for case let url as URL in FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)! where !url.hasDirectoryPath {
            // SQLite's shared-memory lock file is touched by every reader of a WAL index; it holds no content.
            guard !url.lastPathComponent.hasSuffix("-shm") else { continue }
            out[url.path] = try Data(contentsOf: url)
        }
        return out
    }

    func testFindsANoteOnlyInTheBridgedVaultLabelledWithItsName() async throws {
        let home = try await vault("Home")
        _ = try await vault("Work")
        let bridge = try home.addBridge(to: top.appendingPathComponent("Work"))
        XCTAssertEqual(bridge.name, "Work")
        XCTAssertFalse(bridge.withLedger, "notes only unless asked")
        let found = try await home.retrieve("When does Matatu Pay launch?", mode: .search)
        XCTAssertEqual(found.excerpts.first?.path, "Work › Projects/Launch.md")
        XCTAssertTrue(found.excerpts.first?.text.contains("2 February 2027") ?? false)
        XCTAssertEqual(home.text(of: "Work › Projects/Launch.md")?.contains("Amina leads QA"), true)
        // A question this vault answers still comes from here.
        let own = try await home.retrieve("pilau onions cumin", mode: .search)
        XCTAssertEqual(own.excerpts.first?.path, "Kitchen/Pilau.md")
    }

    func testNothingIsWrittenIntoTheBridgedVault() async throws {
        let home = try await vault("Home")
        _ = try await vault("Work")
        try home.addBridge(to: top.appendingPathComponent("Work"), withLedger: true)
        let before = try snapshot("Work")
        _ = try await home.retrieve("Matatu Pay launch", mode: .walk)
        _ = home.text(of: "Work › Projects/Launch.md")
        _ = home.bridgedShelves()
        _ = try home.searchLinesAcrossBridges("Otieno")
        XCTAssertFalse(home.canEdit("Work › Projects/Launch.md"))
        XCTAssertTrue(home.isLinked("Work › Projects/Launch.md"))
        XCTAssertThrowsError(try home.writeNote("Work › Projects/Launch.md", text: "changed"))
        XCTAssertThrowsError(try home.applyChange("Work › Projects/Launch.md", expecting: home.text(of: "Work › Projects/Launch.md")!, with: "changed"))
        XCTAssertThrowsError(try home.trash("Work › Projects/Launch.md"))
        XCTAssertThrowsError(try home.rename("Work › Projects", to: "Gone"))
        XCTAssertEqual(try snapshot("Work"), before, "the bridged vault's files, index and Ledger are byte for byte as they were")
        // Opened only to read, SQLite itself refuses a write.
        let other = try XCTUnwrap(home.bridgedVault(home.bridges()[0]))
        XCTAssertTrue(other.readOnly)
        XCTAssertThrowsError(try other.database.execute("DELETE FROM files"))
    }

    func testBridgesAreNotFollowedOnwards() async throws {
        let home = try await vault("Home")
        let work = try await vault("Work")
        _ = try await vault("Team")
        try work.addBridge(to: top.appendingPathComponent("Team"))
        try home.addBridge(to: top.appendingPathComponent("Work"))
        // Work reads Team...
        let fromWork = try await work.retrieve("zanzibar offsite password", mode: .search)
        XCTAssertTrue(fromWork.paths.contains("Team › Shared/Secret.md"))
        // ...but Home, which reads Work, never reaches Team.
        let fromHome = try await home.retrieve("zanzibar offsite password", mode: .search)
        XCTAssertFalse(fromHome.paths.contains { $0.contains("Secret") }, "\(fromHome.paths)")
        XCTAssertNil(home.text(of: "Work › Team › Shared/Secret.md"))
        XCTAssertNil(home.bridgedVault(home.bridges()[0])?.text(of: "Team › Shared/Secret.md"))
        // A cycle is harmless: Team bridging back to Home adds nothing to Home.
        let team = try await vault("Team")
        try team.addBridge(to: top.appendingPathComponent("Home"))
        let again = try await home.retrieve("zanzibar offsite password", mode: .search)
        XCTAssertFalse(again.paths.contains { $0.contains("Secret") })
    }

    func testScopeNamesOneBridgedVault() async throws {
        let home = try await vault("Home")
        _ = try await vault("Work")
        try home.addBridge(to: top.appendingPathComponent("Work"))
        let found = try await home.retrieve("launch rent onions leave", mode: .search, scope: "Work")
        XCTAssertFalse(found.excerpts.isEmpty)
        XCTAssertTrue(found.paths.allSatisfy { $0.hasPrefix("Work › ") }, "\(found.paths)")
        let inner = try await home.retrieve("leave", mode: .search, scope: "Work › Team")
        XCTAssertEqual(inner.paths, ["Work › Team/Standup.md"])
        let own = try await home.retrieve("launch rent onions leave", mode: .search, scope: "Money")
        XCTAssertEqual(own.paths, ["Money/Rent.md"])
    }

    func testUnbridgeTakesItAway() async throws {
        let home = try await vault("Home")
        _ = try await vault("Work")
        try home.addBridge(to: top.appendingPathComponent("Work"), name: "Office")
        var found = try await home.retrieve("Matatu Pay launch", mode: .search)
        XCTAssertEqual(found.excerpts.first?.path, "Office › Projects/Launch.md")
        let gone = try home.removeBridge("office")
        XCTAssertEqual(gone.name, "Office")
        found = try await home.retrieve("Matatu Pay launch", mode: .search)
        XCTAssertFalse(found.paths.contains { $0.contains("Launch") })
        XCTAssertNil(home.text(of: "Office › Projects/Launch.md"))
        XCTAssertNotNil(try? String(contentsOf: top.appendingPathComponent("Work/Projects/Launch.md"), encoding: .utf8), "the other vault is untouched")
    }

    func testRefusesWhatIsNotABridge() async throws {
        let home = try await vault("Home")
        XCTAssertThrowsError(try home.addBridge(to: top.appendingPathComponent("Home")))
        XCTAssertThrowsError(try home.addBridge(to: top.appendingPathComponent("Home/Kitchen")))
        XCTAssertThrowsError(try home.addBridge(to: top.appendingPathComponent("Work")), "Work has no index yet")
        _ = try await vault("Work")
        _ = try await vault("Team")
        try home.addBridge(to: top.appendingPathComponent("Work"), name: "Shared")
        XCTAssertThrowsError(try home.addBridge(to: top.appendingPathComponent("Team"), name: "Shared"), "names are unique")
        // Bridging the same vault again changes it in place.
        let changed = try home.addBridge(to: top.appendingPathComponent("Work"), withLedger: true)
        XCTAssertEqual(home.bridges().count, 1)
        XCTAssertEqual(changed.name, "Shared")
        XCTAssertTrue(changed.withLedger)
        // A vault's own name is the default, and the separator can't be smuggled into one.
        var settings = CAMRConfig.forVault(store: top.appendingPathComponent("Team/.camr"))
        try settings.set("vault.name", "Team › Stuff/x")
        XCTAssertEqual(try home.addBridge(to: top.appendingPathComponent("Team")).name, "Team Stuffx")
    }

    func testAMovedVaultLeavesTheRestStanding() async throws {
        let home = try await vault("Home")
        _ = try await vault("Work")
        try home.addBridge(to: top.appendingPathComponent("Work"))
        try FileManager.default.moveItem(at: top.appendingPathComponent("Work"), to: top.appendingPathComponent("Moved"))
        let reopened = try Vault(project: top.appendingPathComponent("Home"), everything: true)
        reopened.stateFolder = top.appendingPathComponent("state")
        let found = try await reopened.retrieve("pilau onions", mode: .search)
        XCTAssertEqual(found.excerpts.first?.path, "Kitchen/Pilau.md")
        XCTAssertNotNil(reopened.bridgedShelves().first?.problem)
    }

    // MARK: Only the person on this Mac makes a bridge (D-100)

    /// What a shared, downloaded or cloned vault could carry: a bridges file inside its folder, pointing at another vault.
    private func plantBridgesFile(in vault: String, to other: String) throws {
        let planted = [Bridge(name: other, path: top.appendingPathComponent(other).path, withLedger: true)]
        try JSONEncoder().encode(planted).write(to: top.appendingPathComponent("\(vault)/.camr/bridges.json"))
    }

    func testABridgesFileInsideTheVaultGivesNoAccess() async throws {
        let home = try await vault("Home")
        _ = try await vault("Work")
        try plantBridgesFile(in: "Home", to: "Work")
        XCTAssertTrue(home.bridges().isEmpty)
        XCTAssertTrue(home.bridgedShelves().isEmpty)
        for mode in [Mode.search, .walk] {
            let found = try await home.retrieve("When does Matatu Pay launch? Who leads QA?", mode: mode)
            XCTAssertFalse(found.paths.contains { $0.contains("Launch") || $0.contains("Standup") }, "\(mode): \(found.paths)")
        }
        let scoped = try await home.retrieve("Matatu Pay launch", mode: .search, scope: "Work")
        XCTAssertFalse(scoped.paths.contains { $0.contains("Launch") }, "\(scoped.paths)")
        XCTAssertNil(home.text(of: "Work › Projects/Launch.md"))
        XCTAssertNil(home.bridgedFileURL("Work › Projects/Launch.md"))
        XCTAssertNil(home.bridged("Work › Projects/Launch.md"))
        XCTAssertTrue(try home.searchLinesAcrossBridges("Matatu").isEmpty)
        XCTAssertTrue(try home.searchLinesAcrossBridges("Matatu", scope: "Work").isEmpty)
        // Pointed out once, and nothing is imported from it.
        let notice = try XCTUnwrap(home.takeBridgesInVaultNotice())
        XCTAssertTrue(notice.contains("Found bridges written inside this vault folder"), notice)
        XCTAssertTrue(notice.contains("ignored"), notice)
        XCTAssertNil(home.takeBridgesInVaultNotice(), "said once")
        XCTAssertTrue(home.bridges().isEmpty)
        // A bridge the person makes works beside it; unbridging takes it away again.
        try home.addBridge(to: top.appendingPathComponent("Work"))
        let bridged = try await home.retrieve("When does Matatu Pay launch?", mode: .search)
        XCTAssertEqual(bridged.excerpts.first?.path, "Work › Projects/Launch.md")
        XCTAssertFalse(home.bridges()[0].withLedger, "the planted file's --with-ledger did not leak into the real bridge")
        try home.removeBridge("Work")
        let gone = try await home.retrieve("When does Matatu Pay launch?", mode: .search)
        XCTAssertFalse(gone.paths.contains { $0.contains("Launch") })
        XCTAssertNil(home.text(of: "Work › Projects/Launch.md"))
    }

    func testBridgesAreKeptInCAMRsOwnFolderNeverInTheVault() async throws {
        let home = try await vault("Home")
        _ = try await vault("Work")
        try home.addBridge(to: top.appendingPathComponent("Work"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: top.appendingPathComponent("Home/.camr/bridges.json").path))
        let kept = try XCTUnwrap(try BridgeStore.load(in: top.appendingPathComponent("state")).vaults[home.bridgeKey])
        XCTAssertEqual(kept.map(\.name), ["Work"])
        // The same vault opened afresh, and through a symlink, has it.
        let again = try Vault(project: top.appendingPathComponent("Home"), everything: true)
        again.stateFolder = top.appendingPathComponent("state")
        XCTAssertEqual(again.bridges().map(\.name), ["Work"])
        try FileManager.default.createSymbolicLink(at: top.appendingPathComponent("Home link"), withDestinationURL: top.appendingPathComponent("Home"))
        let linked = try Vault(project: top.appendingPathComponent("Home link"), everything: true)
        linked.stateFolder = top.appendingPathComponent("state")
        XCTAssertEqual(linked.bridges().map(\.name), ["Work"])
        // Another state folder (another person's, or a test's) knows nothing of it.
        let elsewhere = try Vault(project: top.appendingPathComponent("Home"), everything: true)
        elsewhere.stateFolder = top.appendingPathComponent("other-state")
        XCTAssertTrue(elsewhere.bridges().isEmpty)
        // Removing the last bridge leaves no entry behind.
        try home.removeBridge("Work")
        XCTAssertNil(try BridgeStore.load(in: top.appendingPathComponent("state")).vaults[home.bridgeKey])
    }

    func testTwoVaultsWithTheSameFolderNameDoNotShareBridges() async throws {
        try write("Elsewhere/Home/Garden.md", "# Garden\n\nPlant the sukuma wiki before the long rains.\n")
        let home = try await vault("Home")
        let twin = try await vault("Elsewhere/Home")
        _ = try await vault("Work")
        try home.addBridge(to: top.appendingPathComponent("Work"))
        XCTAssertEqual(home.bridges().map(\.name), ["Work"])
        XCTAssertTrue(twin.bridges().isEmpty)
        let found = try await twin.retrieve("When does Matatu Pay launch?", mode: .search)
        XCTAssertFalse(found.paths.contains { $0.contains("Launch") }, "\(found.paths)")
        XCTAssertNil(twin.text(of: "Work › Projects/Launch.md"))
        // And the twin's own bridge is its own.
        _ = try await vault("Team")
        try twin.addBridge(to: top.appendingPathComponent("Team"))
        XCTAssertEqual(home.bridges().map(\.name), ["Work"])
        XCTAssertEqual(twin.bridges().map(\.name), ["Team"])
    }

    /// A bridged vault's list of linked folders is a file in its folder, which anyone who can write there could point at
    /// the person's own folders. Through a bridge, no file outside the other vault's folder is opened (D-100).
    func testABridgedVaultsLinkedFoldersAreNotOpenedThroughTheBridge() async throws {
        try write("Code/fares.py", "def matatu_fare(stage):\n    return 70 * stage\n")
        try write("Private/Diary.md", "# Diary\n\nThe kitty password is jacaranda-42.\n")
        let home = try await vault("Home")
        let work = try await vault("Work")
        try work.linkFolder(top.appendingPathComponent("Code"))
        try await work.refresh()
        try home.addBridge(to: top.appendingPathComponent("Work"))
        // What Work's owner indexed from its linked code is still found, from Work's own index...
        let found = try await home.retrieve("matatu_fare stage", mode: .search)
        XCTAssertTrue(found.paths.contains("Work › Code/fares.py"), "\(found.paths)")
        // ...but nothing outside Work's folder is opened from disk through the bridge.
        XCTAssertNil(home.text(of: "Work › Code/fares.py"))
        // A list rewritten by someone else with write access to Work, pointing at a private folder, reaches nothing.
        let planted = [LinkedFolder(name: "Private", path: top.appendingPathComponent("Private").path)]
        try JSONEncoder().encode(planted).write(to: top.appendingPathComponent("Work/.camr/folders.json"))
        XCTAssertNil(home.text(of: "Work › Private/Diary.md"))
        XCTAssertNotEqual(home.bridgedFileURL("Work › Private/Diary.md")?.standardizedFileURL.path,
                          top.appendingPathComponent("Private/Diary.md").standardizedFileURL.path, "only ever a place inside Work")
        XCTAssertTrue(home.bridgedShelves().allSatisfy { $0.linked.isEmpty })
    }

    func testAnUnreadableListOfBridgesIsNeverWrittenOver() async throws {
        let home = try await vault("Home")
        _ = try await vault("Work")
        let file = top.appendingPathComponent("state/bridges.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: file)
        XCTAssertTrue(home.bridges().isEmpty)
        XCTAssertThrowsError(try home.addBridge(to: top.appendingPathComponent("Work")))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{ not json")
    }

    func testMergeLeavesOutAVaultFarFromTheQuestion() {
        func found(_ path: String, _ nearest: Float?) -> Retrieved {
            Retrieved(mode: .search, excerpts: [Excerpt(path: path, startLine: 1, endLine: 2, text: "text", reason: .search, isNote: true)],
                      seconds: 0, signal: Signal(nearest: nearest, wordMatches: 1))
        }
        let close = Vault.merged([found("a.md", 0.40), found("Work › b.md", 0.71)], budget: Budget(), mode: .search, seconds: 0)
        XCTAssertEqual(close.paths, ["Work › b.md"], "a vault 0.31 behind the best is left out")
        let both = Vault.merged([found("a.md", 0.66), found("Work › b.md", 0.71)], budget: Budget(), mode: .search, seconds: 0)
        XCTAssertEqual(both.paths, ["Work › b.md", "a.md"], "the closer vault comes first")
        XCTAssertEqual(both.signal.nearest, 0.71)
        let words = Vault.merged([found("a.md", nil), found("Work › b.md", nil)], budget: Budget(), mode: .search, seconds: 0)
        XCTAssertEqual(words.paths, ["a.md", "Work › b.md"], "without meaning, this vault first, then each in turn")
    }
}
