@testable import BurrowCore
import XCTest

/// The check that keeps a place the model was never given from reading as a source (D-91).
final class CitationCheckTests: XCTestCase {
    private let lease = ShownLines(path: "Home/Lease-Kilimani-flat.md", startLine: 1, endLine: 23)
    private let decision = "20261114-065345-a355"

    func testTheInventedCitationFromTheFilmIsTakenOutAndStillReported() {
        // The app's Ask, 14 November: right amounts, and the rules' own example as the citation.
        let checked = Citations.check("I send KES 18,000 and Wanjiru sends KES 27,000. (notes/plan.md:12)", shown: [lease])
        XCTAssertEqual(checked.text, "I send KES 18,000 and Wanjiru sends KES 27,000.")
        XCTAssertEqual(checked.unverified, ["notes/plan.md:12"])
    }

    func testACitationThatWasShownStays() {
        let answer = "Rent is KES 45,000, due by the 5th (Home/Lease-Kilimani-flat.md:7). From `Home/Lease-Kilimani-flat.md`:13-18."
        let checked = Citations.check(answer, shown: [lease])
        XCTAssertEqual(checked.text, answer)
        XCTAssertTrue(checked.unverified.isEmpty)
    }

    func testOneOfAListGoesWithItsComma() {
        let first = Citations.check("Rent is KES 45,000 (Home/Lease-Kilimani-flat.md:7, notes/plan.md:12).", shown: [lease])
        XCTAssertEqual(first.text, "Rent is KES 45,000 (Home/Lease-Kilimani-flat.md:7).")
        let second = Citations.check("Rent is KES 45,000 (notes/plan.md:12; Home/Lease-Kilimani-flat.md:7).", shown: [lease])
        XCTAssertEqual(second.text, "Rent is KES 45,000 (Home/Lease-Kilimani-flat.md:7).")
    }

    func testFillerWordsInTheBracketsGoWithIt() {
        let checked = Citations.check("You pay KES 18,000 (from `notes/plan.md`, line 12).", shown: [lease])
        XCTAssertEqual(checked.text, "You pay KES 18,000.")
        XCTAssertEqual(checked.unverified, ["notes/plan.md:12"])
    }

    func testOneInsideASentenceIsMarkedNotCut() {
        let checked = Citations.check("This comes from notes/plan.md:12, which says 60/40.", shown: [lease])
        XCTAssertEqual(checked.text, "This comes from notes/plan.md:12\(Citations.notReadMark), which says 60/40.")
        XCTAssertEqual(checked.unverified, ["notes/plan.md:12"])
    }

    func testALedgerIdItWasGivenCountsAndOneItWasNotIsTakenOut() {
        let given = Citations.check("You pay KES 18,000 (Ledger \(decision)).", shown: [], ledger: [decision])
        XCTAssertEqual(given.text, "You pay KES 18,000 (Ledger \(decision)).")
        XCTAssertEqual(given.ledgerCited, [decision])
        let made = Citations.check("You pay KES 18,000 (Ledger 20260101-120000-0a1b).", shown: [], ledger: [decision])
        XCTAssertEqual(made.text, "You pay KES 18,000.")
        XCTAssertEqual(made.unverified, ["Ledger 20260101-120000-0a1b"])
        XCTAssertTrue(made.ledgerCited.isEmpty)
    }

    func testEachLineIsCheckedOnItsOwnTheSameAsTheWhole() {
        // `burrow chat` checks the answer a line at a time as it streams; the lines must add up to the whole check.
        let answer = "You pay KES 18,000 (notes/plan.md:12).\nWanjiru pays KES 27,000 (Home/Lease-Kilimani-flat.md:7).\n"
        let whole = Citations.check(answer, shown: [lease]).text
        let lines = answer.split(separator: "\n", omittingEmptySubsequences: false).map { Citations.check(String($0), shown: [lease]).text }
        XCTAssertEqual(lines.joined(separator: "\n"), whole)
        XCTAssertEqual(Citations.ledgerIDs(in: "- Ledger \(decision) [decision]: x, and \(decision) again"), [decision])
    }
}
