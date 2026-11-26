import AppKit
import FileKit
import Foundation
import LogKit
import LogKitUI
import Observation
import ProcessKit
import RenChanKit
import Synchronization

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
    /// Scrolls the inspector to a row by its id, such as "language" for the snapshots.
    var inspectorScroll: String?

    // MARK: Playing and sheets

    /// Games running now, with their process.
    @ObservationIgnored var processes: [Game.ID: Shell.RunningCommand] = [:]
    @ObservationIgnored var downloadTask: Task<Void, Never>?
    var playing: Set<Game.ID> = [] { didSet { syncMenu() } }
    /// Games whose working copy is being made, before they start.
    var copying: [Game.ID: CopyProgress] = [:] { didSet { syncMenu() } }
    @ObservationIgnored var copyStops: [Game.ID: StopFlag] = [:]
    var download: DownloadState?
    /// Games waiting to play until their Ren'Py is downloaded, in the order Play was pressed.
    var waitingToPlay: [Game.ID] = []
    var launchError: LaunchFailure?
    var confirmRemove: Game.ID?
    var confirmFullCopy: FullCopyRequest?
    var confirmZip: ZipRequest?
    /// The zip being unpacked now, for the sheet that shows it.
    var unpacking: ZipRequest?
    var confirmRemoveRuntime: String?
    var vndbSearch: VNDBSearch?
    /// The game whose Save Backups sheet is open, and the backup waiting for Restore's confirmation.
    var showBackups: Game.ID?
    var confirmRestore: SaveBackup?
    var confirmUpdate: UpdateRequest?
    /// Discover (S-028): the search, releases by VNDB id, and the entry whose download page was opened last.
    var discover = DiscoverState()
    /// The Find Games sheet (S-030).
    var findGames: FindGamesState?
    /// The person's own filters, from Store.filtersFolder (S-016).
    var customFilters: [CustomFilter] = []
    /// Shader errors from running games, while a filter is being changed live.
    var filterErrors: [Game.ID: String] = [:]
    @ObservationIgnored var filterWatch: Task<Void, Never>?
    /// The mod library (S-017).
    var mods: [Mod] = []
    /// The copy each running game plays from.
    var runningCopies: [Game.ID: URL] = [:]
    /// Games the person stopped: their run ends on a signal that isn't an error.
    var stopRequested: Set<Game.ID> = []
    /// A walkthrough window to open from code, such as snapshot mode (S-032).
    var walkthroughToOpen: WalkthroughRef?
    /// Mods opened from the Finder, waiting for their game (S-037).
    var addModsTo: ModTarget?
    /// A Saves window to open (S-035).
    var savesToOpen: SavesRef?
    var galleryToOpen: GalleryRef?
    /// Games whose watched page is being read now (S-033).
    var checkingVersions: Set<Game.ID> = []
    @ObservationIgnored var watchTask: Task<Void, Never>?
    /// Writes library.json a moment after the last change, off the main thread: a big library takes tens of
    /// milliseconds to encode, and a play session or a check of watched pages changes it several times in a row.
    @ObservationIgnored private var librarySaver: DebouncedSaver<[Game]>?
    /// Disk reads the inspector shows, kept until what they depend on changes.
    @ObservationIgnored var memo: [String: (key: Int, value: Any)] = [:]
    /// Bumped when a mod's files may have changed, so the Mods section reads them again.
    var modsRevision = 0
    /// The model, for the app delegate's flush on quit.
    @ObservationIgnored nonisolated(unsafe) static weak var current: AppModel?
    var releases: [String: [VNDBRelease]] = [:]
    var releasesLoading: Set<String> = []
    @ObservationIgnored var cameFromDiscover: (info: VNDBInfo, opened: Date)?
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
        AppModel.current = self
        librarySaver = DebouncedSaver(Self.libraryFile, delay: .milliseconds(400)) { [weak self] error in self?.reportSaveError(error) }
        loadLibrary()
        recoverSessions()
        startWatchChecks()
        customFilters = CustomFilters.list(in: Store.filtersFolder)
        mods = ModLibrary.load(Store.modsFolder)
        if !OpenQueue.pending.isEmpty {
            let urls = OpenQueue.pending
            OpenQueue.pending = []
            Task { @MainActor in self.open(urls) }
        }
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

    /// library.json, in the test store during a test run.
    static var libraryFile: JSONFile<[Game]> { JSONFile(Store.url, dates: .iso8601) }

    func loadLibrary() {
        flushLibrary()
        do {
            games = try Self.libraryFile.load(setAsideDamaged: true) ?? []
        } catch let damaged as JSONFile<[Game]>.Damaged {
            // Kept aside, so the next save can't write over the person's games.
            let kept = damaged.keptAt?.lastPathComponent
            log.post(.error, "Couldn't read the library at \(Store.url.path): \(damaged.reason)\(kept.map { "; kept it as \($0)" } ?? "")", source: "Library")
            notice = kept.map { String(localized: "RenChan couldn't read its library, so it kept it aside as “\($0)” and started a new one.") }
                ?? String(localized: "RenChan couldn't read its library: \(damaged.reason)")
        } catch {
            log.post(.error, "Couldn't read the library at \(Store.url.path): \(error.localizedDescription)", source: "Library")
        }
        runtimes = runtimeStore.installed()
        detectMissingVersions()
        upgradeCovers()
    }

    /// Covers from before 0.9 were kept as downloaded; they become HEIC at most 1200 px, once, off the main thread.
    private func upgradeCovers() {
        let bases = games.map { Store.coverBase($0.id) }
        Task {
            let (count, saved) = await Task.detached(priority: .utility) {
                bases.reduce((0, Int64(0))) { total, base in Covers.upgrade(base: base).map { (total.0 + 1, total.1 + $0) } ?? total }
            }.value
            if count > 0 {
                log.post(.info, "Stored \(count) covers as HEIC, \(ByteCountFormatter.string(fromByteCount: saved, countStyle: .file)) smaller", source: "Library")
            }
        }
    }

    /// S-033: games added before 0.6.0 get their own version read, off the main thread: it reads up to 60
    /// scripts a game, and a game with no version to find is read again at each launch.
    private func detectMissingVersions() {
        let missing = games.filter { $0.gameVersion == nil }.map { ($0.id, $0.baseURL, $0.sourceURL) }
        guard !missing.isEmpty else { return }
        Task {
            let found = await Task.detached(priority: .utility) {
                missing.compactMap { id, base, source in GameVersion.detect(base: base, source: source).map { (id, $0) } }
            }.value
            for (id, version) in found where game(id)?.gameVersion == nil { update(id) { $0.gameVersion = version } }
        }
    }

    /// Writes the library a moment after the last change (librarySaver).
    func saveLibrary() {
        librarySaver?.schedule(games)
    }

    /// Writes now, on this thread: before quitting, and before reading the file again.
    /// A save already running finishes first, so no older save can land after this one.
    func flushLibrary() {
        do { try librarySaver?.finish() } catch { reportSaveError(error) }
    }

    private func reportSaveError(_ error: any Error) {
        log.post(.error, "Couldn't save the library: \(error.localizedDescription)", source: "Library")
        notice = String(localized: "RenChan couldn't save the library: \(error.localizedDescription)")
    }

    func update(_ id: Game.ID, _ change: (inout Game) -> Void) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        change(&games[index])
        saveLibrary()
    }

    /// A value read from disk, kept while key stays the same.
    func memoized<T>(_ name: String, key: Int, _ make: () -> T) -> T {
        if let hit = memo[name], hit.key == key, let value = hit.value as? T { return value }
        let value = make()
        memo[name] = (key, value)
        return value
    }

    private func syncMenu() {
        MenuState.shared.selection = selection
        // Copying counts as playing: Play waits, and Stop (Command-Period) cancels the copy.
        MenuState.shared.selectionPlaying = selection.map { playing.contains($0) || copying[$0] != nil } ?? false
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

/// A working copy being made: a clone (no size to show) or a full copy, with bytes copied so far.
struct CopyProgress: Equatable {
    var total: Int64
    var copied: Int64 = 0
    var full: Bool

    var fraction: Double? { full && total > 0 ? min(Double(copied) / Double(total), 1) : nil }
}

/// Set from the main thread, read by a copy running elsewhere.
nonisolated final class StopFlag: Sendable {
    private let value = Mutex(false)
    func set() { value.withLock { $0 = true } }
    var isSet: Bool { value.withLock { $0 } }
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
    case library, discover, runtimes, log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: String(localized: "Library")
        case .discover: String(localized: "Discover")
        case .runtimes: String(localized: "Runtimes")
        case .log: String(localized: "Log")
        }
    }

    var symbol: String {
        switch self {
        case .library: "books.vertical"
        case .discover: "sparkle.magnifyingglass"
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
        case .notAZip(let size): String(localized: "This file isn't a zip, only \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) of text: often a download link that expired. Download the game again.")
        }
    }
}
