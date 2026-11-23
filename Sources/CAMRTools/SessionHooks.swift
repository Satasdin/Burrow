import CAMRCore
import Foundation

/// The hook events that manage a live session's context (D-116, D-117), for Claude Code and for Codex, which sends the
/// same events. They keep what they keep in CAMR's own folder, so they work wherever the session runs.
public enum SessionHooks {
    /// Where everything lives; tests point it elsewhere.
    public struct Places: Sendable {
        public var state: URL
        public var settings: SessionSettings
        public var archive: SessionArchive
        public var kept: KeptStore { KeptStore(folder: state.appendingPathComponent("kept", isDirectory: true)) }
        public var meter: SessionMeter { SessionMeter(folder: state.appendingPathComponent("meter", isDirectory: true)) }

        public init(state: URL = CAMRPlaces.stateFolder) {
            self.state = state
            settings = SessionSettings.load(from: state)
            archive = SessionArchive.standard(settings: settings, state: state)
        }
    }

    static func program(of event: [String: Any]) -> SessionText.Program {
        let path = event["transcript_path"] as? String ?? ""
        return path.contains("/.codex/") || path.contains("rollout-") ? .codex : .claudeCode
    }

    static func read(_ event: [String: Any]) -> (text: String, session: SessionText)? {
        guard let path = event["transcript_path"] as? String, let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let id = event["session_id"] as? String ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return (text, program(of: event) == .codex ? SessionText.codex(text, id: id) : SessionText.claudeCode(text, id: id))
    }

    /// The reply for an event this handles completely ("" when it has nothing to say), or nil to let the vault's hooks run.
    /// PreCompact, SessionEnd and Stop are also archived here, and then left to the vault's hooks.
    public static func handle(_ event: [String: Any], places: Places = Places(), now: Date = Date()) -> String? {
        let name = event["hook_event_name"] as? String ?? ""
        let session = event["session_id"] as? String ?? "unknown"
        switch name {
        case "PostToolUse":
            guard let outcome = Lean.shorten(event: event, settings: places.settings, store: places.kept, now: now) else { return "" }
            places.meter.record(outcome.event, session: session)
            return outcome.reply
        case "UserPromptSubmit":
            archive(event, places: places, every: 600, now: now)
            guard places.settings.recall, let prompt = event["prompt"] as? String, let live = read(event) else { return "" }
            guard let found = AutoRecall.handBack(prompt: prompt, session: live.session, kept: places.kept, sessionID: session) else { return "" }
            places.meter.record(MeterEvent(at: now, kind: .recalled, tool: name, original: 0, shown: found.characters,
                                           label: String(prompt.prefix(80))), session: session)
            return AutoRecall.reply(found.text)
        case "PostCompact":
            let summary = event["compact_summary"] as? String ?? ""
            places.meter.record(MeterEvent(at: now, kind: .compacted, tool: name, original: 0, shown: summary.count,
                                           label: event["trigger"] as? String), session: session)
            return ""
        case "PreCompact", "SessionEnd", "Stop":
            archive(event, places: places, every: name == "Stop" ? 600 : 0, now: now)
            return nil
        default:
            return nil
        }
    }

    /// Keeps the session in the archive; with `every`, only when it was last kept longer ago than that many seconds.
    static func archive(_ event: [String: Any], places: Places, every: TimeInterval, now: Date) {
        guard places.settings.archive, let path = event["transcript_path"] as? String else { return }
        let program = program(of: event)
        if every > 0, let id = event["session_id"] as? String, let known = places.archive.meta(program, id),
           now.timeIntervalSince(known.archivedAt) < every { return }
        if let meta = try? places.archive.keep(path: path, program: program) {
            places.meter.record(MeterEvent(at: now, kind: .archived, tool: event["hook_event_name"] as? String ?? "", original: meta.sourceBytes,
                                           shown: meta.archivedBytes, label: meta.name), session: meta.id)
        }
    }

    /// What PreCompact prints: the summary's instructions. Empty when steering is off.
    public static func steer(_ event: [String: Any], fold: String?, transcript: String? = nil, places: Places = Places(), now: Date = Date()) -> String {
        guard places.settings.steer else { return "" }
        let session = event["session_id"] as? String ?? "unknown"
        let text = transcript ?? (event["transcript_path"] as? String).flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? ""
        let live = program(of: event) == .codex ? SessionText.codex(text, id: session) : SessionText.claudeCode(text, id: session)
        let said = CompactSteer.instructions(session: live, kept: places.kept.entries(session: session), fold: fold)
        places.meter.record(MeterEvent(at: now, kind: .steered, tool: "PreCompact", original: 0, shown: said.count, label: event["trigger"] as? String), session: session)
        return said
    }

    /// On a resume whose cache has expired and whose context is large: what resuming will cost, and the lighter way back.
    /// Claude Code gives the hook the session's size and an estimate of the cache write (D-117).
    public static func resumeAdvice(_ event: [String: Any], places: Places = Places(), now: Date = Date()) -> String? {
        guard ["resume", "fork"].contains(event["source"] as? String ?? ""), event["prompt_cache_likely_expired"] as? Bool == true,
              let tokens = event["context_tokens"] as? Int, tokens >= 40_000 else { return nil }
        let session = event["session_id"] as? String ?? ""
        let cost = (event["estimated_cache_write_usd"] as? Double).map { String(format: " (about $%.2f)", $0) } ?? ""
        places.meter.record(MeterEvent(at: now, kind: .resumed, tool: "SessionStart", original: tokens, shown: 0, label: "cache expired"), session: session)
        return "CAMR: this session holds \(tokens.formatted()) tokens and its prompt cache has expired, so the first reply rewrites all of it\(cost). "
            + "For a lighter start, type /clear, then /camr-resume \(session.prefix(8)): CAMR hands back the requests, decisions, plan and where it stopped in a few thousand tokens, and the rest on request."
    }

    /// Whether a resumed session still has the Ledger's head in its context: it was handed over at a start since the last
    /// compaction. Handing it over again on every resume piled up copies: in the first proof run each message resumed
    /// the session, and 23 copies of the head were in its context by the end (D-116).
    public static func stillHasHead(transcript text: String) -> Bool {
        let after = text.range(of: "\"compact_boundary\"", options: .backwards).map { String(text[$0.upperBound...]) } ?? text
        return after.contains("This comes from CAMR's Ledger")
    }

    /// A SessionStart reply with a message for the person added.
    public static func merge(advice: String?, into reply: String?) -> String {
        var root: [String: Any] = [:]
        if let reply, let data = reply.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { root = object }
        if let advice { root["systemMessage"] = advice }
        guard !root.isEmpty else { return reply ?? "" }
        return String(data: (try? JSONSerialization.data(withJSONObject: root, options: [.withoutEscapingSlashes])) ?? Data(), encoding: .utf8) ?? ""
    }
}
