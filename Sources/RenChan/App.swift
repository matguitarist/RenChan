import AppKit
import AppTestKit
import LogKit
import SwiftUI
import RenChanKit

// RenChan
//   RenChan                          the app, with its library in ~/Library/Application Support/RenChan
//   APP_STORE=<file> RenChan         a library at <file> in /tmp, with its log next to it; tests and snapshots
//   APP_SNAPSHOT=<dir> RenChan       save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 RenChan               with APP_STORE: seed data for snapshots (tools/snap.sh)
//   RenChan --selftest               run the self-test on a /tmp library and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> RenChan          run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 RenChan               draw the 8 pt grid and the layout probes over the window

@main
struct RenChanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(log: Store.log)
    @ObservedObject private var menu = MenuState.shared

    var body: some Scene {
        Window("RenChan", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            ToolbarCommands()
            InspectorCommands()
            CommandGroup(replacing: .newItem) {
                Button("Add Game…") { model.addWithPanel() }
                    .keyboardShortcut("o")
                Button("Find Games on This Mac…") { model.sidebar = .library; model.findGames() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Import from F95Checker…") { model.sidebar = .library; model.importF95Checker() }
                Divider()
                Button("Export Compatibility Report…") { model.exportCompatibilityReport() }
                Button("Copy Compatibility Report") { model.copyCompatibilityReport() }
            }
            CommandGroup(after: .sidebar) {
                Button("as Grid") { model.sidebar = .library; model.layout = .grid }
                    .keyboardShortcut("1")
                Button("as List") { model.sidebar = .library; model.layout = .list }
                    .keyboardShortcut("2")
                Divider()
            }
            CommandMenu("Game") {
                Button("Play") { if let id = menu.selection { model.play(id) } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(menu.selection == nil || menu.selectionPlaying)
                Button("Stop") { if let id = menu.selection { model.stop(id) } }
                    .keyboardShortcut(".")
                    .disabled(!menu.selectionPlaying)
                Divider()
                Button("Show in Finder") { if let id = menu.selection { model.showInFinder(id) } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(menu.selection == nil)
                Button("Open Saves Folder") { if let id = menu.selection { model.openSaves(id) } }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                    .disabled(menu.selection == nil)
                Button("Back Up Saves") { if let id = menu.selection { model.backUpSaves(id) } }
                    .keyboardShortcut("b", modifiers: [.command, .option])
                    .disabled(menu.selection == nil)
                Button("Save Backups…") { model.showBackups = menu.selection }
                    .disabled(menu.selection == nil)
                Button("Browse Saves…") { if let id = menu.selection { model.showSaves(id) } }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(menu.selection == nil)
                Button("Gallery…") { if let id = menu.selection { model.showGallery(id) } }
                    .keyboardShortcut("g", modifiers: [.command, .option])
                    .disabled(menu.selection == nil)
                ShowWalkthroughButton(model: model, selection: menu.selection)
                Divider()
                Button("Update to New Version…") { if let id = menu.selection { model.chooseUpdate(id) } }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                    .disabled(menu.selection == nil || menu.selectionPlaying)
                Button("Check All for New Versions") { model.checkForNewVersions(force: true) }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Find on VNDB…") { if let id = menu.selection { model.findOnVNDB(id) } }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(menu.selection == nil)
                Divider()
                Button("Remove from Library…") { model.confirmRemove = menu.selection }
                    .disabled(menu.selection == nil)
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.isAvailable)
            }
            CommandGroup(replacing: .help) {
                Link("RenChan on GitHub", destination: URL(string: "https://github.com/matguitarist/RenChan")!)
            }
        }

        WindowGroup("Walkthrough", id: "walkthrough", for: WalkthroughRef.self) { $ref in
            Group {
                if let ref {
                    WalkthroughWindow(ref: ref)
                } else {
                    ContentUnavailableView("No Walkthrough", systemImage: "book.closed")
                        .frame(minWidth: 380, minHeight: 420)
                }
            }
            .environment(model)
            .themed()
        }
        .defaultSize(width: 560, height: 760)

        WindowGroup("Gallery", id: "gallery", for: GalleryRef.self) { $ref in
            Group {
                if let ref {
                    GalleryWindow(ref: ref)
                } else {
                    ContentUnavailableView("No Pictures", systemImage: "photo")
                }
            }
            .frame(minWidth: 720, minHeight: 480)
            .environment(model)
            .themed()
        }
        .defaultSize(width: 1000, height: 700)

        WindowGroup("Saves", id: "saves", for: SavesRef.self) { $ref in
            Group {
                if let ref {
                    SavesWindow(ref: ref)
                } else {
                    ContentUnavailableView("No Saves", systemImage: "tray")
                }
            }
            .frame(minWidth: 720, minHeight: 480)
            .environment(model)
            .themed()
        }
        .defaultSize(width: 900, height: 640)

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        _ = Updater.shared
    }

    /// S-037: files opened from the Finder or dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            if let model = AppModel.current { model.open(urls) } else { OpenQueue.pending += urls }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.current?.flushLibrary() }
        Store.log.flushFile()
        SelfTest.exitIfRequested()
    }
}

/// Where the library lives: ~/Library/Application Support/RenChan/library.json.
/// With APP_STORE set (tests, snapshots, self-test), a library at that path in /tmp instead.
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, self-test). The shared Updater and
    /// AppLanguage read it.
    static var isOverridden: Bool { TestRun.isTestRun() }

    static var folder: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "RenChan", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// An APP_STORE outside /tmp quits at once, before anything is read or written.
    static let url: URL = TestRun.store() ?? folder.appending(path: "library.json")

    /// ~/Library/Logs/RenChan/RenChan.log, or next to APP_STORE in a test run.
    static var logURL: URL {
        isOverridden ? url.deletingPathExtension().appendingPathExtension("log")
                     : LogStore.defaultFileURL(app: "RenChan")
    }

    static let log = LogStore(fileURL: logURL)

    /// Working copies, unpacked zips and runtimes: next to library.json, or next to APP_STORE in a test run.
    static var dataFolder: URL {
        isOverridden ? url.deletingLastPathComponent().appending(path: url.deletingPathExtension().lastPathComponent + "-data", directoryHint: .isDirectory)
                     : folder
    }

    static var runtimesFolder: URL { dataFolder.appending(path: "Runtimes", directoryHint: .isDirectory) }

    /// One folder per game: play/ (the working copy), source/ (an unpacked zip), run.log.
    static func gameFolder(_ id: UUID) -> URL { dataFolder.appending(path: "Games/\(id.uuidString)", directoryHint: .isDirectory) }
    static func workingCopy(_ id: UUID) -> URL { gameFolder(id).appending(path: "play", directoryHint: .isDirectory) }
    /// A second clone, for play with mods on, so mods never touch the plain copy or its game/saves (S-018, S-020).
    static func moddedCopy(_ id: UUID) -> URL { gameFolder(id).appending(path: "play-modded", directoryHint: .isDirectory) }
    /// Where modded play keeps its saves, through RENPY_PATH_TO_SAVES (S-020).
    static func moddedSaves(_ id: UUID) -> URL { gameFolder(id).appending(path: "Modded Saves", directoryHint: .isDirectory) }
    /// A game's walkthroughs (S-032). Removed with the game.
    static func walkthroughsFolder(_ id: UUID) -> URL { gameFolder(id).appending(path: "Walkthroughs", directoryHint: .isDirectory) }
    /// The mod library (S-017).
    static var modsFolder: URL { dataFolder.appending(path: "Mods", directoryHint: .isDirectory) }
    /// The person's own .glsl filters (S-016).
    static var filtersFolder: URL { dataFolder.appending(path: "Filters", directoryHint: .isDirectory) }
    /// Save backups, one folder per game. Kept when a game is removed (S-012).
    static func backupsFolder(_ id: UUID) -> URL { dataFolder.appending(path: "Backups/\(id.uuidString)", directoryHint: .isDirectory) }
    /// The cover from VNDB or one the person chose (S-010).
    /// The game's cover without its extension (Covers).
    static func coverBase(_ id: UUID) -> URL { gameFolder(id).appending(path: "cover") }
    /// The game's cover file, whatever its format; nil when it has none.
    static func coverFile(_ id: UUID) -> URL? { Covers.find(base: coverBase(id)) }
    /// Written while a game plays, for its playtime (S-009).
    static func sessionFile(_ id: UUID) -> URL { gameFolder(id).appending(path: "session.json") }

    /// The home Ren'Py writes ~/Library/RenPy under: the real one, or a folder in /tmp in a test run.
    static var renpyHome: URL {
        isOverridden ? dataFolder.appending(path: "home", directoryHint: .isDirectory) : FileManager.default.homeDirectoryForCurrentUser
    }

    static var saveRoot: URL { SaveFolder.root(home: renpyHome) }
}
