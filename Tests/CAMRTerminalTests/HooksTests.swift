import CAMRCore
import Foundation
import Testing
@testable import CAMRTools

@Suite struct HooksTests {
    let vaultRoot = URL(fileURLWithPath: "/tmp/vault")
    let linked = [LinkedFolder(name: "camr", path: "/Users/me/Developer/camr")]

    @Test func aLinkedFolderIsItsOwnBranch() throws {
        let place = try #require(Hooks.place(for: URL(fileURLWithPath: "/Users/me/Developer/camr/app"), vaultRoot: vaultRoot, linked: linked))
        #expect(place.branch == "camr")
        #expect(place.vaultPath("/Users/me/Developer/camr/app/Sources/App.swift") == "camr/app/Sources/App.swift")
        #expect(place.vaultPath("/Users/me/elsewhere/x.swift") == nil)
        #expect(Hooks.place(for: URL(fileURLWithPath: "/Users/me/elsewhere"), vaultRoot: vaultRoot, linked: linked) == nil)
        #expect(Hooks.place(for: URL(fileURLWithPath: "/tmp/vault/Notes"), vaultRoot: vaultRoot, linked: linked)?.branch == "main")
    }

    @Test func theTranscriptGivesRequestsEditsPlanAndModel() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"Add the shelf limit"}}"#,
            #"{"type":"user","isMeta":true,"message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","model":"claude-opus-5-5","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/Users/me/Developer/camr/Sources/KV.swift"}},{"type":"tool_use","name":"TodoWrite","input":{"todos":[{"content":"Limit to 12 GB","status":"completed"},{"content":"Show it in the app","status":"in_progress"}]}}]}}"#,
            "not json",
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Now the app"}]}}"#,
        ].joined(separator: "\n")
        let found = Hooks.readTranscript(lines)
        #expect(found.asked == ["Add the shelf limit", "Now the app"])
        #expect(found.edited == ["/Users/me/Developer/camr/Sources/KV.swift"])
        #expect(found.openTodos == ["Show it in the app"])
        #expect(found.doneTodos == ["Limit to 12 GB"])
        #expect(found.model == "claude-opus-5-5")
    }

    @Test func aCheckpointKeepsThePlanAndWhereItStopped() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hooks-\(UUID().uuidString)")
        let ledger = Ledger(folder: folder, read: { _ in "text" })
        let place = try #require(Hooks.place(for: URL(fileURLWithPath: "/Users/me/Developer/camr"), vaultRoot: vaultRoot, linked: linked))
        var transcript = Hooks.Transcript()
        transcript.asked = ["Add the shelf limit"]
        transcript.edited = ["/Users/me/Developer/camr/Sources/KV.swift", "/Users/me/other.txt"]
        transcript.openTodos = ["Show it in the app"]
        transcript.model = "claude-opus-5-5"
        let made = try Hooks.checkpoint(ledger: ledger, place: place, transcript: transcript, session: "abc", event: "PreCompact")
        #expect(made.map(\.kind) == [.plan, .handoff])
        #expect(made[1].message.hasPrefix("Claude Code stopped before compacting"))
        #expect(made[1].cites.keys.sorted() == ["camr/Sources/KV.swift"])
        #expect(made[1].body.contains("Outside the vault: 1 file"))
        // The same plan again is not repeated.
        let again = try Hooks.checkpoint(ledger: ledger, place: place, transcript: transcript, session: "abc", event: "SessionEnd")
        #expect(again.map(\.kind) == [.handoff])
        #expect(try Hooks.checkpoint(ledger: ledger, place: place, transcript: Hooks.Transcript(), session: "x", event: "SessionEnd").isEmpty)
        // When CAMR's MCP connection has just written this session's handoff as it closed, the end hook does not write a second (D-70).
        try ledger.commit(.handoff, "claude-code stopped after 1 lookup. Last: shelf", author: "claude-opus-5-5", client: "claude-code", session: "20261112-184151-002a")
        #expect(try Hooks.checkpoint(ledger: ledger, place: place, transcript: transcript, session: "abc", event: "SessionEnd").isEmpty)
        #expect(try Hooks.checkpoint(ledger: ledger, place: place, transcript: transcript, session: "abc", event: "PreCompact").map(\.kind) == [.handoff])
        let start = Hooks.sessionStart(ledger: ledger, place: place)
        #expect(start.contains("\"hookEventName\":\"SessionStart\""))
        #expect(start.contains("Show it in the app"))
    }

    @Test func aGitCommitIsLinkedOnce() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("hooks-\(UUID().uuidString)")
        let ledger = Ledger(folder: folder, read: { _ in "text" })
        let place = Hooks.Place(branch: "camr", root: URL(fileURLWithPath: "/Users/me/Developer/camr"), prefix: "camr")
        let made = try #require(try Hooks.gitCommit(ledger: ledger, place: place, sha: "abcdef1234567", subject: "Shelf limit",
                                                     files: ["/Users/me/Developer/camr/Sources/KV.swift"]))
        #expect(made.kind == .code)
        #expect(made.message == "abcdef1234 Shelf limit")
        #expect(made.cites.keys.sorted() == ["camr/Sources/KV.swift"])
        #expect(try Hooks.gitCommit(ledger: ledger, place: place, sha: "abcdef1234567", subject: "Shelf limit", files: []) == nil)
    }
}
