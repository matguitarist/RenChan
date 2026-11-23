import LogKitUI
import RenChanKit
import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.sidebar) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .badge(item == .library ? model.games.count : 0)
                        .tag(item)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            page(model.sidebar ?? .library)
        }
        .sheet(item: Binding(get: { model.download.map(DownloadSheetItem.init) }, set: { _ in })) { item in
            DownloadSheet(initial: item.state).environment(model).themed()
        }
        .sheet(item: Binding(get: { model.vndbSearch.map(VNDBSheetItem.init) }, set: { if $0 == nil { model.vndbSearch = nil } })) { item in
            VNDBSearchSheet(initial: item.search).environment(model).themed()
        }
        .sheet(item: Binding(get: { model.showBackups.map(BackupsSheetItem.init) }, set: { if $0 == nil { model.showBackups = nil } })) { item in
            SaveBackupsSheet(gameID: item.id).environment(model).themed()
        }
        .onChange(of: model.walkthroughToOpen) { _, ref in
            if let ref { openWindow(id: "walkthrough", value: ref); model.walkthroughToOpen = nil }
        }
        .onChange(of: model.savesToOpen) { _, ref in
            if let ref { openWindow(id: "saves", value: ref); model.savesToOpen = nil }
        }
        .sheet(item: Binding(get: { model.findGames.map(FindGamesSheetItem.init) }, set: { if $0 == nil { model.findGames = nil } })) { item in
            FindGamesSheet(initial: item.state).environment(model).themed()
        }
        .sheet(item: Binding(get: { model.addModsTo.map(AddModSheetItem.init) }, set: { if $0 == nil { model.addModsTo = nil } })) { item in
            AddModSheet(target: item.target).environment(model).themed()
        }
        .sheet(item: $model.launchError) { failure in
            LaunchErrorSheet(failure: failure).environment(model).themed()
        }
        .confirmationDialog(removeTitle, isPresented: Binding(get: { model.confirmRemove != nil }, set: { if !$0 { model.confirmRemove = nil } })) {
            Button("Remove", role: .destructive) { if let id = model.confirmRemove { model.remove(id) } }
        } message: {
            Text("RenChan deletes its working copy. The game you added and your saves stay where they are.")
        }
        .confirmationDialog(copyTitle, isPresented: Binding(get: { model.confirmFullCopy != nil }, set: { if !$0 { model.confirmFullCopy = nil } })) {
            Button("Copy and Play") { model.confirmCopyAndPlay() }
        } message: {
            Text("The game is on another disk, so RenChan needs a full copy (\(model.confirmFullCopy?.size.bytesText ?? "")) in its own folder. The original stays as it is.")
        }
        .confirmationDialog(zipTitle, isPresented: Binding(get: { model.confirmZip != nil }, set: { if !$0 { model.confirmZip = nil } })) {
            Button("Unpack") { if let zip = model.confirmZip?.url { model.addZip(zip) } }
        } message: {
            Text(model.confirmZip?.size.map { String(localized: "RenChan unpacks it into its own folder (\($0.bytesText)). The zip stays as it is.") }
                 ?? String(localized: "RenChan unpacks it into its own folder. The zip stays as it is."))
        }
        .confirmationDialog(updateTitle, isPresented: Binding(get: { model.confirmUpdate != nil }, set: { if !$0 { model.confirmUpdate = nil } })) {
            Button("Update") { if let request = model.confirmUpdate { model.applyUpdate(request) } }
        } message: {
            Text(updateMessage)
        }
        .confirmationDialog(runtimeTitle, isPresented: Binding(get: { model.confirmRemoveRuntime != nil }, set: { if !$0 { model.confirmRemoveRuntime = nil } })) {
            Button("Remove", role: .destructive) { if let version = model.confirmRemoveRuntime { model.removeRuntime(version) } }
        } message: {
            Text("RenChan downloads it again the next time a game needs it.")
        }
        .alert("RenChan", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
        .task {
            SeedData.addIfRequested(model: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var removeTitle: String {
        String(localized: "Remove “\(model.game(model.confirmRemove)?.title ?? "")” from the library?")
    }
    private var copyTitle: String {
        String(localized: "Copy “\(model.game(model.confirmFullCopy?.id)?.title ?? "")” to play it?")
    }
    private var zipTitle: String {
        String(localized: "Unpack “\(model.confirmZip?.url.lastPathComponent ?? "")”?")
    }
    private var updateTitle: String {
        String(localized: "Update “\(model.game(model.confirmUpdate?.game)?.title ?? "")” to \(model.confirmUpdate?.url.lastPathComponent ?? "")?")
    }
    private var updateMessage: String {
        let keep = String(localized: "Its playtime, status, rating, labels, notes, cover and save backups stay. RenChan makes a fresh working copy; the old version's files stay where they are.")
        guard let request = model.confirmUpdate, request.isZip else { return keep }
        let unpack = request.size.map { String(localized: "RenChan unpacks the zip into its own folder (\($0.bytesText)).") }
            ?? String(localized: "RenChan unpacks the zip into its own folder.")
        return unpack + " " + keep
    }
    private var runtimeTitle: String {
        String(localized: "Remove Ren'Py \(model.confirmRemoveRuntime ?? "")?")
    }

    @ViewBuilder
    private func page(_ item: SidebarItem) -> some View {
        switch item {
        case .library: LibraryPage()
        case .discover: DiscoverPage()
        case .runtimes: RuntimesPage()
        case .log:
            LogViewer(model: model.logViewer, options: LogViewerOptions(
                emptyTitle: String(localized: "No Log Yet"),
                emptyMessage: String(localized: "What RenChan does shows here: games added, runtimes downloaded, games played.")))
                .navigationTitle(SidebarItem.log.title)
        }
    }
}

private struct FindGamesSheetItem: Identifiable {
    let state: FindGamesState
    var id: String { "find" }
}

/// Stays up while the person picks the game underneath.
private struct AddModSheetItem: Identifiable {
    let target: ModTarget
    var id: UUID { target.id }
}

private struct BackupsSheetItem: Identifiable {
    let id: Game.ID
}

/// The VNDB sheet stays up while its results change underneath.
private struct VNDBSheetItem: Identifiable {
    let search: VNDBSearch
    var id: Game.ID { search.game }
}

/// The download sheet stays up for the whole download; its state changes underneath.
private struct DownloadSheetItem: Identifiable {
    let state: DownloadState
    var id: String { state.version }
}
