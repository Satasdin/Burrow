import CAMRCore
import CAMRTools
import Foundation

let sessionUsage = """
Sessions, kept whole so any program can resume them (D-116, D-117):
  camr session                                   the latest archived sessions
  camr session sync                              keep every Claude Code and Codex session still on this Mac
  camr session resume <name|id>                  the resume pack: requests word for word, decisions, plan, where it stopped
  camr session find <name|id> "words"            the exact messages of that session that match
  camr session timeline <name|id>                one line per request
  camr session meter [id]                        what CAMR did in a live session: outputs kept, recalls, compactions
  camr session allow <name|id> <program>         let another program read that session's exact messages (in your own terminal, typing yes)
  camr session settings [key value]              lean-bash, lean-read, lean-grep, recall, steer, archive on|off; lean-characters N; archive-folder PATH
  camr expand <handle> [--lines A-B] [--find words]   part of a tool output CAMR kept whole
"""

func runSessionCommand(_ arguments: [String]) throws -> Bool {
    guard let command = arguments.first, ["session", "expand"].contains(command) else { return false }
    let words = Array(arguments.dropFirst())
    var values: [String: String] = [:]
    var positional: [String] = []
    var index = 0
    while index < words.count {
        if ["--lines", "--find"].contains(words[index]), index + 1 < words.count { values[words[index]] = words[index + 1]; index += 2 }
        else { positional.append(words[index]); index += 1 }
    }
    if command == "expand" {
        guard let handle = positional.first else { throw Failure("expand needs a handle: camr expand k3f2a91 [--lines 200-260] [--find words]") }
        let result = SessionTools.expand(handle: handle, lines: values["--lines"], find: values["--find"], reader: nil)
        print(result.text)
        return true
    }
    let places = SessionHooks.Places()
    switch positional.first ?? "list" {
    case "list":
        print(SessionTools.session(nil, find: nil, timeline: nil, ref: nil, client: nil, places: places).text)
    case "sync":
        let started = Date()
        let report = places.archive.sync { done in if done % 50 == 0 { logToStandardError("  \(done) transcripts read") } }
        print("Kept \(report.kept) new or changed sessions (\(ByteSize.format(report.bytes)) compressed), \(report.unchanged) unchanged, \(report.skipped) skipped (empty, or Codex copies of Claude Code sessions), \(report.failed) failed, in \(String(format: "%.1f", Date().timeIntervalSince(started))) s.")
        print("The archive is \(places.archive.folder.path), \(ByteSize.format(places.archive.size())) in all.")
    case "resume", "find", "timeline":
        guard positional.count >= 2 else { throw Failure("\(positional[0]) needs a session: its id, first 8 characters, or words from its name") }
        let name = positional[1]
        let find = positional[0] == "find" ? (positional.count >= 3 ? positional[2...].joined(separator: " ") : nil) : nil
        if positional[0] == "find", find == nil { throw Failure("find needs words to look for") }
        let result = SessionTools.session(name, find: find, timeline: positional[0] == "timeline" ? "yes" : nil, ref: nil, client: nil, places: places)
        print(result.text)
    case "meter":
        let id = positional.count >= 2 ? positional[1] : places.meter.sessions().first?.id
        guard let id else { print("No session has used CAMR's session hooks yet."); return true }
        let events = places.meter.events(session: id)
        print(SessionReport.text(events, session: id))
    case "allow":
        guard positional.count >= 3 else { throw Failure("allow needs a session and a program: camr session allow <id> codex|claude-code") }
        let found = places.archive.find(positional[1])
        guard found.count == 1, let meta = found.first else { throw Failure("\(found.count) sessions match \(positional[1]); give its id") }
        let program = positional[2].lowercased().contains("codex") ? "codex" : positional[2].lowercased().contains("claude") ? "claude-code" : positional[2].lowercased()
        try askThePerson(["Let \(program) read the exact messages of session \(meta.id.prefix(8)) (\(meta.program.rawValue)): \"\(meta.name)\"?",
                          "It already gets the resume pack, with secrets taken out. This adds every message and tool output, by search or by ref."],
                         refusal: "only you can widen who reads a session: run this in your own terminal and type yes.")
        try SessionApprovals().allow(session: meta.id, program: program)
        print("\(program) may now read session \(meta.id.prefix(8)) in full.")
    case "settings":
        var settings = SessionSettings.load()
        if positional.count >= 3 {
            let key = positional[1], value = positional[2]
            let on = ["on", "yes", "true", "1"].contains(value.lowercased())
            switch key {
            case "lean-bash": settings.leanBash = on
            case "lean-read": settings.leanRead = on
            case "lean-grep": settings.leanGrep = on
            case "recall": settings.recall = on
            case "steer": settings.steer = on
            case "archive": settings.archive = on
            case "lean-characters": settings.leanCharacters = max(1_000, Int(value) ?? settings.leanCharacters)
            case "lean-read-lines": settings.leanReadLines = max(200, Int(value) ?? settings.leanReadLines)
            case "archive-folder": settings.archiveFolder = ["default", "none", ""].contains(value) ? nil : (value as NSString).expandingTildeInPath
            default: throw Failure("unknown setting \(key)")
            }
            try settings.save()
        }
        let data = (try? JSONEncoder.pretty.encode(settings)) ?? Data()
        print(String(decoding: data, as: UTF8.self))
        print("Archive: \(SessionArchive.standard(settings: settings).folder.path)")
        if let chosen = SessionArchive.chosenFolder(settings), let drive = SessionArchive.missingDrive(chosen) {
            print("The drive \(drive) is not connected, so sessions are kept in CAMR's own folder until it is.")
        }
    default:
        throw Failure(sessionUsage)
    }
    return true
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
