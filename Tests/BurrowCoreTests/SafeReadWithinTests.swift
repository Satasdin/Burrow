@testable import BurrowCore
import XCTest

/// D-112: a file is read only if the file actually opened lies inside the folder it was read from, checked on the open
/// file itself, so a folder on the way swapped for a link can't lead outside.
final class SafeReadWithinTests: XCTestCase {
    private var top: URL!

    override func setUpWithError() throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("saferead-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: top.appendingPathComponent("root/inside"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: top.appendingPathComponent("private"), withIntermediateDirectories: true)
        try "kept".write(to: top.appendingPathComponent("root/inside/note.md"), atomically: true, encoding: .utf8)
        try "secret diary".write(to: top.appendingPathComponent("private/Diary.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: top) }

    func testAFileInsideTheFolderIsRead() {
        let root = top.appendingPathComponent("root").path
        XCTAssertEqual(try? SafeRead.text(root + "/inside/note.md", cap: 1_000, within: root).get(), "kept")
    }

    func testAFolderOnTheWayThatLeadsOutsideIsRefused() throws {
        try FileManager.default.createSymbolicLink(at: top.appendingPathComponent("root/swapped"), withDestinationURL: top.appendingPathComponent("private"))
        let root = top.appendingPathComponent("root").path
        guard case let .failure(refusal) = SafeRead.text(root + "/swapped/Diary.md", cap: 1_000, within: root) else {
            return XCTFail("a file reached through a link out of the folder was read")
        }
        XCTAssertEqual(refusal, .outside)
    }

    func testTheSameFolderSpelledInAnotherCaseStillReads() {
        let root = top.appendingPathComponent("root").path
        let upper = root.replacingOccurrences(of: "/root", with: "/ROOT")
        XCTAssertEqual(try? SafeRead.text(root + "/inside/note.md", cap: 1_000, within: upper).get(), "kept")
    }
}
