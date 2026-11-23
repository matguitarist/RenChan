import AppKit
import RenChanKit
import SwiftUI

/// The inspector's Details section: what VNDB says about the game, or a way to find it (S-010).
struct VNDBSection: View {
    @Environment(AppModel.self) private var model
    let game: Game
    @State private var expanded = false

    var body: some View {
        Section("Details") {
            if let info = game.vndb {
                if let developer = info.developer {
                    LabeledContent("Developer", value: developer)
                }
                if let released = info.released {
                    LabeledContent("Released") {
                        if let date = info.releaseDate {
                            Text(date, format: .dateTime.day().month(.wide).year())
                        } else {
                            Text(verbatim: released)
                        }
                    }
                }
                if let text = info.description, !text.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(verbatim: text)
                            .lineLimit(expanded ? nil : 4)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(expanded ? "Less" : "More") { expanded.toggle() }
                            .buttonStyle(.link)
                    }
                }
                HStack {
                    Link("Open on VNDB", destination: info.pageURL)
                    Spacer()
                    Menu("More Actions", systemImage: "ellipsis") {
                        Button("Refresh from VNDB") { model.refreshFromVNDB(game.id) }
                        Button("Find on VNDB…") { model.findOnVNDB(game.id) }
                        Divider()
                        Button("Unlink from VNDB") { model.unlinkVNDB(game.id) }
                    }
                    .labelStyle(.iconOnly)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Refresh or unlink the VNDB details")
                }
            } else {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("Get the cover, developer, release date and description from the Visual Novel Database.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Find on VNDB…") { model.findOnVNDB(game.id) }
                        .help("Search VNDB for this game (Shift-Command-D)")
                }
            }
        }
        .onChange(of: game.id) { expanded = false }
    }
}

/// Find on VNDB (S-010): search by title, pick a result, Use This Game.
struct VNDBSearchSheet: View {
    @Environment(AppModel.self) private var model
    let initial: VNDBSearch
    private var search: VNDBSearch { model.vndbSearch ?? initial }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Find on VNDB").font(.title3.weight(.semibold))
            TextField("Title", text: Binding(get: { search.query }, set: { model.vndbSearch?.query = $0 }))
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.runVNDBSearch() }
            if let error = search.error {
                Label(error, systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
            }
            results
                .frame(height: 300)
            HStack {
                Text("From vndb.org").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { model.vndbSearch = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Use This Game") { if let pick { model.useVNDB(pick) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pick == nil)
            }
        }
        .padding(Space.xl)
        .frame(width: 560)
        .noInitialFocus()
    }

    private var pick: VNDBInfo? { search.results.first { $0.id == search.selection } }

    @ViewBuilder
    private var results: some View {
        if search.searching && search.results.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if search.searched && search.results.isEmpty && search.error == nil {
            ContentUnavailableView("No Results", systemImage: "magnifyingglass",
                                   description: Text("No games on VNDB match “\(search.query)”. Try another title."))
        } else {
            List(search.results, selection: Binding(get: { search.selection }, set: { model.vndbSearch?.selection = $0 })) { info in
                VNDBRow(info: info).tag(info.id)
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .contextMenu(forSelectionType: VNDBInfo.ID.self) { _ in } primaryAction: { ids in
                if let id = ids.first, let info = search.results.first(where: { $0.id == id }) { model.useVNDB(info) }
            }
        }
    }
}

private struct VNDBRow: View {
    let info: VNDBInfo

    var body: some View {
        HStack(spacing: Space.md) {
            AsyncImage(url: info.imageURL.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 40, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: info.title).font(.headline).lineLimit(1)
                if let original = info.originalTitle {
                    Text(verbatim: original).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(verbatim: [info.developer, info.released.map { String($0.prefix(4)) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
