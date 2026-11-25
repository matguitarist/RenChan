import FileKit
import RenChanKit
import SwiftUI

/// The Ren'Py versions RenChan has downloaded, the games that use each, and Remove.
struct RuntimesPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.runtimes.isEmpty {
                ContentUnavailableView("No Runtimes Yet", systemImage: "shippingbox",
                                       description: Text("RenChan downloads the Ren'Py a game needs from renpy.org the first time you play it."))
            } else {
                List(model.runtimes) { runtime in
                    RuntimeRow(runtime: runtime)
                }
            }
        }
        .navigationTitle(SidebarItem.runtimes.title)
    }
}

struct RuntimeRow: View {
    @Environment(AppModel.self) private var model
    let runtime: Runtime
    @State private var size: Int64?

    var body: some View {
        HStack(spacing: Space.md) {
            IconTile(symbol: "shippingbox.fill", size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ren'Py \(runtime.version)").font(.headline)
                Text(details).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove…") { model.confirmRemoveRuntime = runtime.version }
                .disabled(!model.playing.isEmpty)
        }
        .padding(.vertical, Space.xs)
        .task(id: runtime.version) {
            size = await FolderSize.allocated(of: runtime.folder)
        }
    }

    private var details: String {
        let python = (RenPyVersion(runtime.version)?.pythonLine ?? .python3).title
        let arch = runtime.isUniversal ? String(localized: "Native") : String(localized: "Runs under Rosetta")
        let used = model.games(using: runtime).count
        let games = used == 1 ? String(localized: "1 game") : String(localized: "\(used) games")
        return [python, arch, size?.bytesText, games].compactMap { $0 }.joined(separator: " · ")
    }
}
