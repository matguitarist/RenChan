import AppKit
import IOKit.pwr_mgt
import ProcessKit
import RenChanKit
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots ~/Applications/RenChan.app/Contents/MacOS/RenChan
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=library,runtimes,log limits the pages. Also: "library-list", "library-filtered", "library-empty", "game-details",
/// "runtime-download", "launch-error", "vndb-search", "save-backups", "find-games", "settings".
/// Add APP_ACCENT=<id> to see the pages in another accent.
/// Add APP_SNAPSHOT_MIN=1 to shrink the main window to its smallest size first.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real library.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            // The same window every run, whatever size or tiling the person's own RenChan window was saved with.
            if let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) {
                main.setFrameAutosaveName("")
                main.setFrame(NSRect(x: 80, y: 80, width: 1080, height: 720), display: true)
                try? await Task.sleep(for: .seconds(0.5))
            }
            if env["APP_SNAPSHOT_MIN"] != nil, let main = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) {
                // The window clamps to its content's minimum size.
                main.setContentSize(NSSize(width: 1, height: 1))
                try? await Task.sleep(for: .seconds(0.5))
            }
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in SidebarItem.allCases where only?.contains(page.rawValue) ?? true {
                    model.sidebar = page
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                }
            }
            let main = { @MainActor in NSApp.windows.first { $0.canBecomeMain && !$0.isSheet } }
            @MainActor func shoot(_ name: String, sheet: Bool = false, _ show: @MainActor () -> Void, _ hide: @MainActor () -> Void) async {
                guard only == nil || only?.contains(name) == true else { return }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    show()
                    try? await Task.sleep(for: .seconds(1))
                    capture(to: "\(dir)/\(name)-\(mode).png", window: sheet ? main()?.attachedSheet : nil)
                    hide()
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }
            model.sidebar = .library
            await shoot("library-list", { model.layout = .list }, { model.layout = .grid })
            await shoot("game-details", { model.showInspector = true }, {})
            // The Language picker sits low in the inspector, so this one scrolls to it.
            await shoot("game-language", { model.selection = model.games.first { $0.title == "The Question" }?.id; model.showInspector = true; model.inspectorScroll = "language" },
                        { model.inspectorScroll = nil; model.selection = model.games.first?.id })
            await shoot("game-mods", { model.selection = model.games.count > 1 ? model.games[1].id : nil; model.showInspector = true },
                        { model.selection = model.games.first?.id })
            if only == nil || only?.contains("walkthrough") == true, model.games.count > 1, let walkthrough = model.games[1].walkthroughs.first {
                model.walkthroughToOpen = WalkthroughRef(game: model.games[1].id, walkthrough: walkthrough.id)
                try? await Task.sleep(for: .seconds(1.5))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(1))
                    if let window = NSApp.windows.first(where: { $0.title.contains("Walkthrough") && $0.isVisible }) {
                        capture(to: "\(dir)/walkthrough-\(mode).png", window: window)
                    }
                }
                NSApp.windows.first { $0.title.contains("Walkthrough") }?.close()
            }
            if only == nil || only?.contains("saves") == true, let game = model.games.first(where: { $0.title == "The Question" }) {
                model.savesToOpen = SavesRef(game: game.id)
                try? await Task.sleep(for: .seconds(3))
                let window = NSApp.windows.first { $0.isVisible && $0.title.contains(game.title) }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(1))
                    if let window { capture(to: "\(dir)/saves-\(mode).png", window: window) }
                }
                window?.close()
            }
            if only == nil || only?.contains("gallery") == true, let game = model.games.first(where: { $0.title == "The Question" }) {
                model.galleryToOpen = GalleryRef(game: game.id)
                try? await Task.sleep(for: .seconds(4))
                let window = NSApp.windows.first { $0.isVisible && $0.title.contains(game.title) }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(1))
                    if let window { capture(to: "\(dir)/gallery-\(mode).png", window: window) }
                }
                window?.close()
            }
            if only == nil || only?.contains("saves-persistent") == true, let game = model.games.first(where: { $0.title == "The Question" }) {
                model.savesToOpen = SavesRef(game: game.id, persistent: true)
                try? await Task.sleep(for: .seconds(3))
                let window = NSApp.windows.first { $0.isVisible && $0.title.contains(game.title) }
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    try? await Task.sleep(for: .seconds(1))
                    if let window { capture(to: "\(dir)/saves-persistent-\(mode).png", window: window) }
                }
                window?.close()
            }
            await shoot("library-filtered", { model.filter = LibraryFilter(labels: ["Romance"]) }, { model.filter = LibraryFilter() })
            let saved = model.games
            await shoot("library-empty", { model.games = [] }, { model.games = saved })
            await shoot("runtime-download", sheet: true, {
                model.download = DownloadState(version: "7.8.7", received: 61_000_000, total: 148_000_000)
            }, { model.download = nil })
            await shoot("launch-error", sheet: true, {
                model.launchError = LaunchFailure(game: saved.first?.id ?? UUID(), title: "Seven Days",
                    text: "I'm sorry, but an uncaught exception occurred.\n\nWhile running game code:\n  File \"game/script.rpy\", line 112, in script\n    $ renpy.pause(hard=True)\nTypeError: pause() got an unexpected keyword argument 'hard'\n",
                    tracebackFile: nil, exactVersion: "6.99.14.3")
            }, { model.launchError = nil })
            await shoot("find-games", sheet: true, {
                let home = FileManager.default.homeDirectoryForCurrentUser
                model.findGames = FindGamesState(scanning: false, found: [
                    FoundGame(url: URL(fileURLWithPath: "/Applications/Night Train to Aoi.app"), title: "Night Train to Aoi", version: "8.3.7"),
                    FoundGame(url: home.appending(path: "Games/Starlit_Harbor-1.2-pc"), title: "Starlit Harbor", version: "8.6.1"),
                    FoundGame(url: home.appending(path: "Downloads/The_Bakery_on_Fifth-0.4-pc"), title: "The Bakery on Fifth", version: "7.4.11"),
                ], chosen: [URL(fileURLWithPath: "/Applications/Night Train to Aoi.app"), home.appending(path: "Games/Starlit_Harbor-1.2-pc")],
                places: ["/Applications", "~/Applications", "~/Games", "~/Downloads", "~/Desktop"])
            }, { model.findGames = nil })
            await shoot("add-mod", sheet: true, {
                model.addModsTo = ModTarget(files: [URL(fileURLWithPath: "/Users/Shared/0x52_URM.rpa")], game: saved.first?.id)
            }, { model.addModsTo = nil })
            await shoot("save-backups", sheet: true, { model.showBackups = saved.first?.id }, { model.showBackups = nil })
            await shoot("vndb-search", sheet: true, {
                model.vndbSearch = VNDBSearch(game: saved.first?.id ?? UUID(), query: "The Question", results: [
                    VNDBInfo(id: "v3625", title: "The Question", developer: "ATP Projects", released: "2006-12-03"),
                    VNDBInfo(id: "v31774", title: "The Question", developer: "Little Smug Studio", released: "2020-05-01"),
                    VNDBInfo(id: "v19376", title: "The Question: The Tease", originalTitle: "ザ・クエスチョン", developer: "Forestmaster Games", released: "2012-10-16"),
                ], selection: "v3625", searched: true)
            }, { model.vndbSearch = nil })
            if only == nil || only?.contains("settings") == true {
                let main = main()
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    private static func capture(to path: String, window: NSWindow? = nil) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            _ = try? Shell.runSync("/usr/sbin/screencapture", ["-x", "-o", "-l", String(window.windowNumber), path])
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}

