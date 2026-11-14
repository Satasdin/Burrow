import BurrowCore
import CryptoKit
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
///   3. for the steps that defeat the gate, a one-time code shown only outside the terminal (`PersonCode`).
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

/// A six-digit code for one step that defeats the gate: shown in the Burrow app if it is running, else in a macOS
/// notification, never in the terminal, a file, an argument list or an environment. Valid 2 minutes, used once, three
/// wrong tries end it; only its salted hash is kept, in Burrow's own folder (`person-codes.json`) (D-113).
public enum PersonCode {
    public static let lifetime: TimeInterval = 120
    public static let tries = 3
    /// At most this many codes in ten minutes, so a program can't keep asking for codes and guessing.
    public static let perTenMinutes = 6
    static let fileName = "person-codes.json"

    /// A code as the process that asked for it holds it. The plain code stays in this process's memory.
    public struct Issued: Sendable {
        public let id: String
        public let action: String
        public let expires: Date
        let salt: Data
        let digest: Data
        let plain: String
    }

    struct Entry: Codable, Equatable {
        var id: String
        var action: String
        var issued: Date
        var expires: Date
        var salt: String
        var digest: String
        var used: Bool
        var wrong: Int
    }

    static func digest(_ code: String, salt: Data) -> Data { Data(SHA256.hash(data: salt + Data(code.utf8))) }

    static func load(_ state: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: state.appendingPathComponent(fileName)) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Entry].self, from: data)) ?? []
    }

    static func save(_ entries: [Entry], _ state: URL) throws {
        try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = state.appendingPathComponent(fileName)
        try encoder.encode(entries).write(to: url, options: .atomic)
        chmod(url.path, 0o600)
    }

    public struct TooMany: Error, CustomStringConvertible {
        public var description: String { "Burrow has shown \(PersonCode.perTenMinutes) codes in the last ten minutes; wait a few minutes and try again." }
    }

    /// Makes a code for `action` and keeps its salted hash. Old entries (over ten minutes) are dropped.
    public static func issue(action: String, state: URL, now: Date = Date()) throws -> Issued {
        var entries = load(state).filter { now.timeIntervalSince($0.issued) < 600 }
        guard entries.count < perTenMinutes else { throw TooMany() }
        var generator = SystemRandomNumberGenerator()
        let plain = String(format: "%06d", Int.random(in: 0..<1_000_000, using: &generator))
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255, using: &generator) })
        let id = UUID().uuidString.lowercased()
        let issued = Issued(id: id, action: action, expires: now.addingTimeInterval(lifetime), salt: salt, digest: digest(plain, salt: salt), plain: plain)
        entries.append(Entry(id: id, action: action, issued: now, expires: issued.expires, salt: salt.base64EncodedString(),
                             digest: issued.digest.base64EncodedString(), used: false, wrong: 0))
        try save(entries, state)
        return issued
    }

    public enum Outcome: Equatable {
        case accepted
        case wrong(triesLeft: Int)
        case expired
        /// Already used, ended by wrong tries, or no longer on file.
        case spent
    }

    /// Checks a typed code against the one this process holds, and against the record on file: the record can only make
    /// it stricter (taken away or marked used, the code no longer works), never let a different code through.
    public static func redeem(_ typed: String, _ issued: Issued, state: URL, now: Date = Date()) -> Outcome {
        var entries = load(state)
        guard let index = entries.firstIndex(where: { $0.id == issued.id }), !entries[index].used,
              entries[index].digest == issued.digest.base64EncodedString() else { return .spent }
        guard now <= issued.expires, now <= entries[index].expires else {
            entries[index].used = true; try? save(entries, state)
            return .expired
        }
        let answer = typed.filter { !$0.isWhitespace }
        let matches = equalInConstantTime(digest(answer, salt: issued.salt), issued.digest)
        if matches {
            entries[index].used = true
            do { try save(entries, state) } catch { return .spent }
            return .accepted
        }
        entries[index].wrong += 1
        if entries[index].wrong >= tries { entries[index].used = true }
        try? save(entries, state)
        return entries[index].used ? .spent : .wrong(triesLeft: tries - entries[index].wrong)
    }

    /// Ends a code nobody typed (the input closed): marked used on file, so its record says it can't be used.
    public static func spend(_ issued: Issued, state: URL) {
        var entries = load(state)
        guard let index = entries.firstIndex(where: { $0.id == issued.id }) else { return }
        entries[index].used = true
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
        case app
        case notification
        /// Debug and test builds only: written to the file BURROW_TEST_CODE_FILE names.
        case testHook
        case nowhere
    }

    /// Shows the code outside the terminal: in the Burrow app when it is running for this state folder, else as a macOS
    /// notification (osascript, given its script on stdin so the code is never in an argument list a program can read
    /// with ps). In debug and test builds only, BURROW_TEST_CODE_FILE makes it write the code to that file instead; the
    /// branch is compiled out of release builds (`swift build -c release`, the app's bundled burrow), so no variable a
    /// program could set reveals the code there.
    public static func show(_ issued: Issued, state: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> Shown {
        #if DEBUG
        if let file = environment["BURROW_TEST_CODE_FILE"], !file.isEmpty {
            return (try? issued.plain.write(toFile: file, atomically: true, encoding: .utf8)) != nil ? .testHook : .nowhere
        }
        #endif
        if PersonCodeInbox.deliver(issued, state: state) { return .app }
        if notify(issued) { return .notification }
        return .nowhere
    }

    static func appleScriptString(_ text: String) -> String {
        "\"" + Printable.clean(text).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// A macOS notification, from osascript (a bare command-line program can't use UserNotifications: that needs an app
    /// bundle). Headless-safe: it needs no window and no Accessibility permission.
    static func notify(_ issued: Issued) -> Bool {
        let script = "display notification \(appleScriptString("Type it in your terminal only if you asked for this yourself: \(issued.action). Never give it to a program or a chat."))"
            + " with title \(appleScriptString("Burrow code \(issued.plain)"))"
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

/// The Burrow app's side of the code: it listens on a local Mach message port named for its state folder, and a burrow
/// command asking for a code sends it there only while a Burrow.app is running. The app shows it in a small sheet.
public enum PersonCodeInbox {
    /// What the app is sent: the code and what it is for.
    public struct Request: Codable, Equatable, Sendable {
        public var code: String
        public var action: String
        public var expires: Date
    }

    /// One port per state folder, so a burrow run with its own BURROW_STATE_DIR (a test, a demo) never reaches the app
    /// the person has open.
    public static func portName(state: URL) -> String {
        let path = state.standardizedFileURL.resolvingSymlinksInPath().path
        let hash = SHA256.hash(data: Data(path.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "app.burrow.mac.code.\(getuid()).\(hash)"
    }

    nonisolated(unsafe) private static var handler: ((Request) -> Void)?
    nonisolated(unsafe) private static var port: CFMessagePort?

    /// For the app: starts listening on the main run loop. False when the port could not be made (another process holds
    /// the name: then the app says so, and codes come as notifications).
    @discardableResult
    public static func listen(state: URL, show: @escaping (Request) -> Void) -> Bool {
        handler = show
        var shouldFree: DarwinBoolean = false
        guard let local = CFMessagePortCreateLocal(nil, portName(state: state) as CFString, { _, _, data, _ in
            guard let data, let request = try? PersonCodeInbox.decoder.decode(Request.self, from: data as Data),
                  request.code.count == 6, request.code.allSatisfy(\.isNumber) else { return nil }
            DispatchQueue.main.async { PersonCodeInbox.handler?(request) }
            return Unmanaged.passRetained(Data("shown".utf8) as CFData)
        }, nil, &shouldFree) else { return false }
        port = local
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMessagePortCreateRunLoopSource(nil, local, 0), .commonModes)
        return true
    }

    static var decoder: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }

    /// True when a Burrow.app is running on this Mac (its executable is Burrow.app/Contents/MacOS/Burrow).
    public static func appIsRunning() -> Bool {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(Int(max(found, 0))) where pid > 0 {
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            if String(cString: buffer).hasSuffix(".app/Contents/MacOS/Burrow") { return true }
        }
        return false
    }

    /// For burrow: sends the code to the app, and true only when the app answered that it is showing it.
    static func deliver(_ issued: PersonCode.Issued, state: URL) -> Bool {
        guard appIsRunning(), let remote = CFMessagePortCreateRemote(nil, portName(state: state) as CFString) else { return false }
        defer { CFMessagePortInvalidate(remote) }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let payload = try? encoder.encode(Request(code: issued.plain, action: issued.action, expires: issued.expires)) else { return false }
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(remote, 1, payload as CFData, 2, 2, CFRunLoopMode.defaultMode.rawValue, &reply)
        guard status == kCFMessagePortSuccess, let answer = reply?.takeRetainedValue() else { return false }
        return (answer as Data) == Data("shown".utf8)
    }
}
