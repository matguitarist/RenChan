import AppKit
import PictureKitUI
import RenChanKit
import SwiftUI
import UniformTypeIdentifiers

/// RenChan's gallery (S-042): every picture of a game, read from its files and archives without playing it.
struct GalleryRef: Codable, Hashable {
    var game: Game.ID
}

extension AppModel {
    func showGallery(_ id: Game.ID) { galleryToOpen = GalleryRef(game: id) }

    /// Where the last list is kept, so the gallery opens at once, even while the game plays.
    private func picturesFile(_ id: Game.ID) -> URL { Store.gameFolder(id).appending(path: "pictures.json") }

    /// Read off the main thread: a big game lists tens of thousands of pictures.
    func cachedPictures(of game: Game) async -> [GamePicture]? {
        let file = picturesFile(game.id)
        return await Task.detached(priority: .userInitiated) { () -> [GamePicture]? in
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? JSONDecoder().decode([GamePicture].self, from: data)
        }.value
    }

    /// Asks Ren'Py where every picture is (its loose files and archives), then keeps the list.
    func readPictures(of game: Game) async throws -> [GamePicture] {
        let pictures = try await runSaveTool(game, modded: false) { SaveTool.picturesArguments(output: $0) }.pictures ?? []
        let file = picturesFile(game.id)
        await Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(pictures) { try? data.write(to: file) }
        }.value
        log.post(.info, "Found \(pictures.count) pictures in \(game.title)", source: "Gallery")
        return pictures
    }
}

extension GamePicture: Encodable {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(path, forKey: .path)
        try c.encodeIfPresent(file, forKey: .file)
        try c.encodeIfPresent(archive, forKey: .archive)
        try c.encodeIfPresent(parts, forKey: .parts)
    }
    private enum Keys: String, CodingKey { case path, file, archive, parts }
}

extension GamePicture.Part: Encodable {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encodeIfPresent(offset, forKey: .offset)
        try c.encodeIfPresent(length, forKey: .length)
        try c.encodeIfPresent(bytes, forKey: .bytes)
    }
    private enum Keys: String, CodingKey { case offset, length, bytes }
}

extension GamePicture {
    /// Read from its file or archive only when shown, off the main thread.
    var source: PictureSource {
        let picture = self
        return .data(id: "\(archive ?? file ?? "")#\(path)") { try picture.data() }
    }
}

struct GalleryWindow: View {
    static let allFolders = "\u{1}all"
    @Environment(AppModel.self) private var model
    let ref: GalleryRef
    @State private var pictures: [GamePicture] = []
    /// The folder shown; allFolders shows every picture.
    @State private var folder = GalleryWindow.allFolders
    @State private var search = ""
    @State private var showInterface = false
    @State private var loading = false
    @State private var error: String?
    /// The index in shown of the picture viewed large.
    @State private var viewing: Int?
    /// Worked out when the pictures, folder, search or interface toggle change, not on every redraw.
    @State private var story: [GamePicture] = []
    @State private var folders: [(name: String, count: Int)] = []
    @State private var shown: [GamePicture] = []

    private var game: Game? { model.game(ref.game) }

    var body: some View {
        NavigationSplitView {
            List(selection: $folder) {
                Label { Text("All Pictures") } icon: { Image(systemName: "photo.on.rectangle") }
                    .badge(story.count)
                    .tag(GalleryWindow.allFolders)
                Section("Folders") {
                    ForEach(folders, id: \.name) { item in
                        Label { Text(verbatim: item.name.isEmpty ? "game" : item.name) } icon: { Image(systemName: "folder") }
                            .badge(item.count)
                            .tag(item.name)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            detail
        }
        .navigationTitle(game.map { String(localized: "Gallery of \($0.title)") } ?? String(localized: "Gallery"))
        .searchable(text: $search, placement: .toolbar, prompt: Text("Search Pictures"))
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $showInterface) { Label("Interface Pictures", systemImage: "square.on.square.dashed") }
                    .help("Also show the game’s interface pictures: buttons, frames and menus")
            }
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { load(refresh: true) }
                    .disabled(loading || game.map { model.playing.contains($0.id) } ?? true)
                    .help("List the pictures again, for a new version of the game")
            }
        }
        .noInitialFocus()
        .task { load(refresh: false) }
        .onChange(of: showInterface) { sortOut(story: true) }
        .onChange(of: folder) { sortOut(story: false) }
        .onChange(of: search) { sortOut(story: false) }
    }

    /// Story pictures (or every picture with Interface Pictures on), their folders, and the ones shown.
    private func sortOut(story changed: Bool) {
        if changed {
            story = showInterface ? pictures : pictures.filter { !$0.isInterface }
            folders = Dictionary(grouping: story, by: \.folder).map { ($0.key, $0.value.count) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        shown = story.filter { (folder == Self.allFolders || $0.folder == folder) && (search.isEmpty || $0.path.localizedCaseInsensitiveContains(search)) }
        viewing = nil
    }

    @ViewBuilder
    private var detail: some View {
        if loading && pictures.isEmpty {
            VStack(spacing: Space.md) {
                ProgressView()
                Text("Finding the pictures with Ren'Py…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error, pictures.isEmpty {
            ContentUnavailableView {
                Label("No Pictures", systemImage: "photo")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { load(refresh: true) }
            }
        } else if shown.isEmpty {
            if search.isEmpty { ContentUnavailableView("No Pictures", systemImage: "photo", description: Text("This folder has no pictures.")) }
            else { ContentUnavailableView.search(text: search) }
        } else if let viewing, shown.indices.contains(viewing) {
            PictureViewer(index: viewing, pictures: shown) { self.viewing = $0 }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Space.md)], spacing: Space.md) {
                    ForEach(shown.indices, id: \.self) { index in
                        Button { viewing = index } label: { Thumbnail(picture: shown[index]) }
                            .buttonStyle(.plain)
                            .help(shown[index].path)
                    }
                }
                .padding(Space.lg)
                .gridArea("gallery")
            }
        }
    }

    private func load(refresh: Bool) {
        guard let game else { return }
        loading = true
        error = nil
        Task {
            if !refresh, let cached = await model.cachedPictures(of: game) {
                pictures = cached
            } else {
                do { pictures = try await model.readPictures(of: game) } catch { self.error = error.localizedDescription }
            }
            sortOut(story: true)
            loading = false
        }
    }
}

private struct Thumbnail: View {
    let picture: GamePicture

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(.quaternary)
                AsyncPicture(picture.source, contentMode: .fill, maxPixels: 400) {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            Text(verbatim: picture.name).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .contentShape(Rectangle())
    }
}

/// One picture large, with the previous and next ones on the arrow keys.
private struct PictureViewer: View {
    let index: Int
    let pictures: [GamePicture]
    let show: (Int?) -> Void
    @State private var image: NSImage?

    private var picture: GamePicture { pictures[index] }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit) } else { ProgressView() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Space.lg)
            HStack(spacing: Space.sm) {
                Button("Back to All", systemImage: "square.grid.2x2") { show(nil) }
                    .keyboardShortcut(.cancelAction)
                    .help("Back to the grid (Escape)")
                Text(verbatim: picture.path).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(index + 1) of \(pictures.count)").foregroundStyle(.secondary).monospacedDigit()
                Button("Previous", systemImage: "chevron.left") { step(-1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(index == 0)
                Button("Next", systemImage: "chevron.right") { step(1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(index >= pictures.count - 1)
                Button("Copy") { copy() }.keyboardShortcut("c")
                Button("Export…") { export() }.keyboardShortcut("e")
            }
            .padding(Space.md)
            .background(.bar)
        }
        .task(id: picture) {
            image = nil
            image = await PictureCache.shared.image(picture.source, maxPixels: 4096)
                .map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }
    }

    private func step(_ by: Int) {
        guard pictures.indices.contains(index + by) else { return }
        show(index + by)
    }

    private func copy() {
        guard let image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    /// Saves the picture's own bytes, as the game ships them.
    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = picture.name
        guard panel.runModal() == .OK, let url = panel.url, let data = try? picture.data() else { return }
        try? data.write(to: url)
    }
}
