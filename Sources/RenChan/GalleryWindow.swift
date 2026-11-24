import AppKit
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

    func cachedPictures(of game: Game) -> [GamePicture]? {
        guard let data = try? Data(contentsOf: picturesFile(game.id)) else { return nil }
        return try? JSONDecoder().decode([GamePicture].self, from: data)
    }

    /// Asks Ren'Py where every picture is (its loose files and archives), then keeps the list.
    func readPictures(of game: Game) async throws -> [GamePicture] {
        let pictures = try await runSaveTool(game, modded: false) { SaveTool.picturesArguments(output: $0) }.pictures ?? []
        if let data = try? JSONEncoder().encode(pictures) { try? data.write(to: picturesFile(game.id)) }
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

/// Thumbnails decoded once, off the main thread.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(_ picture: GamePicture, pixels: Int) async -> NSImage? {
        let key = "\(picture.archive ?? picture.file ?? "")#\(picture.path)#\(pixels)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            picture.thumbnail(maxPixels: pixels).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
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
    @State private var viewing: GamePicture?

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
        } else if let viewing {
            PictureViewer(picture: viewing, pictures: shown) { self.viewing = $0 }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Space.md)], spacing: Space.md) {
                    ForEach(shown) { picture in
                        Button { viewing = picture } label: { Thumbnail(picture: picture) }
                            .buttonStyle(.plain)
                            .help(picture.path)
                    }
                }
                .padding(Space.lg)
                .gridArea("gallery")
            }
        }
    }

    /// Story pictures, or every picture when Interface Pictures is on.
    private var story: [GamePicture] { showInterface ? pictures : pictures.filter { !$0.isInterface } }

    private var folders: [(name: String, count: Int)] {
        Dictionary(grouping: story, by: \.folder).map { ($0.key, $0.value.count) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var shown: [GamePicture] {
        story.filter { (folder == Self.allFolders || $0.folder == folder) && (search.isEmpty || $0.path.localizedCaseInsensitiveContains(search)) }
    }

    private func load(refresh: Bool) {
        guard let game else { return }
        if !refresh, let cached = model.cachedPictures(of: game) {
            pictures = cached
            return
        }
        loading = true
        error = nil
        Task {
            do { pictures = try await model.readPictures(of: game) } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

private struct Thumbnail: View {
    let picture: GamePicture
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(.quaternary)
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            Text(verbatim: picture.name).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .contentShape(Rectangle())
        .task(id: picture) { image = await ThumbnailCache.shared.image(picture, pixels: 400) }
    }
}

/// One picture large, with the previous and next ones on the arrow keys.
private struct PictureViewer: View {
    let picture: GamePicture
    let pictures: [GamePicture]
    let show: (GamePicture?) -> Void
    @State private var image: NSImage?

    private var index: Int? { pictures.firstIndex(of: picture) }

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
                if let index { Text("\(index + 1) of \(pictures.count)").foregroundStyle(.secondary).monospacedDigit() }
                Button("Previous", systemImage: "chevron.left") { step(-1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled((index ?? 0) == 0)
                Button("Next", systemImage: "chevron.right") { step(1) }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled((index ?? 0) >= pictures.count - 1)
                Button("Copy") { copy() }.keyboardShortcut("c")
                Button("Export…") { export() }.keyboardShortcut("e")
            }
            .padding(Space.md)
            .background(.bar)
        }
        .task(id: picture) {
            image = nil
            image = await ThumbnailCache.shared.image(picture, pixels: 4096)
        }
    }

    private func step(_ by: Int) {
        guard let index, pictures.indices.contains(index + by) else { return }
        show(pictures[index + by])
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
