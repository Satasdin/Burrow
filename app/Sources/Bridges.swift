import AppKit
import CAMRCore
import SwiftUI

/// A bridged vault in the Library: its own section after this vault's folders, each file labelled with its vault (D-97).
struct BridgedSection: View {
    static let symbol = "point.3.connected.trianglepath.dotted"
    let workspace: Workspace
    let shelf: BridgedShelf
    let kind: LibraryKind

    private var files: [MapFile] {
        shelf.files.filter { kind.holds($0) }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    var body: some View {
        if shelf.problem != nil || !files.isEmpty || kind == .all {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: Self.symbol).foregroundStyle(Night.conversation)
                    Text(shelf.bridge.name).font(.system(size: 15, weight: .semibold))
                    Text("\(files.count)").font(.system(size: 13)).foregroundStyle(Night.faint).monospacedDigit()
                    Text("bridged vault · read-only" + (shelf.bridge.withLedger ? " · with its decisions" : ""))
                        .font(.system(size: 12)).foregroundStyle(Night.faint)
                    Spacer()
                }
                .help(shelf.bridge.path)
                if let problem = shelf.problem {
                    Text(problem).font(.system(size: 12)).foregroundStyle(Night.stale)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 240), spacing: 16, alignment: .top)], alignment: .leading, spacing: 18) {
                        ForEach(Array(files.enumerated()), id: \.element.path) { index, file in
                            CoverCard(workspace: workspace, path: file.path, selected: workspace.librarySelection == file.path)
                                .arrive(index)
                                .onTapGesture(count: 2) { workspace.go(.file(file.path), newTab: true) }
                                .simultaneousGesture(TapGesture().onEnded { workspace.librarySelection = file.path })
                        }
                    }
                }
            }
            .padding(.top, 8)
            .overlay(alignment: .top) { Rectangle().fill(Night.conversation.opacity(0.25)).frame(height: 1).offset(y: -6) }
        }
    }
}

/// Where bridges are added and taken away, with the vault's storage beside them.
struct BridgesSheet: View {
    let workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var withLedger = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: BridgedSection.symbol).foregroundStyle(Night.conversation)
                Text("Bridges").font(.title2.weight(.semibold))
            }
            Text("A bridge lets \(workspace.name) read another vault. Its notes show in the Library, in search and in Ask, each marked with its vault's name. It works one way and only reads: nothing is ever written into the other vault, and that vault's own bridges are not followed.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if workspace.bridged.isEmpty {
                Text("No bridges yet.").font(.callout).foregroundStyle(.tertiary)
            }
            ForEach(workspace.bridged, id: \.bridge.name) { shelf in
                HStack(spacing: 10) {
                    Image(systemName: BridgedSection.symbol).foregroundStyle(Night.conversation).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shelf.bridge.name).font(.body.weight(.semibold))
                        Text((shelf.bridge.path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Text(shelf.problem ?? "\(shelf.files.count) files · " + (shelf.bridge.withLedger ? "notes and decisions in force" : "notes only"))
                            .font(.caption).foregroundStyle(shelf.problem == nil ? Color.secondary : Night.stale)
                    }
                    Spacer()
                    Button("Remove") { Task { await workspace.removeBridge(shelf.bridge.name) } }
                        .help("Stop reading \(shelf.bridge.name). Nothing in either vault changes.")
                }
                .padding(10)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                Toggle("A new bridge also hands over that vault's decisions in force", isOn: $withLedger)
                Text("Off unless you choose it: what a vault decided, and why, can be more private than its notes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Add a Bridge…") { pickBridge(workspace, withLedger: withLedger) }.buttonStyle(.borderedProminent)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if let storage = workspace.storage {
                Divider().padding(.vertical, 2)
                Text("Storage").font(.headline)
                StorageBars(report: storage, wide: true)
                Text("CAMR's own store is what counts: the index, meaning search, conversations and the Ledger. Your own files are never counted and never deleted. Set a limit with camr config, such as storage.limit 2GB.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}

@MainActor
func pickBridge(_ workspace: Workspace, withLedger: Bool) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.prompt = "Bridge"
    panel.message = "Choose another CAMR vault. \(workspace.name) will read it, one way and read-only."
    if panel.runModal() == .OK, let url = panel.url { Task { await workspace.addBridge(url, withLedger: withLedger) } }
}

/// CAMR's store against its limits: this vault, and every vault together (D-98). Amber near a limit, red past it.
struct StorageBars: View {
    let report: StorageReport
    var wide = false

    var body: some View {
        VStack(alignment: .leading, spacing: wide ? 8 : 3) {
            row("This vault", used: report.usage.total, limit: report.limit)
            row(report.vaultCount == 1 ? "All vaults" : "All \(report.vaultCount) vaults", used: report.allVaults, limit: report.globalLimit)
        }
        .help("CAMR's own store: index \(ByteSize.format(report.usage.index)), meaning search \(ByteSize.format(report.usage.vectorCache)), conversations and the Ledger \(ByteSize.format(report.usage.other)). Your files are not counted.")
    }

    private func colour(_ share: Double) -> Color {
        share >= 1 ? Night.stale : share >= StorageReport.nearShare ? Night.document : Night.conversation
    }

    private func row(_ title: String, used: Int, limit: Int?) -> some View {
        let share = limit.map { Double(used) / Double(max(1, $0)) }
        return HStack(spacing: 7) {
            Text(title).font(.system(size: wide ? 12 : 10.5)).foregroundStyle(Night.dim).frame(width: wide ? 86 : 64, alignment: .leading)
            if let share {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(colour(share)).frame(width: max(3, (wide ? 200 : 84) * min(1, share)))
                }
                .frame(width: wide ? 200 : 84, height: wide ? 7 : 5)
            }
            Text(limit.map { "\(ByteSize.format(used)) of \(ByteSize.format($0))" } ?? "\(ByteSize.format(used)) · no limit")
                .font(.system(size: wide ? 12 : 10.5)).foregroundStyle(share.map { $0 >= StorageReport.nearShare ? colour($0) : Night.dim } ?? Night.faint)
                .monospacedDigit()
            if let share, share >= StorageReport.nearShare {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: wide ? 11 : 9)).foregroundStyle(colour(share))
                    .help(share >= 1 ? "Over the limit: indexing adds nothing more until it is raised." : "Near the limit.")
            }
        }
    }
}
