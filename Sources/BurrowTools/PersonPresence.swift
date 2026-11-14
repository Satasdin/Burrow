import BurrowCore
import Darwin
import Foundation

/// Is the person on this Mac the one asking, or a program they connected to Burrow (D-113)?
///
/// Every step only the person may take (approving a linked folder, joining a team, publishing a share, confirming,
/// clearing or overriding a decision's check) used to trust two things: stdin and stderr are terminals, and the answer
/// was "yes". A connected agent with a shell can make a pseudo-terminal (`script`, `expect`, a Python pty) and type yes.
/// This adds the layers in front of that typed yes:
///   1. never from an agent's environment: the variables each agent sets for the commands it runs;
///   2. never from an agent's process tree: burrow's own parents, its session leader's and its terminal's;
///   3. for the steps that defeat the gate, a one-time code shown only in a notification and checked only
///      in the memory of the burrow process that made it (`PersonCode`).
/// An agent that already runs arbitrary code as the person can in principle strip its environment and detach from its
/// tree; layers 1 and 2 stop the ordinary path, and layer 3 stops even that for what defeats the gate.
public enum PersonPresence {
    /// Why burrow decided the person is not the one asking.
    public struct Refusal: Error, Equatable, CustomStringConvertible, Sendable {
        public let reason: String
        public var description: String { reason }
    }

    // MARK: Layer 1: the agent's environment

    /// The variables each program sets in the environment of the commands it runs for its model. Found by running each
    /// one on this Mac (14-15 November 2026) and dumping what its shell tool's child saw, except Gemini CLI and Cursor's
    /// agent, which are not installed here and are named from their documentation. Whole prefixes (CLAUDE_CODE_*,
    /// HERMES_*, OPENCODE_*) are not used: people export CLAUDE_CODE_USE_BEDROCK or HERMES_HOME in their own shell
    /// profile, and refusing them in their own terminal would teach them to work around this.
    public static let markers: [String: String] = [
        // Claude Code 2.1.321 (its Bash tool, CLI and desktop).
        "CLAUDECODE": "Claude Code", "CLAUDE_CODE_SESSION_ID": "Claude Code", "CLAUDE_CODE_CHILD_SESSION": "Claude Code",
        "CLAUDE_CODE_SESSION_ATTENDED": "Claude Code", "CLAUDE_CODE_ENTRYPOINT": "Claude Code", "CLAUDE_PID": "Claude Code",
        // Set by Claude Code, OpenCode and Hermes when not already set: it names the outermost agent.
        "AI_AGENT": "an AI agent",
        // OpenCode 2.2.7.
        "OPENCODE": "OpenCode", "OPENCODE_SESSION_ID": "OpenCode", "OPENCODE_TERMINAL": "OpenCode",
        // Codex CLI 0.146.0; the sandbox ones only inside its sandbox.
        "CODEX_THREAD_ID": "Codex", "CODEX_CI": "Codex", "CODEX_SANDBOX": "Codex", "CODEX_SANDBOX_NETWORK_DISABLED": "Codex",
        // OpenClaw 2026.11.3.
        "OPENCLAW_SHELL": "OpenClaw", "OPENCLAW_CLI": "OpenClaw", "OPENCLAW_SUBAGENT_EXEC": "OpenClaw",
        // Hermes Agent v0.23.1.
        "HERMES_AGENT": "Hermes", "HERMES_SESSION_ID": "Hermes", "HERMES_SESSION_KEY": "Hermes", "HERMES_SESSION_PLATFORM": "Hermes",
        "_HERMES_GATEWAY": "Hermes", "HERMES_EXEC_ASK": "Hermes",
        // Not installed here: from their documentation.
        "GEMINI_CLI": "Gemini CLI", "CURSOR_AGENT": "Cursor's agent",
        // Burrow's own: set by `burrow mcp` for anything it starts, and for every decision check a gate runs, since a
        // check runs the very code a program just changed.
        mcpMarker: "burrow mcp", checkMarker: "a decision check Burrow is running",
    ]
    public static let mcpMarker = "BURROW_MCP"
    public static let checkMarker = "BURROW_CHECK_RUN"

    /// The first agent variable present, by name, whatever its value (an empty one is still set on purpose).
    public static func environmentRefusal(_ environment: [String: String]) -> Refusal? {
        // The one that names the nearest agent first; AI_AGENT names the outermost one, so it comes last.
        let order = markers.keys.filter { $0 != "AI_AGENT" }.sorted() + ["AI_AGENT"]
        guard let name = order.first(where: { environment[$0] != nil }) else { return nil }
        return Refusal(reason: "it was run from inside \(markers[name]!) (\(name) is set)")
    }

    // MARK: Layer 2: the agent's process tree

    /// What burrow can see of one process on this Mac.
    public struct ProcessFacts: Equatable, Sendable {
        public var pid: pid_t
        public var parent: pid_t
        /// The kernel's short name (16 characters at most).
        public var name: String
        /// The executable's full path, when it can be read.
        public var path: String
        /// Its arguments, argv[0] first, when they can be read (a program can rewrite them, as Node's process.title does).
        public var arguments: [String]

        public init(pid: pid_t, parent: pid_t, name: String, path: String = "", arguments: [String] = []) {
            self.pid = pid; self.parent = parent; self.name = name; self.path = path; self.arguments = arguments
        }
    }

    /// Programs that are agents themselves, by executable name.
    static let agentNames: [String: String] = [
        "claude": "Claude Code", "Claude": "the Claude app", "opencode": "OpenCode", "codex": "Codex", "cursor-agent": "Cursor's agent",
        "gemini": "Gemini CLI", "openclaw": "OpenClaw", "hermes": "Hermes",
    ]
    /// Words that, in an interpreter's arguments (node, bun, python), mean it is running an agent.
    static let agentWords: [String: String] = [
        "claude-code": "Claude Code", "opencode": "OpenCode", "opencode-ai": "OpenCode", "codex": "Codex", "cursor-agent": "Cursor's agent",
        "gemini": "Gemini CLI", "gemini-cli": "Gemini CLI", "openclaw": "OpenClaw", "hermes": "Hermes", "hermes_cli": "Hermes",
    ]
    static let interpreters = ["node", "bun", "deno", "python", "Python"]

    /// The agent a process is, or nil. burrow itself counts when it serves programs (`burrow mcp`), runs a gate whose
    /// decision checks run the code a program changed (`burrow check`), or answers a program's hook (`burrow hook`).
    public static func agent(_ process: ProcessFacts) -> String? {
        let argv0 = process.arguments.first.map { ($0 as NSString).lastPathComponent } ?? ""
        let file = (process.path as NSString).lastPathComponent
        for name in [process.name, argv0, file] where !name.isEmpty {
            if let agent = agentNames[name] { return agent }
        }
        // Claude Code's native build runs from a file named for its version, kept in a folder named for it.
        if process.path.contains("/claude/versions/") || process.path.contains("/claude-code/") { return "Claude Code" }
        if [process.name, file].contains("burrow"), process.arguments.count > 1, ["mcp", "check", "hook"].contains(process.arguments[1]) {
            return "burrow \(process.arguments[1])"
        }
        if interpreters.contains(where: { process.name.hasPrefix($0) || file.hasPrefix($0) }) || agentWords[argv0] != nil {
            for argument in process.arguments {
                for word in argument.split(whereSeparator: { "/. :=".contains($0) }) {
                    if let agent = agentWords[String(word)] { return agent }
                }
            }
        }
        return nil
    }

    /// One process, read with sysctl and libproc. Nil when it has gone or can't be read.
    public static func facts(_ pid: pid_t) -> ProcessFacts? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&query, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let path = pathLength > 0 ? String(cString: pathBuffer) : ""
        return ProcessFacts(pid: pid, parent: info.kp_eproc.e_ppid, name: name, path: path, arguments: arguments(pid))
    }

    /// A process's arguments from KERN_PROCARGS2: argc, the executable path, then argv. Empty when it can't be read.
    static func arguments(_ pid: pid_t) -> [String] {
        var query: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&query, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&query, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let count = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }   // the executable path
        while index < size, buffer[index] == 0 { index += 1 }   // its padding
        var out: [String] = []
        while out.count < count, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            out.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return out
    }

    /// A process and its parents up to launchd. `complete` is false when one in between could not be read.
    public static func lineage(from pid: pid_t, read: (pid_t) -> ProcessFacts? = facts) -> (chain: [ProcessFacts], complete: Bool) {
        var chain: [ProcessFacts] = []
        var next = pid
        var seen = Set<pid_t>()
        while next > 1, chain.count < 128, seen.insert(next).inserted {
            guard let process = read(next) else { return (chain, false) }
            chain.append(process)
            next = process.parent
        }
        return (chain, true)
    }

    /// Layer 2: burrow's parents, its session's leader and the leader of the session that owns its terminal, each with
    /// their own parents. Refuses when any is an agent, and when burrow's own parents can't be read (fails closed).
    public static func processRefusal(read: (pid_t) -> ProcessFacts? = facts) -> Refusal? {
        let own = lineage(from: getppid(), read: read)
        if let found = own.chain.first(where: { agent($0) != nil }) {
            return Refusal(reason: "it was started by \(agent(found)!) (\(describe(found)), process \(found.pid))")
        }
        guard own.complete else { return Refusal(reason: "burrow could not see which program started it") }
        var leaders = Set<pid_t>()
        let session = getsid(0)
        if session > 1 { leaders.insert(session) }
        for descriptor in [STDIN_FILENO, STDERR_FILENO] where isatty(descriptor) == 1 {
            let owner = tcgetsid(descriptor)
            if owner > 1 { leaders.insert(owner) }
        }
        let ownPids = Set(own.chain.map(\.pid) + [getpid()])
        for leader in leaders.sorted() where !ownPids.contains(leader) {
            for found in lineage(from: leader, read: read).chain where agent(found) != nil {
                return Refusal(reason: "its terminal belongs to a session started by \(agent(found)!) (\(describe(found)), process \(found.pid))")
            }
        }
        return nil
    }

    static func describe(_ process: ProcessFacts) -> String {
        let shown = process.arguments.isEmpty ? process.name
            : ([(process.arguments[0] as NSString).lastPathComponent] + process.arguments.dropFirst().prefix(2)).joined(separator: " ")
        return Printable.clean(String(shown.prefix(80)))
    }

    /// Layers 1 and 2 together. Nil means nothing here says a program is asking.
    public static func refusal(environment: [String: String] = ProcessInfo.processInfo.environment) -> Refusal? {
        environmentRefusal(environment) ?? processRefusal()
    }
}

// MARK: Layer 3: a code shown only outside the terminal

/// An eight-digit code for one step that defeats the gate, shown only in a macOS notification: never in the terminal,
/// a file, an argument list, an environment or a message to another process (D-113, and its security review).
///
/// The burrow process that asks for it makes it, shows it, reads what is typed and compares, all in one run and in its
/// own memory (`Challenge`). Nothing written anywhere can check a code: `person-codes.json` in Burrow's own folder keeps
/// only when codes were made, for what, and how they ended, to slow a program that keeps asking for new ones. Any
/// program running as the person can write that file, so verification never reads it, and a missing or unreadable one
/// is taken as "can't tell" (burrow waits longer before making a code), never as an empty history.
public enum PersonCode {
    public static let digits = 8
    public static let lifetime: TimeInterval = 120
    public static let tries = 3
    /// At most this many codes in ten minutes (counted from the file, so this only slows a program down).
    public static let perTenMinutes = 6
    /// Waited before every code is made.
    public static let issueDelay: TimeInterval = 2
    /// Waited instead, when the record of earlier codes is missing or can't be read.
    public static let unknownHistoryDelay: TimeInterval = 20
    static let fileName = "person-codes.json"

    /// One code, held only by the process that made it. Nothing outside this object can check a typed code.
    public final class Challenge: @unchecked Sendable {
        public let id: String
        public let action: String
        public let expires: Date
        let plain: String
        private(set) var wrong = 0
        private(set) var finished = false

        init(id: String, action: String, expires: Date, plain: String) {
            self.id = id; self.action = action; self.expires = expires; self.plain = plain
        }

        /// Compares a typed code with the one made here, in this process's memory.
        public func verify(_ typed: String, now: Date = Date()) -> Outcome {
            guard !finished else { return .spent }
            guard now <= expires else { finished = true; return .expired }
            let answer = typed.filter { !$0.isWhitespace }
            if PersonCode.equalInConstantTime(Data(answer.utf8), Data(plain.utf8)) {
                finished = true
                return .accepted
            }
            wrong += 1
            if wrong >= PersonCode.tries { finished = true; return .spent }
            return .wrong(triesLeft: PersonCode.tries - wrong)
        }

        /// Ends it without a right answer (the input closed).
        public func abandon() { finished = true }
    }

    public enum Outcome: Equatable {
        case accepted
        case wrong(triesLeft: Int)
        case expired
        /// Already used, or ended by wrong tries.
        case spent
    }

    /// What the record keeps of a code: never the code, a hash or salt of it, or anything else that could check one.
    struct Entry: Codable, Equatable {
        var id: String
        var action: String
        var issued: Date
        var expires: Date
        var used: Bool
        var wrong: Int
    }

    /// The record of earlier codes, or nil when it is missing or can't be read.
    static func history(_ state: URL) -> [Entry]? {
        guard let data = try? Data(contentsOf: state.appendingPathComponent(fileName)) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Entry].self, from: data)
    }

    /// Burrow's folder is made 0700 when it is made here; the record is written to a new file created 0600 and then
    /// moved into place, so it is never readable by others, even for a moment.
    static func save(_ entries: [Entry], _ state: URL) throws {
        if !FileManager.default.fileExists(atPath: state.path) {
            try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        let target = state.appendingPathComponent(fileName)
        let temporary = state.appendingPathComponent(".\(fileName).\(getpid()).\(UUID().uuidString)")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        let written = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        close(descriptor)
        guard written == data.count, rename(temporary.path, target.path) == 0 else {
            unlink(temporary.path)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    public struct TooMany: Error, CustomStringConvertible {
        public var description: String { "Burrow has shown \(PersonCode.perTenMinutes) codes in the last ten minutes; wait a few minutes and try again." }
    }

    /// Makes a code for `action`, after waiting `issueDelay` (or `unknownHistoryDelay` when the record of earlier
    /// codes is missing or unreadable), and notes it in the record. `now` and `wait` are there for tests.
    public static func issue(action: String, state: URL, now: () -> Date = Date.init,
                             wait: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) throws -> Challenge {
        let known = history(state)
        wait(known == nil ? unknownHistoryDelay : issueDelay)
        let at = now()
        var entries = (known ?? []).filter { at.timeIntervalSince($0.issued) < 600 }
        guard entries.count < perTenMinutes else { throw TooMany() }
        var generator = SystemRandomNumberGenerator()
        let plain = String((0..<digits).map { _ in Character(String(Int.random(in: 0...9, using: &generator))) })
        let challenge = Challenge(id: UUID().uuidString.lowercased(), action: action, expires: at.addingTimeInterval(lifetime), plain: plain)
        entries.append(Entry(id: challenge.id, action: action, issued: at, expires: challenge.expires, used: false, wrong: 0))
        try save(entries, state)
        return challenge
    }

    /// Notes in the record how a code ended. The record is never read to decide whether a code is right.
    public static func record(_ challenge: Challenge, state: URL) {
        guard var entries = history(state), let index = entries.firstIndex(where: { $0.id == challenge.id }) else { return }
        entries[index].used = challenge.finished
        entries[index].wrong = challenge.wrong
        try? save(entries, state)
    }

    static func equalInConstantTime(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }

    /// Where a code was shown.
    public enum Shown: Equatable, Sendable {
        case notification
        /// Debug and test builds only: written to the file BURROW_TEST_CODE_FILE names.
        case testHook
        case nowhere
    }

    /// Shows the code outside the terminal, as a macOS notification (osascript, given its script on stdin so the code is
    /// never in an argument list a program can read with ps). It is not sent to the Burrow app: the app is ad-hoc
    /// signed, so burrow can't tell it from a program that took its channel first. In debug and test builds only,
    /// BURROW_TEST_CODE_FILE makes it write the code to that file instead; the branch is compiled out of release builds
    /// (`swift build -c release`, the app's bundled burrow), so no variable a program could set reveals the code there.
    public static func show(_ challenge: Challenge, environment: [String: String] = ProcessInfo.processInfo.environment) -> Shown {
        #if DEBUG
        if let file = environment["BURROW_TEST_CODE_FILE"], !file.isEmpty {
            return (try? challenge.plain.write(toFile: file, atomically: true, encoding: .utf8)) != nil ? .testHook : .nowhere
        }
        #endif
        return notify(challenge) ? .notification : .nowhere
    }

    static func appleScriptString(_ text: String) -> String {
        "\"" + Printable.clean(text).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The code as shown: two groups of four, easier to read off a notification.
    static func grouped(_ code: String) -> String { "\(code.prefix(4)) \(code.dropFirst(4))" }

    /// A macOS notification, from osascript (a bare command-line program can't use UserNotifications: that needs an app
    /// bundle). Headless-safe: it needs no window and no Accessibility permission.
    static func notify(_ challenge: Challenge) -> Bool {
        let script = "display notification \(appleScriptString("Type it in your terminal only if you asked for this yourself: \(challenge.action). Never give it to a program or a chat."))"
            + " with title \(appleScriptString("Burrow code \(grouped(challenge.plain))"))"
            + " subtitle \(appleScriptString("Valid for 2 minutes, once"))\n"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-"]
        let feed = Pipe()
        process.standardInput = feed
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        feed.fileHandleForWriting.write(Data(script.utf8))
        try? feed.fileHandleForWriting.close()
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return false }
        return process.terminationStatus == 0
    }
}
