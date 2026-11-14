@testable import BurrowCore
@testable import BurrowTools
import Foundation
import XCTest

/// D-112: what a teammate can put in the team folder can't lead Burrow anywhere or stall it (links, pipes, huge files),
/// a correction run by a program waits for the person, and every prompt shows the whole text agreed to.
final class TeamFilesTests: XCTestCase {
    private var top: URL!
    private var teamFolder: URL { top.appendingPathComponent("TeamShared") }
    private var state: URL { top.appendingPathComponent("state") }
    private var privateDiary: URL { top.appendingPathComponent("Private/Diary.md") }
    private var vault: Vault!
    private var team: Team!

    override func setUp() async throws {
        top = FileManager.default.temporaryDirectory.appendingPathComponent("team-files-" + UUID().uuidString)
        for (path, text) in [
            "TeamShared/Plans/Refunds.md": "# Refunds\n\nA provider timeout leaves the refund state unknown.\n",
            "Otieno/Home.md": "# Home\n\nFootball on Thursdays.\n",
            "Private/Diary.md": Self.commitText(id: "20261114-100000-aaaa-mallory-0000", folder: "mallory-0000", message: "jacaranda-42 private diary line."),
        ] {
            let url = top.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        vault = try Vault(project: top.appendingPathComponent("Otieno"), everything: true)
        vault.stateFolder = state
        try await vault.refresh()
        team = try vault.joinTeam(teamFolder, name: "Team", person: "Otieno Ouma")
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: top) }

    static func commitText(id: String, folder: String, message: String, person: String = "Mallory", padding: Int = 0) -> String {
        "---\nid: \"\(id)\"\nbranch: \"\(folder)\"\nkind: \"decision\"\nauthor: \"claude-code\"\nperson: \"\(person)\"\nat: \"2026-11-14T07:00:00Z\"\n---\n\n"
            + message + "\n\nBecause: a reason." + String(repeating: " ", count: padding) + "\n"
    }

    private func mallory() throws -> URL {
        let place = teamFolder.appendingPathComponent(".burrow/ledger/mallory-0000")
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        return place
    }

    // MARK: Reading the team Ledger

    func testLinksPipesAndHugeFilesInATeammatesFolderAreNeverReadAndNothingHangs() throws {
        let place = try mallory()
        // A link to the private diary, written to read as a decision; a FIFO named as a decision; a 70 KB decision.
        try FileManager.default.createSymbolicLink(atPath: place.appendingPathComponent("20261114-100000-aaaa-mallory-0000.md").path, withDestinationPath: privateDiary.path)
        XCTAssertEqual(mkfifo(place.appendingPathComponent("20261114-100001-bbbb-mallory-0000.md").path, 0o644), 0)
        try Self.commitText(id: "20261114-100002-cccc-mallory-0000", folder: "mallory-0000", message: "Huge.", padding: 70 * 1024)
            .write(to: place.appendingPathComponent("20261114-100002-cccc-mallory-0000.md"), atomically: true, encoding: .utf8)
        try Self.commitText(id: "20261114-100003-dddd-mallory-0000", folder: "mallory-0000", message: "Small and ordinary.")
            .write(to: place.appendingPathComponent("20261114-100003-dddd-mallory-0000.md"), atomically: true, encoding: .utf8)
        // A whole person folder that is a link to another folder of commits.
        let elsewhere = top.appendingPathComponent("Elsewhere/amina-abcd")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Self.commitText(id: "20261114-100004-eeee-amina-abcd", folder: "amina-abcd", message: "From outside.", person: "Amina")
            .write(to: elsewhere.appendingPathComponent("20261114-100004-eeee-amina-abcd.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(atPath: teamFolder.appendingPathComponent(".burrow/ledger/amina-abcd").path, withDestinationPath: elsewhere.path)

        let started = Date()
        let scanned = TeamLedger.scan(team)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "nothing blocks on the pipe")
        XCTAssertEqual(scanned.commits.map(\.message), ["Small and ordinary."])
        let skipped = scanned.skipped.joined(separator: "\n")
        XCTAssertTrue(skipped.contains("aaaa-mallory-0000.md: a symbolic link, never followed"), skipped)
        XCTAssertTrue(skipped.contains("bbbb-mallory-0000.md: not a regular file"), skipped)
        XCTAssertTrue(skipped.contains("cccc-mallory-0000.md: larger than allowed"), skipped)
        XCTAssertTrue(skipped.contains("amina-abcd: a link to a folder, never followed"), skipped)
        let tools = VaultTools(vault: vault, embedder: nil) { _ in FakeAnswerer() }
        XCTAssertFalse(tools.rulesInForce().contains("jacaranda"))
        XCTAssertFalse(tools.rulesInForce().contains("From outside"))
        // The team log says what was left out and why.
        let log = try BurrowBinary.piped(["team", "log", vault.root.path], state: state)
        XCTAssertTrue(log.out.contains("not read: mallory-0000/20261114-100001-bbbb-mallory-0000.md: not a regular file"), log.out)
    }

    func testATeamLedgerFolderThatIsALinkIsNotRead() throws {
        let elsewhere = top.appendingPathComponent("Elsewhere/ledger/mallory-0000")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Self.commitText(id: "20261114-100000-aaaa-mallory-0000", folder: "mallory-0000", message: "Via a linked ledger.")
            .write(to: elsewhere.appendingPathComponent("20261114-100000-aaaa-mallory-0000.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: teamFolder.appendingPathComponent(".burrow"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: team.ledgerFolder.path, withDestinationPath: top.appendingPathComponent("Elsewhere/ledger").path)
        XCTAssertTrue(TeamLedger.commits(team).isEmpty)
        XCTAssertThrowsError(try TeamLedger.commit(vault: vault, team: team, kind: .decision, message: "Mine.", author: "person", client: "terminal"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: top.appendingPathComponent("Elsewhere/ledger").path), ["mallory-0000"], "nothing written through the link")
    }

    func testWritingNeverGoesThroughALinkAndAPlantedTipIsNotRead() throws {
        let member = try XCTUnwrap(vault.teamMember)
        let mine = teamFolder.appendingPathComponent(".burrow/ledger/\(member.folder)")
        // A link planted where this person's folder will be.
        let target = top.appendingPathComponent("Target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: mine.path, withDestinationPath: target.path)
        XCTAssertThrowsError(try TeamLedger.commit(vault: vault, team: team, kind: .decision, message: "Mine.", author: "person", client: "terminal")) {
            XCTAssertTrue("\($0)".contains("is a link or not a folder"), "\($0)")
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
        // A FIFO planted as this person's tip file: writing neither blocks on it nor trusts it.
        try FileManager.default.removeItem(atPath: mine.path)
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        XCTAssertEqual(mkfifo(mine.appendingPathComponent(".tip").path, 0o644), 0)
        let started = Date()
        let made = try TeamLedger.commit(vault: vault, team: team, kind: .decision, message: "Mine.", author: "person", client: "terminal")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertNil(made.parent)
        XCTAssertEqual(SafeRead.kind(mine.appendingPathComponent(".tip").path), .typeRegular)
        let second = try TeamLedger.commit(vault: vault, team: team, kind: .decision, message: "Mine again.", author: "person", client: "terminal")
        XCTAssertEqual(second.parent, made.id)
    }

    func testTheTeamIndexSkipsPipesAndLinksOutAndDoesNotHang() async throws {
        XCTAssertEqual(mkfifo(teamFolder.appendingPathComponent("Plans/Pipe.md").path, 0o644), 0)
        try FileManager.default.createSymbolicLink(atPath: teamFolder.appendingPathComponent("Plans/Diary.md").path, withDestinationPath: privateDiary.path)
        let started = Date()
        let problems = await vault.refreshTeams()
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertTrue(problems.isEmpty, "\(problems)")
        let files = vault.bridgedShelves().first { $0.bridge.name == "Team" }?.files.map(\.path) ?? []
        XCTAssertEqual(files, ["Team › Plans/Refunds.md"])
        XCTAssertEqual(SafeRead.data(privateDiary.path, cap: 10).failureReason, .tooLarge(try Data(contentsOf: privateDiary).count))
    }

    // MARK: Corrections and prompts

    func testACorrectionFromAProgramWaitsAndThePersonSeesTheWholeDecisionBeforeAgreeing() throws {
        let place = try mallory()
        let longReason = "Because: " + String(repeating: "the conductors on the Thika Road routes asked for it, ", count: 6) + "end of reason."
        try (Self.commitText(id: "20261114-100000-aaaa-mallory-0000", folder: "mallory-0000", message: "Fares are rounded to 10 shillings.")
            .replacingOccurrences(of: "Because: a reason.", with: longReason))
            .write(to: place.appendingPathComponent("20261114-100000-aaaa-mallory-0000.md"), atomically: true, encoding: .utf8)
        let before = try FileManager.default.contentsOfDirectory(atPath: team.ledgerFolder.path)

        let piped = try BurrowBinary.piped(["team", "revert", vault.root.path, "20261114-100000-aaaa-mallory-0000", "Fares stay exact."], state: state, input: "yes\n")
        XCTAssertEqual(piped.status, 0, piped.err)
        XCTAssertTrue(piped.out.contains("Not marked wrong yet: waiting for Otieno Ouma's approval"), piped.out)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: team.ledgerFolder.path), before, "nothing written to the team folder")
        let waiting = try XCTUnwrap(TeamPending.list(vault).first)
        XCTAssertEqual(waiting.kind, .correction)
        XCTAssertEqual(waiting.reverts, "20261114-100000-aaaa-mallory-0000")
        XCTAssertTrue(TeamPending.shown(waiting).joined(separator: "\n").contains("end of reason."), "the decision it marks wrong is shown whole")

        let no = try BurrowBinary.inTerminal(["team", "approve", vault.root.path, waiting.id], state: state, answer: "no")
        XCTAssertTrue(no.out.contains("and it marks this team decision wrong:") && no.out.contains("end of reason."), no.out)
        XCTAssertEqual(TeamLedger.retirements(TeamLedger.commits(team)).count, 0)
        let yes = try BurrowBinary.inTerminal(["team", "approve", vault.root.path, waiting.id], state: state, answer: "yes")
        XCTAssertEqual(yes.status, 0, yes.out)
        XCTAssertEqual(Set(TeamLedger.retirements(TeamLedger.commits(team)).keys), ["20261114-100000-aaaa-mallory-0000"])
    }

    func testADirectRevertAndATypedShareAskWithTheWholeText() throws {
        let place = try mallory()
        try Self.commitText(id: "20261114-100000-aaaa-mallory-0000", folder: "mallory-0000", message: "Fares are rounded to 10 shillings.")
            .write(to: place.appendingPathComponent("20261114-100000-aaaa-mallory-0000.md"), atomically: true, encoding: .utf8)
        let refused = try BurrowBinary.inTerminal(["team", "revert", vault.root.path, "20261114-100000-aaaa-mallory-0000", "Fares stay exact."], state: state, answer: "no")
        XCTAssertTrue(refused.out.contains("Mark this team decision wrong for everyone in Team?") && refused.out.contains("Fares are rounded to 10 shillings.")
                      && refused.out.contains("Fares stay exact."), refused.out)
        XCTAssertTrue(TeamLedger.retirements(TeamLedger.commits(team)).isEmpty)
        let done = try BurrowBinary.inTerminal(["team", "revert", vault.root.path, "20261114-100000-aaaa-mallory-0000", "Fares stay exact."], state: state, answer: "yes")
        XCTAssertEqual(done.status, 0, done.out)
        XCTAssertEqual(TeamLedger.retirements(TeamLedger.commits(team)).count, 1)

        let share = try BurrowBinary.inTerminal(["commit", vault.root.path, "Support runs from Nairobi.", "--kind", "decision", "--because", "Two of us are there.", "--team"],
                                                state: state, answer: "no")
        XCTAssertTrue(share.out.contains("Support runs from Nairobi.") && share.out.contains("Because: Two of us are there."), share.out)
        XCTAssertFalse(TeamLedger.commits(team).contains { $0.message == "Support runs from Nairobi." })
    }
}

private extension Result {
    var failureReason: Failure? { if case let .failure(reason) = self { return reason } else { return nil } }
}
