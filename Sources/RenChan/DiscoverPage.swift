import AppKit
import RenChanKit
import SwiftUI

/// Discover (S-028): search VNDB for Ren'Py games and open the pages where they're sold or downloaded.
struct DiscoverPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if let error = model.discover.error, model.discover.results.isEmpty {
                ContentUnavailableView {
                    Label("VNDB Can't Be Reached", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { model.runDiscover() }
                }
            } else if model.discover.results.isEmpty && model.discover.searched && !model.discover.searching {
                ContentUnavailableView("No Results", systemImage: "magnifyingglass",
                                       description: Text("No games on VNDB match “\(model.discover.query)”. Try another title."))
            } else if model.discover.results.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if model.discover.query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Popular on VNDB").font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding([.horizontal, .top], Space.margin)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: Space.lg)], spacing: Space.xl) {
                        ForEach(model.discover.results) { info in
                            DiscoverCard(info: info, selected: model.discover.selection == info.id, inLibrary: model.libraryGame(vndb: info.id) != nil)
                                .onTapGesture { model.discover.selection = info.id }
                        }
                    }
                    .padding(Space.margin)
                    .gridArea("discover")
                }
                .background(.background)
            }
        }
        .navigationTitle(SidebarItem.discover.title)
        .searchable(text: $model.discover.query, placement: .toolbar, prompt: Text("Search VNDB"))
        .onSubmit(of: .search) { model.runDiscover() }
        .onChange(of: model.discover.query) { _, query in if query.isEmpty { model.runDiscover() } }
        .toolbar {
            ToolbarItem {
                Toggle("Ren'Py Only", systemImage: "line.3.horizontal.decrease.circle", isOn: $model.discover.renpyOnly)
                    .help("Show only games with a Ren'Py release")
                    .onChange(of: model.discover.renpyOnly) { model.runDiscover() }
            }
        }
        .inspector(isPresented: $model.showInspector) {
            Group {
                if let info = model.discover.results.first(where: { $0.id == model.discover.selection }) {
                    DiscoverDetails(info: info)
                } else {
                    ContentUnavailableView("No Game Selected", systemImage: "sparkle.magnifyingglass",
                                           description: Text("Select a game to see where to get it."))
                }
            }
            .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
        .task { if !model.discover.searched && !model.discover.searching { model.runDiscover() } }
    }
}

private struct DiscoverCard: View {
    let info: VNDBInfo
    let selected: Bool
    let inLibrary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            VNDBCover(info: info)
                .aspectRatio(Cover.ratio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(selected ? Palette.accent : Color.secondary.opacity(0.2), lineWidth: selected ? 3 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if inLibrary {
                        Label("In Library", systemImage: "checkmark")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, Space.xs)
                            .background(.thinMaterial, in: Capsule())
                            .padding(Space.sm)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: info.title).font(.headline).lineLimit(2)
                Text(verbatim: [info.developer, info.released.map { String($0.prefix(4)) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, Space.xs)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// VNDB's cover, loaded from the web; a tinted tile while it loads.
struct VNDBCover: View {
    let info: VNDBInfo

    var body: some View {
        AsyncImage(url: info.imageURL.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
        } placeholder: {
            ZStack {
                Rectangle().fill(Palette.accent.gradient.opacity(0.35))
                Text(verbatim: String(info.title.prefix(1)).uppercased())
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.accentText)
            }
        }
    }
}

/// The inspector on Discover: what the game is, and where to get it.
private struct DiscoverDetails: View {
    @Environment(AppModel.self) private var model
    let info: VNDBInfo

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Space.md) {
                    Text(verbatim: info.title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    VNDBCover(info: info)
                        .aspectRatio(Cover.ratio, contentMode: .fit)
                        .frame(width: 180)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .frame(maxWidth: .infinity)
                    if let game = model.libraryGame(vndb: info.id) {
                        Button("Show in Library") { model.showInLibrary(game.id) }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            Section("Where to Get It") {
                let releases = model.releases[info.id] ?? []
                if releases.isEmpty {
                    if model.releasesLoading.contains(info.id) {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("VNDB lists no download pages for this game.").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(releases.prefix(6)) { release in
                        ReleaseRow(release: release, info: info)
                    }
                    Text("Download it from one of these pages, then drop it on RenChan. It gets these details when you add it.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("Details") {
                if let developer = info.developer { LabeledContent("Developer", value: developer) }
                if let released = info.released {
                    LabeledContent("Released") {
                        if let date = info.releaseDate { Text(date, format: .dateTime.day().month(.wide).year()) } else { Text(verbatim: released) }
                    }
                }
                if let text = info.description, !text.isEmpty {
                    Text(verbatim: text).lineLimit(8).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                Link("Open on VNDB", destination: info.pageURL)
            }
        }
        .formStyle(.grouped)
        .task(id: info.id) { model.loadReleases(info.id) }
    }
}

private struct ReleaseRow: View {
    @Environment(AppModel.self) private var model
    let release: VNDBRelease
    let info: VNDBInfo

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(verbatim: release.title).font(.headline).lineLimit(2)
            Text(verbatim: facts).font(.caption).foregroundStyle(.secondary)
            if !release.links.isEmpty {
                FlowLayout(spacing: Space.xs) {
                    ForEach(release.links, id: \.url) { link in
                        Button(link.label) { model.openDownloadPage(link.url, for: info) }
                            .controlSize(.small)
                            .help(link.url.absoluteString)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var facts: String {
        var parts: [String] = []
        if let released = release.released { parts.append(released) }
        let names = ["win": "Windows", "mac": "Mac", "lin": "Linux", "and": "Android", "web": "Web"]
        let platforms = release.platforms.compactMap { names[$0] }
        if !platforms.isEmpty { parts.append(platforms.joined(separator: ", ")) }
        parts.append(release.freeware ? String(localized: "Free") : String(localized: "Paid"))
        if !release.official { parts.append(String(localized: "Fan release")) }
        return parts.joined(separator: " · ")
    }
}
