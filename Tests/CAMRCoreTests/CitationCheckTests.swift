@testable import CAMRCore
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
        // `camr chat` checks the answer a line at a time as it streams; the lines must add up to the whole check.
        let answer = "You pay KES 18,000 (notes/plan.md:12).\nWanjiru pays KES 27,000 (Home/Lease-Kilimani-flat.md:7).\n"
        let whole = Citations.check(answer, shown: [lease]).text
        let lines = answer.split(separator: "\n", omittingEmptySubsequences: false).map { Citations.check(String($0), shown: [lease]).text }
        XCTAssertEqual(lines.joined(separator: "\n"), whole)
        XCTAssertEqual(Citations.ledgerIDs(in: "- Ledger \(decision) [decision]: x, and \(decision) again"), [decision])
    }

    // MARK: Nasty answers (D-92): nothing a model writes may make the check throw.

    func testSeveralInventedCitationsInOneBracketGoTogether() {
        // Before D-92 the second cut used a range the first had already taken away, and NSString threw.
        let made = "Rent is KES 45,000 (see Ledger 20260101-120000-0a1a and Ledger 20260101-120000-0a2a)."
        let checked = Citations.check(made, shown: [lease])
        XCTAssertEqual(checked.text, "Rent is KES 45,000.")
        XCTAssertEqual(checked.unverified, ["Ledger 20260101-120000-0a1a", "Ledger 20260101-120000-0a2a"])
        let files = Citations.check("Rent is KES 45,000 (notes/a.md:1, notes/b.md:2; notes/c.md:3).", shown: [lease])
        XCTAssertEqual(files.text, "Rent is KES 45,000.")
        XCTAssertEqual(files.unverified, ["notes/a.md:1", "notes/b.md:2", "notes/c.md:3"])
    }

    func testAShownCitationKeepsItsPlaceAmongInventedOnes() {
        let checked = Citations.check("Rent is KES 45,000 (notes/a.md:1, Home/Lease-Kilimani-flat.md:7, notes/b.md:2).", shown: [lease])
        XCTAssertEqual(checked.text, "Rent is KES 45,000 (Home/Lease-Kilimani-flat.md:7).")
    }

    func testRepeatedIdenticalCitationsAllGo() {
        let made = "You pay 40% (Ledger 20260101-120000-0a1b) (Ledger 20260101-120000-0a1b) [Ledger 20260101-120000-0a1b]."
        let checked = Citations.check(made, shown: [], ledger: [decision])
        XCTAssertEqual(checked.text, "You pay 40%.")
        XCTAssertEqual(checked.unverified, ["Ledger 20260101-120000-0a1b"])
        XCTAssertEqual(Citations.check("(notes/plan.md:12, notes/plan.md:12)", shown: [lease]).text, "")
    }

    func testBracketsAtTheVeryStartAndEnd() {
        XCTAssertEqual(Citations.check("(notes/plan.md:12)", shown: [lease]).text, "")
        XCTAssertEqual(Citations.check("(notes/plan.md:12) Rent is KES 45,000.", shown: [lease]).text, " Rent is KES 45,000.")
        XCTAssertEqual(Citations.check("Rent is KES 45,000 [Ledger 20260101-120000-0a1b]", shown: []).text, "Rent is KES 45,000")
        XCTAssertEqual(Citations.check("notes/plan.md:12", shown: [lease]).text, "notes/plan.md:12" + Citations.notReadMark)
    }

    func testUnbalancedAndNestedBracketsDoNotThrow() {
        for answer in [
            "Rent (see (notes/plan.md:12) and [Ledger 20260101-120000-0a1b",
            "((((notes/plan.md:12",
            "notes/plan.md:12))))]]",
            ")(notes/plan.md:12)(",
            "[(notes/a.md:1] notes/b.md:2)",
            "(notes/a.md:1 (Ledger 20260101-120000-0a1b) notes/b.md:2)",
            "(`notes/plan.md`) line 12)",
        ] {
            let checked = Citations.check(answer, shown: [lease], ledger: [decision])
            XCTAssertFalse(checked.unverified.isEmpty, answer)
        }
    }

    func testUnicodeBeforeTheCitationKeepsItsPlace() {
        let checked = Citations.check("家賃 🏠👨‍👩‍👧 は KES 45,000 (notes/plan.md:12). 🎉 You pay 40% (Ledger 20260101-120000-0a1b).", shown: [lease])
        XCTAssertEqual(checked.text, "家賃 🏠👨‍👩‍👧 は KES 45,000. 🎉 You pay 40%.")
        let marked = Citations.check("見て 🙂 notes/plan.md:12 です", shown: [lease])
        XCTAssertEqual(marked.text, "見て 🙂 notes/plan.md:12\(Citations.notReadMark) です")
    }

    func testAnEmptyAnswer() {
        XCTAssertEqual(Citations.check("", shown: [lease], ledger: [decision]), CheckedAnswer(text: "", unverified: [], ledgerCited: []))
        XCTAssertEqual(Citations.check("\n\n", shown: []).text, "\n\n")
    }

    func testEditsThatOverlapOrRunPastTheEndCannotThrow() {
        let text = "abc (x) def" as NSString
        let edits = [
            Citations.Edit(range: NSRange(location: 4, length: 3), with: ""),
            Citations.Edit(range: NSRange(location: 2, length: 4), with: ""),
            Citations.Edit(range: NSRange(location: 5, length: 0), with: "!"),
            Citations.Edit(range: NSRange(location: 9, length: 50), with: ""),
            Citations.Edit(range: NSRange(location: 400, length: 0), with: "?"),
            Citations.Edit(range: NSRange(location: -3, length: 1), with: ""),
        ]
        // The cut before the start is held to the first character; the mark inside a cut goes with it.
        XCTAssertEqual(Citations.apply(edits, to: text), "b d?")
    }

    func testRandomAnswersBuiltFromTheNastyPiecesNeverThrow() {
        // Seeded, so a failure can be run again. A throw would end the test run, so passing is the proof.
        var generator = SeededGenerator(seed: 0x5EED_D092)
        let pieces = [
            "(", ")", "[", "]", " ", ", ", "; ", "\n", "\r\n", "see ", "from ", "and ", "line ", "lines ", "Ledger ", "decision ",
            "notes/plan.md:12", "notes/plan.md:12-14", "`notes/plan.md`, line 12", "Home/Lease-Kilimani-flat.md:7",
            "Lease-Kilimani-flat.md:99", decision, "Ledger 20260101-120000-0a1b", "20260101-120000-0a1a",
            "\"notes/x.md\":3", "**a.py:1**", "家賃", "🏠", "👨‍👩‍👧", "é", "\u{301}", "KES 45,000", "-", "–", "*", "`", "'",
        ]
        let places = [
            "notes/plan.md:12", "Home/Lease-Kilimani-flat.md:7", "Ledger 20260101-120000-0a1a", "Ledger 20260101-120000-0a1b",
            "20260101-120000-0aaa", "Ledger \(decision)", "`notes/plan.md`, line 12", "notes/x.md:3-9",
        ]
        let between = [", ", "; ", " and ", " ", " see ", ",", " (", ") ", "[", "]"]
        let brackets = [("(", ")"), ("[", "]"), ("(", ""), ("", ")"), ("(see ", ")"), ("(from ", ")")]
        func any<T>(_ items: [T]) -> T { items.randomElement(using: &generator)! }
        for round in 0..<800 {
            let answer: String
            if round.isMultiple(of: 2) {
                answer = (0..<Int.random(in: 0...24, using: &generator)).map { _ in any(pieces) }.joined()
            } else {
                // Brackets holding several places, the shape that used to throw.
                answer = (0..<Int.random(in: 1...4, using: &generator)).map { _ in
                    let (open, close) = any(brackets)
                    let inside = (0..<Int.random(in: 1...4, using: &generator)).map { _ in any(places) }.joined(separator: any(between))
                    return any(["", "Rent is KES 45,000 ", "家賃 🏠 ", "👨‍👩‍👧", "\n"]) + open + inside + close + any(["", ".", " ok", "\n"])
                }.joined()
            }
            let checked = Citations.check(answer, shown: [lease], ledger: [decision])
            XCTAssertTrue(Set(checked.ledgerCited).isSubset(of: [decision]), answer)
            // Each line on its own too, as `camr chat` streams it.
            for line in answer.split(separator: "\n", omittingEmptySubsequences: false) {
                XCTAssertTrue(Set(Citations.check(String(line), shown: [lease], ledger: [decision]).ledgerCited).isSubset(of: [decision]))
            }
        }
    }
}

/// A small fixed-seed generator (SplitMix64), so a fuzz failure can be replayed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
