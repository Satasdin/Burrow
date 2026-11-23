@testable import CAMRCore
import XCTest

/// D-113: CAMR's state folder is the person's alone: created 0700, and tightened if an earlier CAMR made it 0755.
final class StateFolderPrivacyTests: XCTestCase {
    private func mode(_ url: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int ?? -1 }

    func testANewStateFolderIsCreatedPrivate() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("state-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        CAMRPlaces.makePrivate(folder)
        XCTAssertEqual(mode(folder) & 0o777, 0o700)
    }

    func testALooserStateFolderIsTightened() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("state-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        CAMRPlaces.makePrivate(folder)
        XCTAssertEqual(mode(folder) & 0o777, 0o700)
    }
}
