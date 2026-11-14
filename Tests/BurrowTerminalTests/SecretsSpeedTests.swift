@testable import BurrowTools
import XCTest

/// D-106: taking secrets out of a line never takes long, however long or strange the line, because the name patterns are
/// bounded and callers clip before taking secrets out. The hook has seconds, not minutes.
final class SecretsSpeedTests: XCTestCase {
    private func timed(_ text: String) -> (String, TimeInterval) {
        let start = Date()
        let out = Secrets.redacted(text)
        return (out, Date().timeIntervalSince(start))
    }

    func testALongIdentifierLikeLineIsQuick() {
        let line = String(repeating: "a_b.c-", count: 20_000) + "=x"
        let (_, took) = timed(line)
        XCTAssertLessThan(took, 2.0, "took \(took) s")
    }

    func testALongLineFullOfSecretWordsIsQuick() {
        let line = (0..<5_000).map { "token\($0)secret_KEY" }.joined(separator: "_") + ": value12345678"
        let (_, took) = timed(line)
        XCTAssertLessThan(took, 2.0, "took \(took) s")
    }

    func testSecretsAreStillTakenOut() {
        XCTAssertEqual(Secrets.redacted("OPENAI_API_KEY=sk-test-abcdefghijklmnopqrstuv python3 x.py"), "OPENAI_API_KEY=[secret removed] python3 x.py")
        XCTAssertEqual(Secrets.redacted("Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123"), "Authorization: Bearer [secret removed]")
        XCTAssertEqual(Secrets.redacted("max_tokens=4096"), "max_tokens=4096")
    }
}

/// D-106, after review: nothing is skipped for being long, a long name still matches, and a cut never leaves half a secret.
final class SecretsNoBypassTests: XCTestCase {
    func testASecretOnAVeryLongLineIsStillTakenOut() {
        let filler = String(repeating: "word ", count: 2_000)
        let line = filler + "DB_PASSWORD=hunter2hunter2 " + filler + "export API_TOKEN=\"abc def ghi\" end"
        let out = Secrets.redacted(line)
        XCTAssertFalse(out.contains("hunter2hunter2"))
        XCTAssertFalse(out.contains("abc def ghi"))
        XCTAssertTrue(out.contains("DB_PASSWORD=[secret removed]"))
        XCTAssertEqual(out.count(of: "word"), 4_000, "the rest of the line stays word for word")
    }

    func testAVeryLongNameBeforeTheKeyStillMatches() {
        let name = String(repeating: "SERVICE_", count: 20) + "API_KEY"
        XCTAssertEqual(Secrets.redacted("\(name)=supersecretvalue1"), "\(name)=[secret removed]")
    }

    func testAHugeUnbrokenStretchWithASecretWordIsReplacedWhole() {
        let blob = String(repeating: "x", count: 3_000) + "token=" + String(repeating: "y", count: 3_000)
        let out = Secrets.redacted("before " + blob + " after")
        XCTAssertFalse(out.contains("yyyy"))
        XCTAssertTrue(out.hasPrefix("before ") && out.hasSuffix(" after"))
    }

    func testCuttingNeverLeavesHalfASecret() {
        // A secret that straddles the kept length is taken out whole before anything is clipped.
        let text = String(repeating: "a ", count: 495) + "sk-test-" + String(repeating: "Z", count: 40) + " tail"
        let kept = String(Secrets.redacted(Secrets.cutForRedaction(text, 1_000)).prefix(1_000))
        XCTAssertFalse(kept.contains("sk-test"))
        XCTAssertFalse(kept.contains("ZZZZ"))
        XCTAssertTrue(kept.contains("[secret"), "the marker starts where the secret was")
    }

    func testAnUnmatchedQuoteBeforeALongQuotedSecretDoesNotHideIt() {
        let line = "echo \"it's fine " + String(repeating: "pad ", count: 800) + "API_TOKEN=\"" + String(repeating: "s3cr3t ", count: 400) + "\" done"
        let out = Secrets.redacted(line)
        XCTAssertFalse(out.contains("s3cr3t"))
        XCTAssertTrue(out.hasSuffix(" done"))
    }

    func testAQuotedValueThatNeverClosesGoesToTheEndOfTheLine() {
        let out = Secrets.redacted("DB_PASSWORD=\"open secret value\nnext line")
        XCTAssertEqual(out, "DB_PASSWORD=[secret removed]\nnext line")
    }

    func testTabsAndLineBreaksAroundTheSignStillMatch() {
        XCTAssertEqual(Secrets.redacted("API_KEY\t=\tabcdef123456"), "API_KEY\t=\t[secret removed]")
        XCTAssertEqual(Secrets.redacted("\"client_secret\":\n  \"abcdefgh12345\""), "\"client_secret\":\n  [secret removed]")
    }

    func testWhatIsNotASecretStaysAsPrinted() {
        for line in ["max_tokens=4096", "InvalidTokenError: token expired", "Invalid token: expired", "tokenizer=bpe", "monkey=banana42",
                     "export KEY=$HOME", "port: 8080"] {
            XCTAssertEqual(Secrets.redacted(line), line)
        }
    }
}

private extension String {
    func count(of word: String) -> Int { components(separatedBy: word).count - 1 }
}
