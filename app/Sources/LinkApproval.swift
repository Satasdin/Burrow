import BurrowCore
import SwiftUI

/// Asked once when a vault opens with linked folders the person on this Mac has not approved (D-101). A vault's list of
/// linked folders is a file in its folder, so a vault someone else gave you could point it anywhere on this Mac. Until
/// the person says yes here, or with `burrow link approve`, those folders are not read by anything.
struct LinkApprovalSheet: View {
    static let symbol = "link"
    let workspace: Workspace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: Self.symbol).foregroundStyle(Night.document)
                Text("Linked folders").font(.title2.weight(.semibold))
            }
            Text("\(workspace.name) links \(workspace.linksWaiting.count == 1 ? "this folder" : "these folders") on your Mac. Burrow reads a linked folder only once you allow it here, so a vault someone else shared with you can't open your own folders.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(workspace.linksWaiting) { state in
                HStack(spacing: 10) {
                    Image(systemName: "folder").foregroundStyle(Night.document).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.folder.name).font(.body.weight(.semibold))
                        Text((state.folder.path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        if state.leadsElsewhere {
                            Text("which is " + (state.realPath as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        if !state.exists {
                            Text("Not found on this Mac").font(.caption).foregroundStyle(Night.stale)
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 8))
                .help(state.realPath)
            }
            Text("Allowed, \(workspace.linksWaiting.count == 1 ? "it is" : "they are") read where \(workspace.linksWaiting.count == 1 ? "it is" : "they are") and never changed, by search, Ask and the programs you connect. Not now leaves \(workspace.linksWaiting.count == 1 ? "it" : "them") out of all of these, and asks again the next time this vault opens.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Not now") { workspace.linksOpen = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Allow") { Task { await workspace.approveLinks() } }.buttonStyle(.borderedProminent)
                    .help("Approve \(workspace.linksWaiting.count == 1 ? "this folder" : "these folders") for \(workspace.name) on this Mac.")
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}

/// The line under the window while linked folders wait, so Not now is never the last word.
struct LinksWaitingBar: View {
    let workspace: Workspace

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: LinkApprovalSheet.symbol).foregroundStyle(Night.document)
            Text(workspace.linksWaiting.count == 1 ? "A linked folder is waiting for your approval, so it is skipped."
                                                   : "\(workspace.linksWaiting.count) linked folders are waiting for your approval, so they are skipped.")
                .lineLimit(1)
            Spacer()
            Button("Review…") { workspace.linksOpen = true }.buttonStyle(.link)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }
}
