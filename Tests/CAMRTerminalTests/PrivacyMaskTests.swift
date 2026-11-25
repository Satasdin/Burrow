@testable import CAMRCore
@testable import CAMRTools
import Foundation
import XCTest

/// Masking names, ID numbers, KRA PINs, phone numbers and emails in what CAMR hands out (D-126).
final class PrivacyMaskTests: XCTestCase {
    private let intake = """
    Fictional demo material.

    # Matter 2026/014 — Grace Akinyi Otieno v. Haraka Credit Ltd

    - Name: Grace Akinyi Otieno
    - National ID No.: 28456173
    - KRA PIN: A013948271K
    - Mobile: 0722 418 905 (prefers WhatsApp)
    - Email: grace.otieno@example.co.ke
    - SMS came from 0110 552 301 to 47 people.
    Grace Otieno called again from +254722418905; her ID was given as ID 28456173.
    Fee: KES 12000000 on file 7 March.
    """

    private let mask = PrivacyMask(people: PrivacyMask.people(in: """
    # clients
    Grace Akinyi Otieno | Grace Otieno | Mrs Otieno

    Brian Wekesa
    """))

    // MARK: Each pattern

    func testNamesFromThePeopleFileAndTheirOtherNames() {
        let out = mask.masked("Grace Akinyi Otieno met Brian Wekesa. Later grace  otieno and Mrs Otieno phoned. Graceful is a word.")
        XCTAssertEqual(out, "[PERSON-1] met [PERSON-2]. Later [PERSON-1] and [PERSON-1] phoned. Graceful is a word.")
    }

    func testNationalIDNumbersOnlyWithAnIDLabel() {
        XCTAssertEqual(mask.masked("National ID No.: 28456173"), "National ID No.: [ID-1]")
        XCTAssertEqual(mask.masked("**ID number:** 1234567 and I.D. 87654321"), "**ID number:** [ID-1] and I.D. [ID-2]")
        // Seven or eight digits with no ID label are a fee, an account or a count, and stay.
        XCTAssertEqual(mask.masked("KES 12000000; paid 28456173; HC-77120394"), "KES 12000000; paid 28456173; HC-77120394")
        // Nine digits are not an ID number.
        XCTAssertEqual(mask.masked("ID 123456789"), "ID 123456789")
    }

    func testKRAPIN() {
        XCTAssertEqual(mask.masked("KRA PIN: A013948271K, P051234567Z"), "KRA PIN: [PIN-1], [PIN-2]")
    }

    func testPhoneNumbersInEveryKenyanForm() {
        XCTAssertEqual(mask.masked("0722 418 905 / 0722-418-905 / +254722418905 / 254 722 418 905"),
                       "[PHONE-1] / [PHONE-1] / [PHONE-1] / [PHONE-1]")
        XCTAssertEqual(mask.masked("from 0110 552 301 and 0798114230"), "from [PHONE-1] and [PHONE-2]")
        // A longer run of digits is not a phone number.
        XCTAssertEqual(mask.masked("ref 007224189051"), "ref 007224189051")
        // Joined to letters or a dash it is another number: an SHA or NSSF number, a clinic number.
        XCTAssertEqual(mask.masked("SHA No.: SHA-0112-450981 | MFC-0722418905 | 0722418905x"), "SHA No.: SHA-0112-450981 | MFC-0722418905 | 0722418905x")
        XCTAssertEqual(mask.masked("(0722 418 905), tel:0722418905."), "([PHONE-1]), tel:[PHONE-1].")
    }

    func testEmailAddresses() {
        XCTAssertEqual(mask.masked("write to Grace.Otieno@example.co.ke or grace.otieno@example.co.ke, cc nw@wanjiru.law"),
                       "write to [EMAIL-1] or [EMAIL-1], cc [EMAIL-2]")
    }

    // MARK: Stability, lines and paths

    func testPlaceholdersAreStableWithinOneResponse() {
        let out = mask.masked(intake)
        XCTAssertFalse(out.contains("Otieno"))
        XCTAssertFalse(out.contains("28456173"))
        XCTAssertFalse(out.contains("418"))
        XCTAssertFalse(out.contains("A013948271K"))
        XCTAssertFalse(out.contains("@example"))
        // One person, one ID, one phone: the same placeholder every time it comes back.
        XCTAssertEqual(out.components(separatedBy: "[PERSON-1]").count - 1, 3)
        XCTAssertEqual(out.components(separatedBy: "[ID-1]").count - 1, 2)
        XCTAssertEqual(out.components(separatedBy: "[PHONE-1]").count - 1, 2)
        XCTAssertTrue(out.contains("[PHONE-2]"))
        XCTAssertFalse(out.contains("[ID-2]"))
        XCTAssertTrue(out.contains("KES 12000000"))
        XCTAssertTrue(out.contains("Haraka Credit Ltd"))
        // Masking twice changes nothing.
        XCTAssertEqual(mask.masked(out), out)
    }

    func testLinesStayWhereTheyWereAndCitedPathsAreKept() {
        let path = "cases/2026-014-otieno-v-grace otieno.md"
        let text = "<excerpt file=\"\(path)\" lines=\"3-5\">\n3: Grace Otieno\n4: 0722 418 905\n5: done\n</excerpt>\n\(path) has 5 lines."
        let out = mask.masked(text, keeping: [path])
        XCTAssertEqual(out.components(separatedBy: "\n").count, text.components(separatedBy: "\n").count)
        XCTAssertEqual(out, "<excerpt file=\"\(path)\" lines=\"3-5\">\n3: [PERSON-1]\n4: [PHONE-1]\n5: done\n</excerpt>\n\(path) has 5 lines.")
        // In JSON the slashes of a path may be escaped; that form is kept too.
        let json = #"{"path":"cases\/2026-014-otieno-v-grace otieno.md","text":"Grace Otieno"}"#
        XCTAssertEqual(mask.masked(json, keeping: [path]), #"{"path":"cases\/2026-014-otieno-v-grace otieno.md","text":"[PERSON-1]"}"#)
    }

    func testPeopleFileFormat() {
        XCTAssertEqual(PrivacyMask.people(in: "# note\n\n  Njeri  Wanjiru |  Adv. Wanjiru \nX\n"), [["Njeri Wanjiru", "Adv. Wanjiru"]])
    }

    // MARK: Through the tools, on a vault

    private var top: URL!

    override func setUpWithError() throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = top.appendingPathComponent("vault/cases/2026-014-intake.md")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try intake.write(to: file, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: top) }

    private func tools() async throws -> VaultTools {
        let vault = try Vault(project: top.appendingPathComponent("vault"), everything: true)
        vault.stateFolder = top.appendingPathComponent("state")
        try await vault.refresh(embedder: nil)
        return VaultTools(vault: vault, embedder: nil) { _ in FakeAnswerer() }
    }

    private func turnOn(_ tools: VaultTools, people: String = "Grace Akinyi Otieno | Grace Otieno\n") throws {
        var settings = tools.vault.config
        try settings.set("privacy.mask", "on")
        try people.write(to: PrivacyMask.peopleFile(tools.vault), atomically: true, encoding: .utf8)
    }

    func testOffByDefaultNothingChanges() async throws {
        let tools = try await tools()
        XCTAssertFalse(tools.vault.config.privacyMask)
        XCTAssertNil(PrivacyMask.forVault(tools.vault))
        // A people file alone does not turn masking on.
        try "Grace Akinyi Otieno\n".write(to: PrivacyMask.peopleFile(tools.vault), atomically: true, encoding: .utf8)
        let found = try await tools.call("camr_find", arguments: ["query": "Grace Otieno mobile ID"])
        XCTAssertTrue(found.text.contains("Grace Akinyi Otieno"), found.text)
        XCTAssertTrue(found.text.contains("28456173"))
        let read = try await tools.call("camr_read", arguments: ["path": "cases/2026-014-intake.md"])
        XCTAssertTrue(read.text.contains("0722 418 905"))
        XCTAssertFalse(read.text.contains("[PERSON-"))
    }

    func testFindAndReadAreMaskedAndCitationsStillPointAtTheRightLines() async throws {
        let tools = try await tools()
        try turnOn(tools)
        let before = try String(contentsOf: top.appendingPathComponent("vault/cases/2026-014-intake.md"), encoding: .utf8)

        let read = try await tools.call("camr_read", arguments: ["path": "cases/2026-014-intake.md"])
        XCTAssertFalse(read.isError, read.text)
        for real in ["Otieno", "28456173", "0722 418 905", "+254722418905", "A013948271K", "grace.otieno@"] {
            XCTAssertFalse(read.text.contains(real), "\(real) was handed out:\n\(read.text)")
        }
        // Line 6 of the file is the ID line; it is still numbered 6, with the placeholder in it.
        XCTAssertTrue(read.text.contains("6: - National ID No.: [ID-1]"), read.text)
        XCTAssertTrue(read.text.contains("5: - Name: [PERSON-1]"), read.text)
        XCTAssertTrue(read.text.contains("11: [PERSON-1] called again from [PHONE-1]; her ID was given as ID [ID-1]."), read.text)
        XCTAssertEqual(read.sources, [ToolResult.Source(path: "cases/2026-014-intake.md", startLine: 1, endLine: 12, reason: "read")])
        XCTAssertTrue(read.text.contains("file=\"cases/2026-014-intake.md\""))

        let found = try await tools.call("camr_find", arguments: ["query": "Grace Otieno mobile"])
        XCTAssertFalse(found.text.contains("Otieno"), found.text)
        XCTAssertFalse(found.text.contains("418 905"))
        XCTAssertTrue(found.text.contains("[PERSON-1]"))
        XCTAssertTrue(found.text.contains("[PHONE-1]"))
        // Each cited place names the real file and lines, and the masked line sits at the line it names.
        for source in found.sources {
            XCTAssertEqual(source.path, "cases/2026-014-intake.md")
            XCTAssertTrue(found.text.contains("lines=\"\(source.startLine)-\(source.endLine)\""))
        }
        XCTAssertTrue(found.text.contains("7: - KRA PIN: [PIN-1]"), found.text)

        // The file on disk is never changed.
        XCTAssertEqual(try String(contentsOf: top.appendingPathComponent("vault/cases/2026-014-intake.md"), encoding: .utf8), before)

        // Turned off again, the next call hands out the original text.
        var settings = tools.vault.config
        try settings.set("privacy.mask", "off")
        let again = try await tools.call("camr_read", arguments: ["path": "cases/2026-014-intake.md"])
        XCTAssertTrue(again.text.contains("Grace Akinyi Otieno"))
    }

    func testPrepareIsMasked() async throws {
        let tools = try await tools()
        try turnOn(tools)
        let brief = try await tools.call("vault_prepare", arguments: ["task": "Summarise Grace Otieno's matter and her contacts"])
        XCTAssertFalse(brief.isError, brief.text)
        XCTAssertFalse(brief.text.contains("Otieno"), brief.text)
        XCTAssertFalse(brief.text.contains("28456173"))
    }

    func testTheSettingTakesOnlyOnOrOff() throws {
        var settings = CAMRConfig(file: top.appendingPathComponent("config.json"), isGlobal: false)
        try settings.set("privacy.mask", "YES")
        XCTAssertEqual(settings.value("privacy.mask"), "on")
        XCTAssertThrowsError(try settings.set("privacy.mask", "maybe"))
        var global = CAMRConfig(file: top.appendingPathComponent("global.json"), isGlobal: true)
        XCTAssertThrowsError(try global.set("privacy.mask", "on"))
    }
}
