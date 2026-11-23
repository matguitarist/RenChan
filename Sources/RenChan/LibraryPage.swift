import AppKit
import RenChanKit
import SwiftUI

/// The library: games as a cover grid or a list, with the selected game's details in the inspector.
struct LibraryPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.games.isEmpty {
                EmptyLibrary()
            } else if model.shownGames.isEmpty && model.filter.isActive {
                ContentUnavailableView {
                    Label("No Games Match These Filters", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Clear Filters") { model.filter = LibraryFilter() }
                }
            } else if model.shownGames.isEmpty {
                ContentUnavailableView.search(text: model.search)
            } else if model.layout == .grid {
                LibraryGrid()
            } else {
                LibraryList()
            }
        }
        .navigationTitle(SidebarItem.library.title)
        .searchable(text: $model.search, placement: .toolbar, prompt: Text("Search Games"))
        .toolbar { LibraryToolbar() }
        .inspector(isPresented: Binding(get: { model.showInspector && !model.games.isEmpty }, set: { model.showInspector = $0 })) {
            Group {
                if let game = model.selectedGame {
                    GameDetails(game: game)
                } else {
                    ContentUnavailableView("No Game Selected", systemImage: "book.closed",
                                           description: Text("Select a game to see its Ren'Py version, saves, and files."))
                }
            }
            .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
        .onDeleteCommand { model.confirmRemove = model.selection }
        .dropDestination(for: URL.self) { urls, _ in
            model.add(urls)
            return !urls.isEmpty
        }
    }
}

struct EmptyLibrary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Drop a Ren'Py Game Here", systemImage: "square.and.arrow.down.on.square")
        } description: {
            Text("A game folder, a Mac .app, or a zip. RenChan plays it on this Mac without changing it.")
        } actions: {
            Button("Add Game…") { model.addWithPanel() }
        }
    }
}

struct LibraryToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        @Bindable var model = model
        ToolbarItem {
            Button("Add Game", systemImage: "plus") { model.addWithPanel() }
                .help("Add a game folder, a Mac .app, or a zip (Command-O)")
        }
        ToolbarItemGroup {
            Picker("View", selection: $model.layout) {
                Label("Grid", systemImage: "square.grid.2x2").tag(LibraryLayout.grid)
                Label("List", systemImage: "list.bullet").tag(LibraryLayout.list)
            }
            .pickerStyle(.segmented)
            .help("Show games as a grid (Command-1) or a list (Command-2)")
            FilterMenu()
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort By", selection: $model.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
            .help("Sort the library")
        }
    }
}

// MARK: Grid

struct LibraryGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: Space.lg)], spacing: Space.xl) {
                ForEach(model.shownGames) { game in
                    GameCard(game: game, selected: model.selection == game.id, playing: model.playing.contains(game.id))
                        .onTapGesture(count: 2) { model.play(game.id) }
                        .simultaneousGesture(TapGesture().onEnded { model.selection = game.id })
                        .contextMenu { GameActions(game: game) }
                }
            }
            .padding(Space.margin)
            .gridArea("library")
        }
        .background(.background)
        .onTapGesture { model.selection = nil }
    }
}

struct GameCard: View {
    let game: Game
    let selected: Bool
    let playing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Cover(game: game)
                .aspectRatio(Cover.ratio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(selected ? Palette.accent : Color.secondary.opacity(0.2), lineWidth: selected ? 3 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if playing {
                        Label("Playing", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, Space.xs)
                            .background(.thinMaterial, in: Capsule())
                            .padding(Space.sm)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(game.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(game.versionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.xs)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The cover from VNDB or the person, else the game's main menu art, else a tinted tile with its first letter.
struct Cover: View {
    /// VNDB's covers are 2:3 portraits; the game's own landscape art is cropped to the middle.
    static let ratio: CGFloat = 2 / 3

    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let _ = model.coverRevision
        if let image = CoverCache.shared.image(for: game) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack {
                Rectangle().fill(Palette.accent.gradient.opacity(0.35))
                Text(verbatim: String(game.title.prefix(1)).uppercased())
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.accentText)
            }
        }
    }
}

/// Covers read once from disk; the grid redraws often.
final class CoverCache {
    static let shared = CoverCache()
    private var images: [Game.ID: NSImage?] = [:]

    func image(for game: Game) -> NSImage? {
        if let cached = images[game.id] { return cached }
        let own = Store.coverFile(game.id)
        let file = FileManager.default.fileExists(atPath: own.path) ? own : GameLocator.cover(base: game.baseURL)
        let image = file.flatMap { NSImage(contentsOf: $0) }
        images[game.id] = image
        return image
    }

    func forget(_ id: Game.ID) { images[id] = nil }
}

// MARK: List

struct LibraryList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Table(model.shownGames, selection: $model.selection) {
            TableColumn("Title") { game in
                HStack(spacing: Space.sm) {
                    Text(game.title)
                    if model.playing.contains(game.id) {
                        Image(systemName: "play.fill").foregroundStyle(Palette.accentText).accessibilityLabel("Playing")
                    }
                }
            }
            .width(min: 160, ideal: 260)
            TableColumn("Status") { game in Text(game.status.title) }
                .width(min: 80, ideal: 100)
            TableColumn("Rating") { game in
                Text(verbatim: game.stars).foregroundStyle(Palette.accentText)
                    .accessibilityLabel(game.rating.map { String(localized: "\($0) stars") } ?? String(localized: "Not rated"))
            }
            .width(min: 70, ideal: 80)
            TableColumn("Ren'Py") { game in Text(game.version.map { "\($0)" } ?? String(localized: "Unknown")) }
                .width(min: 70, ideal: 90)
            TableColumn("Python") { game in Text(game.pythonLine?.title ?? String(localized: "Unknown")) }
                .width(min: 70, ideal: 90)
            TableColumn("Date Added") { game in Text(game.added, format: .dateTime.day().month().year()) }
                .width(min: 90, ideal: 110)
            TableColumn("Last Played") { game in Text(game.lastPlayedText) }
                .width(min: 90, ideal: 120)
            TableColumn("Playtime") { game in Text(game.playtimeText) }
                .width(min: 80, ideal: 100)
        }
        .contextMenu(forSelectionType: Game.ID.self) { ids in
            if let id = ids.first, let game = model.game(id) { GameActions(game: game) }
        } primaryAction: { ids in
            if let id = ids.first { model.play(id) }
        }
    }
}

/// The actions on one game, for context menus.
struct GameActions: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        if model.playing.contains(game.id) {
            Button("Stop") { model.stop(game.id) }
        } else {
            Button("Play") { model.play(game.id) }
        }
        Divider()
        Button("Show in Finder") { model.showInFinder(game.id) }
        Button("Open Saves Folder") { model.openSaves(game.id) }
            .disabled(game.saveDirectory == nil)
        Divider()
        Button("Update to New Version…") { model.chooseUpdate(game.id) }
            .disabled(model.playing.contains(game.id))
        Button("Find on VNDB…") { model.findOnVNDB(game.id) }
        Button("Choose Cover…") { model.chooseCover(game.id) }
        if game.customCover {
            Button("Reset Cover") { model.resetCover(game.id) }
        }
        Divider()
        Button("Remove from Library…") { model.confirmRemove = game.id }
    }
}

extension PythonLine {
    var title: String {
        switch self {
        case .python2: String(localized: "Python 2")
        case .python3: String(localized: "Python 3")
        }
    }
}

extension Game {
    /// "3 hr, 20 min", "Less than a minute", or "Never" for a game never played.
    var playtimeText: String {
        if playtime < 60 { return lastPlayed == nil ? String(localized: "Never") : String(localized: "Less than a minute") }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = playtime >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        return formatter.string(from: playtime) ?? ""
    }

    var lastPlayedText: String {
        lastPlayed.map { $0.formatted(.relative(presentation: .named)) } ?? String(localized: "Never")
    }

    /// "Ren'Py 8.6.1 · Python 3", for cards and the inspector.
    var versionLine: String {
        switch (version, pythonLine) {
        case let (version?, _): String(localized: "Ren'Py \(version.description)")
        case let (nil, line?): String(localized: "Ren'Py version unknown · \(line.title)")
        case (nil, nil): String(localized: "Ren'Py version unknown")
        }
    }
}
