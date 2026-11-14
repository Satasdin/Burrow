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
