import AppKit
import AppTestKit
import Foundation
import ProcessKit
import RenChanKit

/// The self-test's checks from M3 on, split out of SelfTest.swift. Each takes what the earlier checks made.
extension SelfTest {
    /// S-028 to S-030. Returns the shelf folder outside RenChan's data, where later checks put games.
    static func discoverChecks(_ model: AppModel, root: URL) async -> URL {
        // S-028 Discover: a game added after opening its download page gets that VNDB entry, and only that game
        let starlit = VNDBInfo(id: "v90001", title: "Starlit Harbor")
        model.cameFromDiscover = (starlit, .now)
        let other = model.addFolder(Fixtures.game("Moon_Garden-1.0-pc", in: root, files: [:]))
        check("S-028 a game with another title isn't linked", other.map { model.game($0.id)?.vndb == nil } == true)
        let downloaded = model.addFolder(Fixtures.game("Starlit_Harbor-1.2-pc", in: root, files: [:]))
        check("S-028 the game added after Discover is linked to its VNDB entry",
              downloaded.map { model.game($0.id)?.vndb?.id == "v90001" } == true && model.cameFromDiscover == nil)
        check("S-028 Discover sees it in the library", model.libraryGame(vndb: "v90001")?.title == "Starlit Harbor 1.2")
        model.releases["v90001"] = [VNDBRelease(id: "r1", title: "Starlit Harbor", official: true,
                                                links: [VNDBRelease.Link(label: "Itch.io", url: URL(string: "https://example.itch.io/a")!)]),
                                    VNDBRelease(id: "r2", title: "Fan", official: false,
                                                links: [VNDBRelease.Link(label: "Fan site", url: URL(string: "https://example.org/fan")!)])]
        check("S-029 Get It lists the official download pages only", model.downloadLinks("v90001").map(\.label) == ["Itch.io"])

        // S-030 Find games on this Mac: only games not in the library, never RenChan's own copies
        // Outside RenChan's data folder, which the scan skips.
        let shelf = Store.url.deletingLastPathComponent().appending(path: "RenChan-self-shelf", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: shelf)
        Fixtures.game("Lantern_Night-1.0-pc", in: shelf, files: ["renpy/__init__.py": ""])
        Fixtures.game("Old Letters.app/Contents/Resources/autorun", in: shelf, files: [:])
        model.findGames(in: [shelf, Store.dataFolder])
        for _ in 0..<50 where model.findGames?.scanning == true { try? await Task.sleep(for: .milliseconds(100)) }
        check("S-030 finds a game folder and a Mac build on this Mac",
              model.findGames?.found.map(\.title).sorted() == ["Lantern Night 1.0", "Old Letters"], "\(model.findGames?.found.map(\.title) ?? [])")
        let before030 = model.games.count
        let lantern = Set(model.findGames?.found.filter { $0.title == "Lantern Night 1.0" }.map(\.url) ?? [])
        model.findGames?.chosen = lantern
        model.addFoundGames()
        check("S-030 Add Games adds only the chosen ones", model.games.count == before030 + 1 && model.findGames == nil)
        return shelf
    }

    /// S-035 Browse saves, S-036 change a save's variables, S-042 the gallery.
    static func savesChecks(_ model: AppModel, first: Game) async {
        // S-035 Browse saves, S-036 change a save's variables (the pretend runtime stands in for Ren'Py)
        if let folder = model.savesFolder(model.game(first.id)!, modded: false) {
            Fixtures.save("1-2", name: "At the bridge", minutesAgo: 5, color: .systemPink, in: folder)
            Fixtures.save("quick-1", name: "", minutesAgo: 60, color: .systemBlue, in: folder)
            let listed = SaveList.list(in: folder)
            check("S-035 saves are listed newest first with their name and picture",
                  listed.first?.slot == "1-2" && listed.first?.name == "At the bridge" && listed.first?.screenshot() != nil
                  && listed.contains { $0.place == "Quick 1" }, "\(listed.map(\.slot))")
            if let game = model.game(first.id) {
                for root in [game.baseURL, Store.workingCopy(game.id)] {
                    for (index, path) in ["images/cg/a.png", "images/cg/b.png", "images/bg/c.png", "images/bg/d.png",
                                          "images/e.png", "images/f.png", "images/g.png", "gui/button/idle.png"].enumerated() {
                        Fixtures.picture(index.isMultiple(of: 2) ? .systemPink : .systemTeal, to: root.appending(path: "game/\(path)"), size: NSSize(width: 32, height: 16))
                    }
                }
                let pictures = (try? await model.readPictures(of: game)) ?? []
                check("the gallery lists the game's pictures and hides interface ones by default",
                      pictures.count == 8 && pictures.filter { !$0.isInterface }.count == 7, "\(pictures.map(\.path))")
                let kept = await model.cachedPictures(of: game)
                check("the gallery keeps its list and reads a picture's bytes",
                      kept?.count == 8 && pictures.first.flatMap { $0.thumbnail(maxPixels: 64) } != nil)
            }
            if let game = model.game(first.id), listed.count > 1 {
                let all = try? await model.writeVariables(["met_aoi": false], in: listed, of: game, modded: false)
                let sent = (try? String(contentsOf: Store.workingCopy(first.id).appending(path: "renchan_last_changes.json"), encoding: .utf8)) ?? ""
                let slots = (try? String(contentsOf: Store.workingCopy(first.id).appending(path: "renchan_last_slots"), encoding: .utf8)) ?? ""
                check("Save to All Saves sends one change for every save", all != nil && sent == #"{"met_aoi":false}"#
                      && Set(slots.split(separator: ",").map(String.init)) == Set(listed.map(\.slot)), "\(sent) \(slots)")
                model.togglePin("affection_mei", in: first.id)
                check("a pinned variable is kept with the game", model.game(first.id)?.pinnedVariables == ["affection_mei"])
                model.togglePin("affection_mei", in: first.id)
            }
            if let save = listed.first, let game = model.game(first.id) {
                let variables = (try? await model.readVariables(save, of: game, modded: false)) ?? []
                check("S-036 a save's variables are read with the game's Ren'Py",
                      variables.map(\.name) == ["affection_mei", "bag", "chapter", "hero", "met_aoi"] && variables[1].editable == false)
                let backupsBefore = model.backups(first.id).filter { $0.reason == .beforeEdit }.count
                let changed = (try? await model.writeVariables(["affection_mei": 30], in: save, of: game, modded: false)) ?? []
                let sent = (try? String(contentsOf: Store.workingCopy(first.id).appending(path: "renchan_last_changes.json"), encoding: .utf8)) ?? ""
                check("S-036 a change is backed up first, then written", changed == ["affection_mei"] && sent == #"{"affection_mei":30}"#
                      && model.backups(first.id).filter { $0.reason == .beforeEdit }.count == backupsBefore + 1, sent)
            }
        } else {
            check("S-035 the game knows its saves folder", false)
        }
    }

    /// S-033 new versions on a watched page, S-034 import from F95Checker.
    static func watchAndImportChecks(_ model: AppModel, first: Game, shelf: URL) async {
        // S-033 Know when a new version is out (a page on disk stands in for itch.io)
        let page = shelf.appending(path: "itch-page.html")
        try? #"<div class="upload_name"><strong class="name" title="The Question - [9.9] - PC">The Question - [9.9] - PC</strong></div>"#.write(to: page, atomically: true, encoding: .utf8)
        check("S-033 only itch.io pages and F95zone threads are watched", !model.setWatch("https://example.com/game", for: first.id) && model.notice != nil)
        model.notice = nil
        model.update(first.id) { $0.gameVersion = "6.99"; $0.watch = UpdateWatch(page: page.absoluteString) }
        model.checkNewVersion(first.id)
        for _ in 0..<50 where model.game(first.id)?.watch?.checked == nil { try? await Task.sleep(for: .milliseconds(100)) }
        check("S-033 a newer version on the page shows on the game", model.game(first.id)?.newVersion == "9.9", "\(String(describing: model.game(first.id)?.watch))")
        model.dismissNewVersion(first.id)
        check("S-033 Dismiss hides that version", model.game(first.id)?.newVersion == nil && model.game(first.id)?.watch?.latest == "9.9")
        model.stopWatching(first.id)

        // S-034 Import from F95Checker: games on this Mac are listed with their thread; the database isn't changed
        Fixtures.game("Night_Ferry-0.3-pc", in: shelf, files: ["renpy/__init__.py": ""])
        let db = shelf.appending(path: "db.sqlite3")
        _ = try? Shell.runSync("/usr/bin/sqlite3", [db.path, """
            CREATE TABLE games (id INTEGER PRIMARY KEY, name TEXT, version TEXT, executables TEXT);
            INSERT INTO games VALUES (4242, 'Night Ferry', 'v0.3', '["\(shelf.path)/Night_Ferry-0.3-pc/NightFerry.exe"]');
            INSERT INTO games VALUES (77, 'Far Away', '1.0', '["/Volumes/Nowhere/FarAway/FarAway.exe"]');
            """])
        let dbBefore = try? Data(contentsOf: db)
        model.importF95Checker(database: db)
        check("S-034 lists F95Checker's games that are on this Mac",
              model.findGames?.found.map(\.title) == ["Night Ferry"] && model.findGames?.notOnThisMac == 1, "\(String(describing: model.findGames))")
        model.addFoundGames()
        let ferry = model.games.first { $0.sourcePath.hasSuffix("Night_Ferry-0.3-pc") }
        check("S-034 an imported game watches its F95zone thread",
              ferry?.watch?.page == "https://f95zone.to/threads/4242/" && ferry?.gameVersion == "0.3" && (try? Data(contentsOf: db)) == dbBefore)
        model.watchTask?.cancel()
        model.watchTask = nil
    }

    /// S-037 to S-040: open from the Finder, back up before play, language, persistent data.
    static func newChecks(_ model: AppModel, first: Game, shelf: URL) async {
        // S-037 Open from the Finder and the Dock
        let owl = Fixtures.game("Night_Owl-1.0-pc", in: shelf, files: ["renpy/__init__.py": "", "game/options.rpy": Fixtures.options(name: "Night Owl", saves: "night-owl")])
        let countBefore = model.games.count
        model.open([owl])
        check("S-037 a game opened from the Finder is added", model.games.count == countBefore + 1 && model.selectedGame?.title == "Night Owl")
        let script = shelf.appending(path: "extra_scene.rpy")
        try? "label extra_scene:\n    return\n".write(to: script, atomically: true, encoding: .utf8)
        model.selection = first.id
        model.open([script])
        check("S-037 a mod opened from the Finder asks for its game, the selected one first", model.addModsTo?.game == first.id && model.addModsTo?.files == [script])
        await model.addOpenedMods()
        let added = model.game(first.id)?.mods.last.flatMap { model.mod($0.mod) }
        check("S-037 Add puts the mod on that game", model.addModsTo == nil && added?.files == ["extra_scene.rpy"], "\(String(describing: added))")
        if let use = model.game(first.id)?.mods.last { model.removeMod(use.mod, from: first.id) }

        // S-038 Back up saves before each play
        let autoBefore = model.backups(first.id).filter { $0.reason == .beforePlay }.count
        // Something in the saves changes after the last backup, as when the person plays.
        func playOnce() { if let folder = model.saveFolder(first) { FileManager.default.createFile(atPath: folder.appending(path: "1-9-LT1.save").path, contents: Data("\(Date())".utf8)) } }
        playOnce()
        model.play(first.id)
        await waitUntilStopped(model, first.id)
        check("S-038 the saves are backed up before playing", model.backups(first.id).filter { $0.reason == .beforePlay }.count == autoBefore + 1)
        UserDefaults.standard.set(false, forKey: AppModel.backupBeforePlayKey)
        playOnce()
        model.play(first.id)
        await waitUntilStopped(model, first.id)
        UserDefaults.standard.removeObject(forKey: AppModel.backupBeforePlayKey)
        check("S-038 turned off in Settings, no backup is made", model.backups(first.id).filter { $0.reason == .beforePlay }.count == autoBefore + 1)

        // S-039 Pick a game's language
        if let game = model.game(first.id) {
            try? FileManager.default.createDirectory(at: game.baseURL.appending(path: "game/tl/french", directoryHint: .isDirectory), withIntermediateDirectories: true)
            try? "".write(to: game.baseURL.appending(path: "game/tl/french/strings.rpy"), atomically: true, encoding: .utf8)
            model.modsRevision += 1
            check("S-039 the game's translations are listed", model.languages(game) == ["french"], "\(model.languages(game))")
            model.update(first.id) { $0.language = "french" }
            model.play(first.id)
            await waitUntilStopped(model, first.id)
            let file = Store.workingCopy(first.id).appending(path: "game/\(LanguageLoader.fileName)")
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            check("S-039 the language file lands in the copy", text.contains(#"config.language = u"french""#), text)
            model.update(first.id) { $0.language = nil }
            model.play(first.id)
            await waitUntilStopped(model, first.id)
            check("S-039 Game's Choice takes it out", !FileManager.default.fileExists(atPath: file.path))
        }

        // S-040 Change persistent data (the pretend runtime stands in for Ren'Py)
        if let game = model.game(first.id) {
            var read: PersistentInfo?
            var failure = ""
            do { read = try await model.readPersistent(of: game, modded: false) } catch { failure = error.localizedDescription }
            check("S-040 persistent values are read with the game's Ren'Py",
                  read?.variables.map(\.name) == ["endings_seen", "gallery_lucy1", "lucy_img_201_unlocked", "renders[0].unlocked", "true_ending"] && read?.images == 42
                  && read?.labels == 120 && read?.seenLabels == 30, "\(String(describing: read)) \(failure)")
            let editsBefore = model.backups(first.id).filter { $0.reason == .beforeEdit }.count
            let unlocked = try? await model.unlockImages(of: game, modded: false)
            check("S-040 Unlock All Images backs up the saves, then marks the images as seen",
                  unlocked == 40 && model.backups(first.id).filter { $0.reason == .beforeEdit }.count == editsBefore + 1
                  && FileManager.default.fileExists(atPath: Store.workingCopy(first.id).appending(path: "renchan_unlocked").path))
            let replays = try? await model.unlockReplays(of: game, modded: false)
            check("S-040 Mark All Seen marks every scene as seen", replays == 90)
            _ = try? await model.writePersistent(["true_ending": true], of: game, modded: false)
            let sent = (try? String(contentsOf: Store.workingCopy(first.id).appending(path: "renchan_last_changes.json"), encoding: .utf8)) ?? ""
            check("S-040 a persistent change is sent to Ren'Py", sent == #"{"true_ending":true}"#, sent)
        }
    }
}
