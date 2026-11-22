import LogKitUI
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.sidebar) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            page(model.sidebar ?? .overview)
        }
        .task {
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    @ViewBuilder
    private func page(_ item: SidebarItem) -> some View {
        switch item {
        case .overview: OverviewPage()
        case .log:
            LogViewer(model: model.logViewer, options: LogViewerOptions(
                emptyTitle: String(localized: "No Log Yet"),
                emptyMessage: String(localized: "What RenChan does shows here: games added, runtimes downloaded, games played.")))
                .navigationTitle(SidebarItem.log.title)
        }
    }
}

/// The library comes in 0.1.0 (docs/STORIES.md, M1). Until then, what RenChan will do.
struct OverviewPage: View {
    var body: some View {
        ContentUnavailableView {
            Label("Your Ren'Py Library", systemImage: "books.vertical")
        } description: {
            Text("RenChan will keep your Ren'Py visual novels in one place and play any of them on this Mac, even games made only for Windows or Linux, with screen filters and mods that never change the game.")
        }
        .navigationTitle(SidebarItem.overview.title)
    }
}
