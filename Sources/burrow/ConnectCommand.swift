import BurrowCore
import BurrowTools
import Foundation

let connectUsage = """
  burrow connect <program> <vault> [--write] [--home DIR]   the setup a program needs for this vault: Burrow as an MCP server,
                                                            its tools always in view, and Burrow's gate inside the program.
                                                            Programs: claude-code, opencode, openclaw, hermes, n8n. Prints it;
                                                            --write writes it, in your own terminal after you type yes
"""

/// `burrow connect` (D-108). Returns false when the command is not this one.
func runConnectCommand(_ arguments: [String]) throws -> Bool {
    guard arguments.first == "connect" else { return false }
    var positional: [String] = []
    var write = false
    var home: String?
    var index = 1
    while index < arguments.count {
        switch arguments[index] {
        case "--write": write = true; index += 1
        case "--home":
            guard index + 1 < arguments.count else { throw Failure("--home needs a folder") }
            home = arguments[index + 1]; index += 2
        default: positional.append(arguments[index]); index += 1
        }
    }
    let programs = Connect.Program.allCases.map(\.rawValue).joined(separator: ", ")
    guard positional.count == 2 else { throw Failure("connect needs a program and a vault: burrow connect <program> <vault>. Programs: \(programs).") }
    guard let program = Connect.Program(word: positional[0]) else {
        throw Failure("burrow connect doesn't know \(Printable.clean(positional[0])). Programs: \(programs).")
    }
    var isFolder: ObjCBool = false
    let vaultURL = URL(fileURLWithPath: positional[1]).standardizedFileURL
    guard FileManager.default.fileExists(atPath: vaultURL.path, isDirectory: &isFolder), isFolder.boolValue else {
        throw Failure("\(Printable.clean(positional[1])) is not a folder")
    }
    // The running executable itself, resolved, so the program never starts whatever `burrow` its PATH finds.
    guard let running = Bundle.main.executablePath, running.hasPrefix("/") else { throw Failure("could not tell where this burrow binary is") }
    let environment = ProcessInfo.processInfo.environment
    // The home the programs themselves use: $HOME, as Node, Python and OpenCode read it. NSHomeDirectory() would give the
    // account's home even when HOME points elsewhere, and write settings the program never reads (found in a D-108 run).
    let homeURL = URL(fileURLWithPath: home ?? environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()).standardizedFileURL
    // With --home everything is under that folder; otherwise the programs' own variables are honoured, as they honour them.
    let configHome = home == nil ? environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) } : nil
    let hermesHome = home == nil ? environment["HERMES_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) } : nil
    let setup = Connect.Setup(burrow: URL(fileURLWithPath: running).resolvingSymlinksInPath().path,
                              vault: Vault.realPath(vaultURL.path), home: homeURL, configHome: configHome, hermesHome: hermesHome,
                              stateDir: environment["BURROW_STATE_DIR"])
    let plan = Connect.plan(program, setup)
    print(Connect.describe(plan, setup))
    fflush(stdout)
    if let refusal = plan.refusal { throw Failure((write ? "nothing was written: " : "") + refusal) }
    guard write else {
        if !plan.pending.isEmpty {
            print("\nNothing was written. To write this, run it again with --write in your own terminal; you'll be asked first.")
        }
        return true
    }
    guard !plan.pending.isEmpty else { print("\nAlready set up; nothing to write."); return true }
    // Writing a program's settings changes what that program runs, so only the person does it, in their own terminal (D-104).
    guard inPersonsTerminal() else {
        throw Failure("only you can change a program's settings: run this in your own terminal. It can't be done through a pipe or by a program you've connected to Burrow. Nothing was written.")
    }
    let count = plan.pending.count
    FileHandle.standardError.write(Data("\nWrite \(count) file\(count == 1 ? "" : "s") for \(program.name)? Type yes to write, anything else to stop: ".utf8))
    let answer = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespaces).lowercased()
    guard answer == "yes" else { throw Failure("nothing was written") }
    for line in try Connect.apply(plan, setup) { print(line) }
    print("Done. Start \(program.name) again so it loads Burrow and the gate.")
    return true
}
