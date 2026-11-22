import AppKit
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
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.isAvailable)
            }
            CommandGroup(replacing: .help) {
                Link("RenChan on GitHub", destination: URL(string: "https://github.com/matguitarist/RenChan")!)
            }
        }

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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        Store.log.flushFile()
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the library lives: ~/Library/Application Support/RenChan/library.json.
/// With APP_STORE set (tests, snapshots, self-test), a library at that path in /tmp instead.
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, self-test).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var folder: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "RenChan", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return folder.appending(path: "library.json")
    }

    /// ~/Library/Logs/RenChan/RenChan.log, or next to APP_STORE in a test run.
    static var logURL: URL {
        isOverridden ? url.deletingPathExtension().appendingPathExtension("log")
                     : LogStore.defaultFileURL(app: "RenChan")
    }

    static let log = LogStore(fileURL: logURL)
}
