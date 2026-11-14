@testable import BurrowCore
import Foundation
import XCTest

/// Storage limits and config (D-98): Burrow stops adding to its own store before a limit, and never deletes a file.
final class StorageLimitTests: XCTestCase {
    private var top: URL!
    private var state: URL { top.appendingPathComponent("state") }

    override func setUpWithError() throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("storage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: top, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: top) }

    private func write(_ path: String, _ text: String) throws {
        let url = top.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func vault(_ name: String) throws -> Vault {
        let opened = try Vault(project: top.appendingPathComponent(name), everything: true)
        opened.stateFolder = state
        return opened
    }

    /// Thirty notes of distinct words, about 3 KB each.
    private func manyNotes(in vault: String, from start: Int = 0) throws {
        for number in start..<(start + 30) {
            let lines = (0..<40).map { "Line \($0) of note \(number): word\(number)x\($0) item\($0 * number) agreed by person\($0 % 7)." }
            try write("\(vault)/Meetings/Sync-\(number).md", "# Sync \(number)\n\n" + lines.joined(separator: "\n") + "\n")
        }
    }

    private struct Fake: Embedder {
        func embed(_ texts: [String]) async throws -> [[Float]] {
            texts.map { text in (0..<64).map { Float((text.hashValue >> ($0 % 32)) & 7) + 0.5 } }
        }
    }

    private func hashes(_ folder: String) throws -> [String: Data] {
        var out: [String: Data] = [:]
        for case let url as URL in FileManager.default.enumerator(at: top.appendingPathComponent(folder), includingPropertiesForKeys: nil)!
        where !url.hasDirectoryPath && !url.path.contains("/.burrow/") {
            out[url.path] = try Data(contentsOf: url)
        }
        return out
    }

    func testSizesAsPeopleWriteThem() {
        XCTAssertEqual(ByteSize.parse("2GB"), 2_000_000_000)
        XCTAssertEqual(ByteSize.parse("500 MB"), 500_000_000)
        XCTAssertEqual(ByteSize.parse("1.5gb"), 1_500_000_000)
        XCTAssertEqual(ByteSize.parse("800k"), 800_000)
        XCTAssertEqual(ByteSize.parse("1GiB"), 1_073_741_824)
        XCTAssertEqual(ByteSize.parse("4096"), 4096)
        XCTAssertNil(ByteSize.parse("lots"))
        XCTAssertNil(ByteSize.parse("2 parsecs"))
        XCTAssertNil(ByteSize.parse("-5MB"))
        XCTAssertEqual(ByteSize.format(312_400), "312 KB")
        XCTAssertEqual(ByteSize.format(82_300), "82.3 KB")
        XCTAssertEqual(ByteSize.format(2_000_000_000), "2 GB")
        XCTAssertEqual(ByteSize.format(512), "512 bytes")
    }

    func testConfigKeepsVaultAndGlobalSettingsApart() throws {
        let home = try vault("Home")
        var settings = home.config
        try settings.set("storage.limit", "2GB")
        XCTAssertEqual(home.config.storageLimit, 2_000_000_000)
        XCTAssertThrowsError(try settings.set("storage.limit", "plenty"))
        XCTAssertThrowsError(try settings.set("storage.limit", "0"))
        XCTAssertThrowsError(try settings.set("colour", "blue"))
        var global = home.globalConfig
        XCTAssertThrowsError(try global.set("vault.name", "Home"), "a vault's name is not global")
        try global.set("storage.limit", "10GB")
        XCTAssertEqual(home.globalConfig.storageLimit, 10_000_000_000)
        XCTAssertEqual(global.file.deletingLastPathComponent().path, state.path, "global settings live in Burrow's own folder")
        XCTAssertTrue(try settings.unset("storage.limit"))
        XCTAssertNil(home.config.storageLimit)
    }

    func testIndexingStopsBeforeTheVaultLimitAndDeletesNothing() async throws {
        try write("Work/Plan.md", "# Plan\n\nLaunch in February.\n")
        let work = try vault("Work")
        try await work.refresh()
        let ledger = top.appendingPathComponent("Work/.burrow/ledger/main/1.md")
        try FileManager.default.createDirectory(at: ledger.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "kept decision".write(to: ledger, atomically: true, encoding: .utf8)
        let limit = try work.storageUsage().total + 40_000
        var settings = work.config
        try settings.set("storage.limit", "\(limit)")
        try manyNotes(in: "Work")
        let before = try hashes("Work")

        let report = try await work.refresh(embedder: Fake())
        let stop = try XCTUnwrap(report.storageStop)
        XCTAssertEqual(stop.which, .vault)
        XCTAssertFalse(stop.filesNotAdded.isEmpty)
        XCTAssertGreaterThan(report.filesChanged, 0, "what fits goes in")
        XCTAssertLessThanOrEqual(try work.storageUsage().total, limit, "never over the limit")
        XCTAssertTrue(stop.message.contains("Nothing was deleted"))
        XCTAssertTrue(stop.message.contains("burrow config"))
        XCTAssertNotNil(stop.needed)
        XCTAssertEqual(try hashes("Work"), before, "every file is as it was")
        XCTAssertEqual(try String(contentsOf: ledger, encoding: .utf8), "kept decision", "the Ledger is untouched")
        // What did go in is still found.
        let found = try await work.retrieve("Launch in February", mode: .search)
        XCTAssertEqual(found.excerpts.first?.path, "Plan.md")

        // Raised past what it needs, the same index finishes.
        try settings.set("storage.limit", "\(stop.needed! * 2)")
        let finished = try await work.refresh(embedder: Fake())
        XCTAssertNil(finished.storageStop)
        XCTAssertEqual(try work.projectMap().files.count, 31)
        XCTAssertEqual(try work.stats().vectors, try work.stats().chunks)
    }

    func testTheGlobalLimitCountsEveryKnownVault() async throws {
        try write("Home/Rent.md", "# Rent\n\nDue on the fifth.\n")
        try write("Work/Plan.md", "# Plan\n\nLaunch in February.\n")
        let home = try vault("Home")
        let work = try vault("Work")
        try await home.refresh()
        try await work.refresh()
        KnownVaults.remember(home)
        KnownVaults.remember(work)
        XCTAssertEqual(KnownVaults.list(in: state).count, 2)
        let together = try home.storageUsage().total + work.storageUsage().total
        var global = home.globalConfig
        try global.set("storage.limit", "\(together + 30_000)")
        try manyNotes(in: "Home")
        let report = try await home.refresh()
        let stop = try XCTUnwrap(report.storageStop)
        XCTAssertEqual(stop.which, .global)
        XCTAssertTrue(stop.message.contains("--global"))
        let report2 = try home.storageReport()
        XCTAssertEqual(report2.vaultCount, 2)
        XCTAssertLessThanOrEqual(report2.allVaults, together + 30_000)
    }

    func testRemovingFilesMakesRoom() async throws {
        try manyNotes(in: "Work")
        let work = try vault("Work")
        try await work.refresh()
        let full = try work.storageUsage().total
        for number in 0..<20 { try FileManager.default.removeItem(at: top.appendingPathComponent("Work/Meetings/Sync-\(number).md")) }
        try await work.refresh()
        XCTAssertLessThan(try work.storageUsage().total, full, "freed pages are not counted as used")
    }

    func testLargeFilesAreLeftOutWhenAsked() async throws {
        try write("Work/Small.md", "# Small\n\nShort.\n")
        try write("Work/Big.md", "# Big\n\n" + String(repeating: "A long line of words. ", count: 400))
        let work = try vault("Work")
        var settings = work.config
        try settings.set("index.maxFileSize", "2KB")
        let report = try await work.refresh()
        XCTAssertEqual(report.tooLarge, 1)
        XCTAssertEqual(try work.projectMap().files.map(\.path), ["Small.md"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: top.appendingPathComponent("Work/Big.md").path))
    }

    func testNoLimitMeansNoMeasuring() throws {
        let work = try vault("Work")
        XCTAssertNil(StorageGuard(vault: work))
    }
}
