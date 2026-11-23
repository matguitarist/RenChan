import AppKit
import Foundation
import LogKit
import LogKitUI
import Observation
import RenChanKit

/// The app's state: the library, runtimes, what is selected and playing, and the open sheets.
/// Actions live in Models+Library.swift and Models+Play.swift.
@Observable
final class AppModel {
    let log: LogStore
    /// The Log page's viewer; kept here so its filters survive moving between pages.
    let logViewer: LogViewerModel

    var sidebar: SidebarItem? = .library
    var settingsTab: SettingsTab = .general

    // MARK: Library

    var games: [Game] = []
    var runtimes: [Runtime] = []
    var selection: Game.ID? { didSet { syncMenu() } }
    var search = ""
    var filter = LibraryFilter()
    var sort: LibrarySort = LibrarySort(rawValue: UserDefaults.standard.string(forKey: "library.sort") ?? "") ?? .title {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "library.sort") }
    }
    var layout: LibraryLayout = LibraryLayout(rawValue: UserDefaults.standard.string(forKey: "library.layout") ?? "") ?? .grid {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: "library.layout") }
    }
    var showInspector = true

    // MARK: Playing and sheets

    /// Games running now, with their process.
    @ObservationIgnored var processes: [Game.ID: Process] = [:]
    @ObservationIgnored var downloadTask: Task<Void, Never>?
    var playing: Set<Game.ID> = [] { didSet { syncMenu() } }
    var download: DownloadState?
    var launchError: LaunchFailure?
    var confirmRemove: Game.ID?
    var confirmFullCopy: FullCopyRequest?
    var confirmZip: ZipRequest?
    var confirmRemoveRuntime: String?
    var vndbSearch: VNDBSearch?
    /// Bumped when a cover file changes, so covers redraw.
    var coverRevision = 0
    /// The game whose Save Backups sheet is open, and the backup waiting for Restore's confirmation.
    var showBackups: Game.ID?
    var confirmRestore: SaveBackup?
    /// Bumped when backups change on disk, so lists reload.
    var backupRevision = 0
    /// One-line message in an alert.
    var notice: String?

    var language: AppLanguage = .current {
        didSet { language.apply() }
    }

    var checksForUpdates: Bool {
        get { Updater.shared.automaticallyChecks }
        set { Updater.shared.automaticallyChecks = newValue }
    }

    init(log: LogStore) {
        self.log = log
        logViewer = LogViewerModel(store: log)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        log.post(.info, "RenChan \(version) started", source: "App")
        loadLibrary()
        recoverSessions()
    }

    var runtimeStore: RuntimeStore { RuntimeStore(folder: Store.runtimesFolder) }

    func game(_ id: Game.ID?) -> Game? {
        guard let id else { return nil }
        return games.first { $0.id == id }
    }

    var selectedGame: Game? { game(selection) }

    /// Every label in the library, for the filter and suggestions.
    var allLabels: [String] { Labels.all(in: games) }

    /// The library after search, filter and sort.
    var shownGames: [Game] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let found = games.filter { (query.isEmpty || $0.title.localizedStandardContains(query)) && filter.matches($0) }
        switch sort {
        case .title: return found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .added: return found.sorted { $0.added > $1.added }
        case .lastPlayed: return found.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
        case .playtime: return found.sorted { $0.playtime > $1.playtime }
        }
    }

    func loadLibrary() {
        do {
            games = try LibraryFile.load(Store.url)
        } catch {
            log.post(.error, "Couldn't read the library at \(Store.url.path): \(error.localizedDescription)", source: "Library")
        }
        runtimes = runtimeStore.installed()
    }

    func saveLibrary() {
        do {
            try LibraryFile.save(games, to: Store.url)
        } catch {
            log.post(.error, "Couldn't save the library: \(error.localizedDescription)", source: "Library")
            notice = String(localized: "RenChan couldn't save the library: \(error.localizedDescription)")
        }
    }

    func update(_ id: Game.ID, _ change: (inout Game) -> Void) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        change(&games[index])
        saveLibrary()
    }

    private func syncMenu() {
        MenuState.shared.selection = selection
        MenuState.shared.selectionPlaying = selection.map { playing.contains($0) } ?? false
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case title, added, lastPlayed, playtime
    var id: String { rawValue }
    var title: String {
        switch self {
        case .title: String(localized: "Title")
        case .added: String(localized: "Date Added")
        case .lastPlayed: String(localized: "Last Played")
        case .playtime: String(localized: "Playtime")
        }
    }
}

enum LibraryLayout: String, CaseIterable, Identifiable {
    case grid, list
    var id: String { rawValue }
}

struct DownloadState: Equatable {
    var version: String
    var received: Int64 = 0
    var total: Int64?
    /// The game to play once it's installed.
    var then: Game.ID?
}

struct LaunchFailure: Identifiable, Equatable {
    let id = UUID()
    var game: Game.ID
    var title: String
    var text: String
    var tracebackFile: URL?
    /// The game's exact Ren'Py version, offered when it differs from the runtime that failed.
    var exactVersion: String?
}

struct FullCopyRequest: Identifiable, Equatable {
    var id: Game.ID
    var size: Int64
}

struct ZipRequest: Identifiable, Equatable {
    var id: URL { url }
    var url: URL
    var size: Int64?
}

/// The menu bar's view of the selection. Commands don't observe @Observable models (swift-code).
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var selection: UUID?
    @Published var selectionPlaying = false
}

/// The sidebar's pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case library, runtimes, log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: String(localized: "Library")
        case .runtimes: String(localized: "Runtimes")
        case .log: String(localized: "Log")
        }
    }

    var symbol: String {
        switch self {
        case .library: "books.vertical"
        case .runtimes: "shippingbox"
        case .log: "list.bullet.rectangle"
        }
    }
}

extension LocateError {
    var message: String {
        switch self {
        case .noGameFolder: String(localized: "This isn't a Ren'Py game: there is no game folder in it.")
        case .noScripts: String(localized: "This isn't a Ren'Py game: its game folder has no Ren'Py scripts.")
        case .unsafeZip(let entry): String(localized: "This zip was refused: it would write outside its folder (\(entry)).")
        case .unzipFailed(let reason): String(localized: "This zip couldn't be opened: \(reason)")
        }
    }
}
