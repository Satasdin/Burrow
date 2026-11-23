@testable import CAMRCore
import Foundation
import XCTest

/// D-114: which folders are vaults, which vault the app opens first, and finding indexes no one chose.
final class VaultPlacesTests: XCTestCase {
    private var top: URL!

    override func setUp() async throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("places-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: top, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: top) }

    private func folder(_ path: String) throws -> URL {
        let url = top.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testOnlyAFolderWithAnIndexIsAVault() throws {
        let plain = try folder("Downloads")
        XCTAssertFalse(Vault.hasIndex(plain))
        _ = try Vault(project: try folder("Notes"), everything: true)
        XCTAssertTrue(Vault.hasIndex(top.appendingPathComponent("Notes")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.appendingPathComponent(".camr").path), "asking makes nothing")
        // A store kept elsewhere counts where it is.
        let elsewhere = top.appendingPathComponent("store")
        _ = try Vault(project: try folder("Code"), store: elsewhere)
        XCTAssertTrue(Vault.hasIndex(top.appendingPathComponent("Code"), store: elsewhere))
        XCTAssertFalse(Vault.hasIndex(top.appendingPathComponent("Code")))
        XCTAssertTrue(Vault.notAVault("/x/Downloads").contains("camr vault new /x/Downloads"))
    }

    func testTheAppOpensTheTerminalsVaultOnItsFirstLaunch() {
        let all: Set<String> = ["/v/CAMRTest", "/v/Notes", "/v/Old"]
        let exists = { all.contains($0) }
        // The tester's case: nothing opened in the app yet, ~/CAMRTest made with `camr vault new`.
        XCTAssertEqual(StartingVault.choose(recents: [], last: "/v/CAMRTest", known: ["/v/CAMRTest", "/v/Notes"], exists: exists), .open("/v/CAMRTest"))
        // No last vault written (made by an older CAMR), one known vault: that one.
        XCTAssertEqual(StartingVault.choose(recents: [], last: nil, known: ["/v/Notes"], exists: exists), .open("/v/Notes"))
        // Several and no last: listed, never asked to choose a folder from scratch.
        XCTAssertEqual(StartingVault.choose(recents: [], last: nil, known: ["/v/Notes", "/v/Old"], exists: exists), .pick(["/v/Notes", "/v/Old"]))
        // A last vault since removed is passed over.
        XCTAssertEqual(StartingVault.choose(recents: [], last: "/v/Gone", known: ["/v/Notes"], exists: exists), .open("/v/Notes"))
        // Someone who has used the app gets the welcome list as before, with the terminal's vaults after their recents.
        XCTAssertEqual(StartingVault.choose(recents: ["/v/Old"], last: "/v/CAMRTest", known: ["/v/CAMRTest", "/v/Old", "/v/Gone"], exists: exists),
                       .pick(["/v/Old", "/v/CAMRTest"]))
        XCTAssertEqual(StartingVault.choose(recents: [], last: nil, known: [], exists: exists), .pick([]))
    }

    /// The first-launch check found "All 2 vaults" for one: the terminal kept /tmp/…, the app /private/tmp/….
    func testOneVaultSpelledTwoWaysIsKnownOnce() throws {
        let state = try folder("state")
        let real = try folder("real/Notes")
        let link = top.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: top.appendingPathComponent("real"))
        for root in [real, link.appendingPathComponent("Notes")] {
            let vault = try Vault(project: root, everything: true)
            vault.stateFolder = state
            KnownVaults.remember(vault)
        }
        XCTAssertEqual(KnownVaults.list(in: state).count, 1)
        let other = try Vault(project: link.appendingPathComponent("Notes"), everything: true)
        other.stateFolder = state
        XCTAssertEqual(try other.storageReport().vaultCount, 1, "the storage line counts it once")
        // A list an older CAMR wrote with both spellings is read as one.
        let both = #"[{"root":"\#(real.path)","store":"\#(real.path)/.camr"},{"root":"\#(link.path)/Notes","store":"\#(link.path)/Notes/.camr"}]"#
        try both.write(to: state.appendingPathComponent("vaults.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(KnownVaults.list(in: state).count, 1)
    }

    func testTheLastVaultIsKeptInCAMRsOwnFolder() throws {
        let state = try folder("state"), notes = try folder("Notes")
        XCTAssertNil(LastVault.read(in: state))
        LastVault.write(notes.path, in: state)
        XCTAssertEqual(LastVault.read(in: state), notes.path)
        try FileManager.default.removeItem(at: notes)
        XCTAssertNil(LastVault.read(in: state), "a folder that is gone is not offered")
    }

    func testIndexesNoOneChoseAreFoundAndKnownOnesAreNamed() throws {
        let home = try folder("home"), state = try folder("state")
        let notes = try Vault(project: try folder("home/Notes"), everything: true)
        notes.stateFolder = state
        KnownVaults.remember(notes)
        _ = try Vault(project: try folder("home/Downloads"), everything: true)          // the stray from 1.2.1
        _ = try Vault(project: try folder("home/Downloads/test"), everything: true)     // inside it: not looked for again
        _ = try Vault(project: try folder("home/Library/Caches/x"), everything: true)    // ~/Library is passed over
        _ = try Vault(project: try folder("home/a/b/c/d/deep"), everything: true)       // deeper than the scan
        _ = try folder("home/.hidden/thing")
        try Data(count: 4096).write(to: home.appendingPathComponent("Downloads/.camr/index-extra"))

        let found = IndexPlaces.all(home: home, state: state)
        XCTAssertEqual(found.map(\.known), [true, false])
        XCTAssertEqual(found.map { URL(fileURLWithPath: $0.root).lastPathComponent }, ["Notes", "Downloads"])
        XCTAssertGreaterThan(found[1].bytes, 4096)

        KnownVaults.forget(root: notes.root.path, in: state)
        XCTAssertTrue(KnownVaults.list(in: state).isEmpty)
        XCTAssertEqual(IndexPlaces.all(home: home, state: state).filter { !$0.known }.count, 2, "Notes is now found by the scan instead")
    }
}
