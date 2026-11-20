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

    func testNestedNamesInsideAValueLeaveNothingBehind() {
        let out = Secrets.redacted("A_TOKEN=\"outer B_KEY=inner-secret-1 tail\" C_SECRET=another-secret-2 end")
        XCTAssertFalse(out.contains("inner-secret-1"))
        XCTAssertFalse(out.contains("another-secret-2"))
        XCTAssertFalse(out.contains("outer"))
        XCTAssertTrue(out.hasSuffix(" end"))
    }

    /// D-123: what D-106 guards against is backtracking, which grows faster than the line. So the main check is how the
    /// time grows, which does not depend on the machine: doubling the line about doubles the time (backtracking gives 4x
    /// or worse). Then an absolute ceiling keeps it "seconds, not minutes", with room for a slower hosted runner, where a
    /// flat 2 s failed at 2.02 s (run 44270777591) while a Mac takes 0.8 s.
    func testManyNamesOnOneLongLineStayQuick() {
        func line(_ n: Int) -> String {
            String(repeating: "key=", count: 25_000 * n) + " " + String(repeating: "token: \"", count: 10_000 * n)
        }
        let half = line(1), full = line(2)
        var out = ""
        let tookHalf = cpuSeconds { _ = Secrets.redacted(half) }
        let tookFull = cpuSeconds { out = Secrets.redacted(full) }
        XCTAssertLessThan(tookFull / tookHalf, 3.0, "doubling the line took \(tookHalf) s to \(tookFull) s")
        let ceiling = ProcessInfo.processInfo.environment["CI"] == nil ? 2.0 : 6.0
        XCTAssertLessThan(tookFull, ceiling, "the full line took \(tookFull) s")
        XCTAssertFalse(out.isEmpty)
    }

    func testANameRightAfterAnotherNamesSignIsStillChecked() {
        let out = Secrets.redacted("A_TOKEN=B_KEY=\"inner secret value\" after")
        XCTAssertFalse(out.contains("inner secret value"))
        XCTAssertTrue(out.hasSuffix(" after"))
    }

    func testALoneCarriageReturnDoesNotEndAnUnclosedValue() {
        let out = Secrets.redacted("API_TOKEN=\"part-one\rpart-two-secret\nnext")
        XCTAssertFalse(out.contains("part-two-secret"))
        XCTAssertEqual(out, "API_TOKEN=[secret removed]\nnext")
        XCTAssertEqual(Secrets.redacted("API_TOKEN=\"abc def\r\nnext"), "API_TOKEN=[secret removed]\r\nnext")
    }

    func testAFlagMatchesOnlyWhenItStartsItsOwnWord() {
        XCTAssertEqual(Secrets.redacted("mysql --password hunter2 -h db"), "mysql --password [secret removed] -h db")
        XCTAssertEqual(Secrets.redacted("ran part-two-secret\nnext step"), "ran part-two-secret\nnext step")
        XCTAssertEqual(Secrets.redacted("run --db-password hunter2 now"), "run --db-password [secret removed] now")
        XCTAssertEqual(Secrets.redacted("vault login --vault-token=s.abcdef123"), "vault login --vault-token=[secret removed]")
        XCTAssertEqual(Secrets.redacted("-token abcdef"), "-token [secret removed]")
    }

    func testWhatIsNotASecretStaysAsPrinted() {
        for line in ["max_tokens=4096", "InvalidTokenError: token expired", "Invalid token: expired", "tokenizer=bpe", "monkey=banana42",
                     "export KEY=$HOME", "port: 8080"] {
            XCTAssertEqual(Secrets.redacted(line), line)
        }
    }
}

/// CPU seconds this thread spent on `work`, the best of `runs`: other jobs on a shared runner do not count against it.
private func cpuSeconds(runs: Int = 2, _ work: () -> Void) -> Double {
    (0..<runs).map { _ -> Double in
        let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        work()
        return Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1e9
    }.min()!
}

private extension String {
    func count(of word: String) -> Int { components(separatedBy: word).count - 1 }
}
