import AppKit
import AppTestKit
import RenChanKit
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots ~/Applications/RenChan.app/Contents/MacOS/RenChan
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=library,runtimes,log limits the pages. Also: "library-list", "library-filtered", "library-empty", "game-details",
/// "runtime-download", "launch-error", "vndb-search", "save-backups", "find-games", "whats-new", "settings".
/// Add APP_ACCENT=<id> to see the pages in another accent.
/// Add APP_SNAPSHOT_MIN=1 to shrink the main window to its smallest size first.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        // Refuses without APP_STORE in /tmp: snapshots never run against the real library.
        guard let run = SnapshotRun.requested(layout: { GridProbes.shared.write(to: $0.path, window: $1) }) else { return }
        Task {
            // The same window every run, whatever size or tiling the person's own RenChan window was saved with.
            await run.start(mainFrame: NSRect(x: 80, y: 80, width: 1080, height: 720))
            await run.shootPages(SidebarItem.allCases.map(\.rawValue)) { model.sidebar = SidebarItem(rawValue: $0) }
            model.sidebar = .library
            await run.shoot("library-list", show: { model.layout = .list }, hide: { model.layout = .grid })
            await run.shoot("game-details", show: { model.showInspector = true }, hide: {})
            // The Language picker sits low in the inspector, so this one scrolls to it.
            await run.shoot("game-language", show: { model.selection = model.games.first { $0.title == "The Question" }?.id; model.showInspector = true; model.inspectorScroll = "language" },
                        hide: { model.inspectorScroll = nil; model.selection = model.games.first?.id })
            await run.shoot("game-mods", show: { model.selection = model.games.count > 1 ? model.games[1].id : nil; model.showInspector = true },
                        hide: { model.selection = model.games.first?.id })
            // Windows of their own: opened, shot in light and dark, closed.
            @MainActor func shootWindow(_ name: String, after wait: Duration, open: @MainActor () -> Void,
                                        find: @MainActor () -> NSWindow?) async {
                guard run.wants(name) else { return }
                open()
                await run.pause(wait)
                let window = find()
                await run.forEachAppearance { look in
                    await run.pause(.seconds(1))
                    if let window { await run.capture(name, look, window: window) }
                }
                window?.close()
            }
            if model.games.count > 1, let walkthrough = model.games[1].walkthroughs.first {
                await shootWindow("walkthrough", after: .seconds(1.5),
                                  open: { model.walkthroughToOpen = WalkthroughRef(game: model.games[1].id, walkthrough: walkthrough.id) },
                                  find: { NSApp.windows.first { $0.title.contains("Walkthrough") && $0.isVisible } })
            }
            if let game = model.games.first(where: { $0.title == "The Question" }) {
                await shootWindow("saves", after: .seconds(3), open: { model.savesToOpen = SavesRef(game: game.id) },
                                  find: { NSApp.windows.first { $0.isVisible && $0.title.contains(game.title) } })
                await shootWindow("gallery", after: .seconds(4), open: { model.galleryToOpen = GalleryRef(game: game.id) },
                                  find: { NSApp.windows.first { $0.isVisible && $0.title.contains(game.title) } })
                await shootWindow("saves-persistent", after: .seconds(3), open: { model.savesToOpen = SavesRef(game: game.id, persistent: true) },
                                  find: { NSApp.windows.first { $0.isVisible && $0.title.contains(game.title) } })
            }
            await run.shoot("library-filtered", show: { model.filter = LibraryFilter(labels: ["Romance"]) }, hide: { model.filter = LibraryFilter() })
            let saved = model.games
            await run.shoot("library-empty", show: { model.games = [] }, hide: { model.games = saved })
            await run.shoot("runtime-download", window: { WindowShot.mainWindow()?.attachedSheet }, show: {
                model.download = DownloadState(version: "7.8.7", received: 61_000_000, total: 148_000_000)
            }, hide: { model.download = nil })
            await run.shoot("launch-error", window: { WindowShot.mainWindow()?.attachedSheet }, show: {
                model.launchError = LaunchFailure(game: saved.first?.id ?? UUID(), title: "Seven Days",
                    text: "I'm sorry, but an uncaught exception occurred.\n\nWhile running game code:\n  File \"game/script.rpy\", line 112, in script\n    $ renpy.pause(hard=True)\nTypeError: pause() got an unexpected keyword argument 'hard'\n",
                    tracebackFile: nil, exactVersion: "6.99.14.3")
            }, hide: { model.launchError = nil })
            await run.shoot("find-games", window: { WindowShot.mainWindow()?.attachedSheet }, show: {
                let home = FileManager.default.homeDirectoryForCurrentUser
                model.findGames = FindGamesState(scanning: false, found: [
                    FoundGame(url: URL(fileURLWithPath: "/Applications/Night Train to Aoi.app"), title: "Night Train to Aoi", version: "8.3.7"),
                    FoundGame(url: home.appending(path: "Games/Starlit_Harbor-1.2-pc"), title: "Starlit Harbor", version: "8.6.1"),
                    FoundGame(url: home.appending(path: "Downloads/The_Bakery_on_Fifth-0.4-pc"), title: "The Bakery on Fifth", version: "7.4.11"),
                ], chosen: [URL(fileURLWithPath: "/Applications/Night Train to Aoi.app"), home.appending(path: "Games/Starlit_Harbor-1.2-pc")],
                places: ["/Applications", "~/Applications", "~/Games", "~/Downloads", "~/Desktop"])
            }, hide: { model.findGames = nil })
            await run.shoot("add-mod", window: { WindowShot.mainWindow()?.attachedSheet }, show: {
                model.addModsTo = ModTarget(files: [URL(fileURLWithPath: "/Users/Shared/0x52_URM.rpa")], game: saved.first?.id)
            }, hide: { model.addModsTo = nil })
            await run.shoot("save-backups", window: { WindowShot.mainWindow()?.attachedSheet }, show: { model.showBackups = saved.first?.id }, hide: { model.showBackups = nil })
            await run.shoot("vndb-search", window: { WindowShot.mainWindow()?.attachedSheet }, show: {
                model.vndbSearch = VNDBSearch(game: saved.first?.id ?? UUID(), query: "The Question", results: [
                    VNDBInfo(id: "v3625", title: "The Question", developer: "ATP Projects", released: "2006-12-03"),
                    VNDBInfo(id: "v31774", title: "The Question", developer: "Little Smug Studio", released: "2020-05-01"),
                    VNDBInfo(id: "v19376", title: "The Question: The Tease", originalTitle: "ザ・クエスチョン", developer: "Forestmaster Games", released: "2012-10-16"),
                ], selection: "v3625", searched: true)
            }, hide: { model.vndbSearch = nil })
            await run.shoot("whats-new", window: { WindowShot.mainWindow()?.attachedSheet },
                            show: { WhatsNewState.shared.shown = .sample }, hide: { WhatsNewState.shared.shown = nil })
            await run.shootSettings(tabs: SettingsTab.allCases.map(\.rawValue), open: { openSettings() },
                                    select: { if let tab = SettingsTab(rawValue: $0) { model.settingsTab = tab } })
            run.finish()
        }
    }
}
