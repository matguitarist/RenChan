import PDFKit
import AppKit
import RenChanKit

/// Self-test for agents: drives the app model on a library in /tmp,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/RenChan-self.json ~/Applications/RenChan.app/Contents/MacOS/RenChan --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp so the test never touches the real library")
            finish(code: 1)
            return
        }
        Task {
            check("the library folder is the test one", Store.url.path.hasPrefix("/tmp") || Store.url.path.hasPrefix("/private/tmp"))
            check("the app wrote its start line to the log", model.log.entries.contains { $0.message.hasPrefix("RenChan ") && $0.message.hasSuffix(" started") })
            model.log.post(.info, "Self-test line", source: "SelfTest")
            model.log.flushFile()
            let written = (try? String(contentsOf: Store.logURL, encoding: .utf8)) ?? ""
            check("log lines reach the log file next to the store", written.contains("Self-test line"))

            await libraryChecks(model)

            for tab in SettingsTab.allCases {
                model.settingsTab = tab
                try? await Task.sleep(for: .milliseconds(100))
                check("Settings opens on \(tab.rawValue)", model.settingsTab == tab)
            }
            for page in SidebarItem.allCases {
                model.sidebar = page
                try? await Task.sleep(for: .milliseconds(100))
                check("the sidebar shows \(page.rawValue)", model.sidebar == page)
            }

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    /// M1: add, detect, find, play from a clone, read a crash, remove (docs/STORIES.md S-001 to S-008).
    private static func libraryChecks(_ model: AppModel) async {
        let root = Store.dataFolder.appending(path: "SelfTestGames", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        Fixtures.runtime(RuntimeCatalog.python3, folder: "py3-mac-universal", in: Store.runtimesFolder)
        Fixtures.runtime(RuntimeCatalog.python2, folder: "py2-mac-universal", in: Store.runtimesFolder)
        model.runtimes = model.runtimeStore.installed()
        check("pretend runtimes are installed", model.runtimes.map(\.version).sorted() == [RuntimeCatalog.python2, RuntimeCatalog.python3].sorted())

        // S-001 Add a game
        let question = Fixtures.game("The_Question-7.0-pc", in: root, files: [
            "renpy/vc_version.py": "version = '8.6.1.26111705'\n",
            "game/options.rpy": Fixtures.options(name: "The Question", saves: "the_question-7"),
        ])
        let added = model.addFolder(question)
        check("adding a game folder puts it in the library", added?.title == "The Question" && model.games.count == 1)
        model.addFolder(question)
        check("adding it again doesn't add a duplicate", model.games.count == 1)
        let notAGame = root.appending(path: "Holiday Photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: notAGame, withIntermediateDirectories: true)
        model.addFolder(notAGame)
        check("a folder that isn't a game is refused, saying why", model.games.count == 1 && model.notice == LocateError.noGameFolder.message, model.notice ?? "no notice")
        model.notice = nil

        let app = root.appending(path: "Old Letters.app/Contents/Resources/autorun", directoryHint: .isDirectory)
        Fixtures.game("", in: app, files: ["game/script_version.txt": "(7, 4, 11)"])
        let fromApp = model.addFolder(root.appending(path: "Old Letters.app"))
        check("a Mac .app is added from its autorun folder", fromApp?.kind == .app && fromApp?.title == "Old Letters")

        let zipSource = root.appending(path: "zipsrc", directoryHint: .isDirectory)
        Fixtures.game("Zipped-1.0-pc", in: zipSource, files: ["game/options.rpy": Fixtures.options(name: "Zipped", saves: "zipped-1")])
        let zip = root.appending(path: "Zipped-1.0-pc.zip")
        let zipper = Process()
        zipper.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipper.arguments = ["-qr", zip.path, "Zipped-1.0-pc"]
        zipper.currentDirectoryURL = zipSource
        try? zipper.run()
        zipper.waitUntilExit()
        model.add([zip])
        check("a zip asks before unpacking, with its size", model.confirmZip?.url == zip && (model.confirmZip?.size ?? 0) > 0)
        let fromZip = model.addZip(zip)
        check("a zip is unpacked into RenChan's folder and added", fromZip?.kind == .zip && fromZip?.basePath.contains(Store.dataFolder.lastPathComponent + "/Games/") == true,
              "\(String(describing: fromZip?.basePath)) \(model.notice ?? "")")

        // S-002 Detect the Ren'Py version
        check("the version and Python line are read", added?.version?.description == "8.6.1" && added?.pythonLine == .python3 && added?.versionSource == .vcVersion)
        check("a 7.4 game plays on 7.8.7", fromApp.map { model.runtimeVersion(for: $0) } == RuntimeCatalog.python2)

        // S-006 Library grid and list
        model.search = "lett"
        check("search narrows the library", model.shownGames.map(\.title) == ["Old Letters"])
        model.search = ""
        model.sort = .title
        check("sort by title", model.shownGames.map(\.title) == ["Old Letters", "The Question", "Zipped"])

        // S-011 Labels, rating and notes
        if let first = added, let other = fromApp {
            model.update(first.id) { $0.labels = Labels.add("Romance", to: $0.labels); $0.rating = 4; $0.notes = "Bridge choice" }
            model.update(other.id) { $0.status = .finished; $0.rating = 2 }
            model.filter = LibraryFilter(labels: ["romance"])
            check("S-011 filter by label", model.shownGames.map(\.title) == ["The Question"])
            model.filter = LibraryFilter(minimumRating: 2)
            check("S-011 filter by rating", model.shownGames.map(\.title) == ["Old Letters", "The Question"])
            model.filter = LibraryFilter(status: .finished)
            check("S-011 filter by status", model.shownGames.map(\.title) == ["Old Letters"])
            model.filter = LibraryFilter()
            model.loadLibrary()
            check("S-011 labels, rating and notes are saved", model.game(first.id)?.labels == ["Romance"] && model.game(first.id)?.notes == "Bridge choice")
        }

        // S-004 Play a game, S-007 Open saves
        guard let first = added else { return }
        let before = digest(question)
        model.play(first.id)
        check("Play starts the game", model.playing.contains(first.id))
        await waitUntilStopped(model, first.id)
        let copy = Store.workingCopy(first.id)
        check("the game ran from its working copy", FileManager.default.fileExists(atPath: copy.appending(path: "game/script.rpyc").path))
        check("the original is unchanged", digest(question) == before && !FileManager.default.fileExists(atPath: question.appending(path: "game/script.rpyc").path))
        check("the run was recorded", model.game(first.id)?.lastPlayed != nil && model.launchError == nil)
        check("S-011 playing a game moves it to Playing", model.game(first.id)?.status == .playing)
        check("S-009 playtime counts the run and the session file is gone",
              (model.game(first.id)?.playtime ?? 0) > 0 && !FileManager.default.fileExists(atPath: Store.sessionFile(first.id).path))
        check("saves are found under the test home, never the real one",
              model.saveFolder(first)?.path.hasPrefix(Store.renpyHome.path) == true && model.saveCount(first) == 1)

        // S-014 Turn on a filter: the loader lands in the copy only, and leaves when the filter is off
        model.update(first.id) { $0.filter = FilterSetting(filter: .crt, strength: 0.6) }
        model.play(first.id)
        await waitUntilStopped(model, first.id)
        let filterFile = copy.appending(path: "game/\(FilterLoader.fileName)")
        check("S-014 a filter is written into the working copy, never the original",
              FileManager.default.fileExists(atPath: filterFile.path) && digest(question) == before)
        let live = FilterLoader.liveFile(copy)
        func liveText() -> String { (try? String(contentsOf: live, encoding: .utf8)) ?? "" }
        check("S-015 the filter state starts at the game's filter and strength",
              liveText().contains("\"strength\":0.6") && liveText().contains("\"name\":\"crt\""))
        model.playing.insert(first.id)
        model.update(first.id) { $0.filter = FilterSetting(filter: .grayscale, strength: 0.25) }
        model.applyFilterLive(first.id)
        model.playing.remove(first.id)
        check("S-015 another filter or strength while playing is written for the game",
              liveText().contains("\"strength\":0.25") && liveText().contains("\"name\":\"grayscale\""))
        // S-016 Add my own shader
        let sepiaFile = root.appending(path: "Sepia.glsl")
        try? "// {\"name\": \"Sepia\"}\nc = mix(c, vec3(dot(c, vec3(0.393, 0.769, 0.189))), s);".write(to: sepiaFile, atomically: true, encoding: .utf8)
        _ = try? CustomFilters.add(sepiaFile, to: Store.filtersFolder)
        model.customFilters = CustomFilters.list(in: Store.filtersFolder)
        model.update(first.id) { $0.filter = FilterSetting(custom: "Sepia.glsl") }
        model.play(first.id)
        await waitUntilStopped(model, first.id)
        check("S-016 my own filter is listed and played",
              model.customFilters.map(\.name) == ["Sepia"]
              && liveText().contains("0.393, 0.769, 0.189"))
        model.update(first.id) { $0.filter = nil }
        model.play(first.id)
        await waitUntilStopped(model, first.id)
        check("S-014 turning the filter off draws nothing", !FileManager.default.fileExists(atPath: filterFile.path) || liveText().contains("\"passes\":[]"))

        // S-017 to S-021 Mods
        func modFolder(_ name: String, _ files: [String: String]) -> URL {
            let folder = root.appending(path: "ModSources/\(name)", directoryHint: .isDirectory)
            for (path, text) in files {
                let url = folder.appending(path: path)
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? text.write(to: url, atomically: true, encoding: .utf8)
            }
            return folder
        }
        model.addMod(modFolder("Question_Walkthrough", ["Question-7.0/game/walkthrough.rpy": "screen choice(items): pass"]), to: first.id)
        model.addMod(modFolder("URM", ["0x52_URM.rpy": "screen choice(items): pass"]), to: first.id)
        check("S-017 a mod is added to the game and kept by RenChan",
              model.mods.count == 2 && model.game(first.id)?.mods.count == 2
              && FileManager.default.fileExists(atPath: Store.modsFolder.appending(path: "mods.json").path))
        check("S-019 two mods that change the same screen are reported", model.modConflicts(model.game(first.id)!).count == 1)
        let moddedBackupsBefore = model.backups(first.id).filter { $0.reason == .beforeMods }.count
        model.play(first.id)
        await waitUntilStopped(model, first.id)
        let modded = Store.moddedCopy(first.id)
        check("S-018 the mods are in the modded copy only, never the plain copy or the original",
              FileManager.default.fileExists(atPath: modded.appending(path: "game/walkthrough.rpy").path)
              && !FileManager.default.fileExists(atPath: copy.appending(path: "game/walkthrough.rpy").path)
              && !FileManager.default.fileExists(atPath: question.appending(path: "game/walkthrough.rpy").path)
              && digest(question) == before)
        let moddedSave = Store.moddedSaves(first.id).appending(path: "\(model.game(first.id)?.saveDirectory ?? "")/1-1-LT1.save")
        check("S-020 modded play keeps its saves apart, after one backup",
              FileManager.default.fileExists(atPath: moddedSave.path)
              && model.backups(first.id).filter { $0.reason == .beforeMods }.count == moddedBackupsBefore + 1)
        let urm = model.mods.first { $0.name == "URM" }!.id
        model.setMod(urm, enabled: false, in: first.id)
        model.play(first.id)
        await waitUntilStopped(model, first.id)
        check("S-018 turning a mod off takes its files out before launch",
              !FileManager.default.fileExists(atPath: modded.appending(path: "game/0x52_URM.rpy").path)
              && FileManager.default.fileExists(atPath: modded.appending(path: "game/walkthrough.rpy").path))
        // S-021: URM, added once, goes on another game with one click.
        if let other = model.games.first(where: { $0.id != first.id }) {
            model.attachMod(urm, to: other.id)
            check("S-021 a library mod goes on another game in one step", model.game(other.id)?.mods.first?.mod == urm)
            model.removeMod(urm, from: other.id)
        }
        let walkthrough = model.mods.first { $0.name != "URM" }!.id
        model.removeMod(walkthrough, from: first.id)
        model.removeMod(urm, from: first.id)
        check("S-017 a mod no game uses leaves the library", model.mods.isEmpty)

        // S-022 Developer console
        model.update(first.id) { $0.devTools = DevTools(console: true, fastSkip: true) }
        model.play(first.id)
        await waitUntilStopped(model, first.id)
        let devFile = copy.appending(path: "game/\(DevToolsLoader.fileName)")
        check("S-022 the console and fast skip go in the copy only",
              ((try? String(contentsOf: devFile, encoding: .utf8)) ?? "").contains("config.console = True") && digest(question) == before)
        model.update(first.id) { $0.devTools = DevTools() }
        // S-027 Compatibility report
        check("S-027 each run is recorded", (model.game(first.id)?.runs.count ?? 0) >= 1 && model.game(first.id)?.runs.first?.outcome == .worked
              && model.game(first.id)?.runs.first?.runtime == RuntimeCatalog.python3)
        let compat = model.compatibilityReport()
        check("S-027 the report lists each game and its last run", compat.contains("| The Question |") && compat.contains("| worked |"), compat)
        // S-023, S-024 a mod made from the template, with the API beside it
        model.createMod(named: "Bridge Helper", for: first.id)
        model.play(first.id)
        await waitUntilStopped(model, first.id)
        let modded024 = Store.moddedCopy(first.id)
        check("S-024 New Mod makes a mod from the template and plays it",
              FileManager.default.fileExists(atPath: modded024.appending(path: "game/bridge_helper.rpy").path)
              && ModLibrary.manifest(model.mods.first { $0.name == "Bridge Helper" }!, root: Store.modsFolder)?.name == "Bridge Helper")
        check("S-023 the mod API is beside the mods", FileManager.default.fileExists(atPath: modded024.appending(path: "game/\(ModAPI.fileName)").path))
        if let helper = model.mods.first(where: { $0.name == "Bridge Helper" }) { model.removeMod(helper.id, from: first.id) }

        // S-032 Walkthroughs
        let guide = root.appending(path: "Question_Walkthrough.pdf")
        Fixtures.pdf(["Page one", "Page two", "Page three"], to: guide)
        let added032 = model.addWalkthrough(guide, to: first.id)
        let stored = added032.map { model.walkthroughURL(model.game(first.id)!, $0) }
        check("S-032 a walkthrough PDF is kept by RenChan and opens", stored.flatMap { PDFDocument(url: $0) }?.pageCount == 3)
        if let added032 { model.setWalkthroughPage(2, WalkthroughRef(game: first.id, walkthrough: added032.id)) }
        check("S-032 the page read is remembered", model.game(first.id)?.walkthroughs.first?.page == 2)
        let fake = root.appending(path: "expired.pdf")
        try? "<Error><Code>ExpiredRequest</Code></Error>".write(to: fake, atomically: true, encoding: .utf8)
        model.notice = nil
        model.addWalkthrough(fake, to: first.id)
        check("S-032 a PDF that isn't one is refused with why", model.game(first.id)?.walkthroughs.count == 1 && model.notice != nil)
        model.notice = nil
        if let added032 { model.removeWalkthrough(added032.id, from: first.id) }
        check("S-032 removing a walkthrough takes its file out", model.game(first.id)?.walkthroughs.isEmpty == true
              && !(stored.map { FileManager.default.fileExists(atPath: $0.path) } ?? true))

        // S-005 See why a game didn't start
        let broken = Fixtures.game("Broken-1.0-pc", in: root, files: [
            "game/script.rpy": "label start:\n    $ crash()\n",
            "renpy/__init__.py": "version_tuple = (7, 4, 11, vc_version)\n",
        ])
        if let crash = model.addFolder(broken) {
            model.play(crash.id)
            await waitUntilStopped(model, crash.id)
            check("a crash shows Ren'Py's traceback with file and line", model.launchError?.text.contains("game/script.rpy\", line 2") == true)
            check("the exact version is offered", model.launchError?.exactVersion == "7.4.11")
            check("S-009 a crash still counts its playtime", (model.game(crash.id)?.playtime ?? 0) > 0)
            model.launchError = nil
        }

        // S-010 Details from VNDB: a cover the person chose stays when VNDB details change
        let picture = root.appending(path: "cover.png")
        if let tiff = NSImage(size: NSSize(width: 8, height: 8), flipped: false, drawingHandler: { rect in NSColor.systemPink.setFill(); rect.fill(); return true }).tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: picture)
        }
        model.setCover(first.id, from: picture)
        check("S-010 a chosen cover is stored by RenChan, not in the game",
              model.game(first.id)?.customCover == true && FileManager.default.fileExists(atPath: Store.coverFile(first.id).path)
              && CoverCache.shared.image(for: model.game(first.id)!) != nil)
        model.update(first.id) { _ = VNDB.apply(VNDBInfo(id: "v3625", title: "The Question", imageURL: "https://t.vndb.org/x.jpg"), to: &$0) }
        model.unlinkVNDB(first.id)
        check("S-010 linking and unlinking VNDB keeps the chosen cover",
              model.game(first.id)?.vndb == nil && FileManager.default.fileExists(atPath: Store.coverFile(first.id).path))
        model.resetCover(first.id)
        check("S-010 Reset Cover goes back to the game's own art", model.game(first.id)?.customCover == false
              && !FileManager.default.fileExists(atPath: Store.coverFile(first.id).path))

        // S-012 Back up saves
        if let saves = model.saveFolder(first) {
            model.backUpSaves(first.id)
            check("S-012 Back Up Saves makes a dated backup in RenChan's folder",
                  model.backups(first.id).filter { $0.reason == .manual }.count == 1
                  && model.backups(first.id).first { $0.reason == .manual }?.saveCount == 1)
            try? "later".write(to: saves.appending(path: "2-1-LT1.save"), atomically: true, encoding: .utf8)
            if let backup = model.backups(first.id).first(where: { $0.reason == .manual }) { model.restore(backup, for: first.id) }
            check("S-012 a restore brings back the saves and backs up the ones it replaced",
                  !FileManager.default.fileExists(atPath: saves.appending(path: "2-1-LT1.save").path)
                  && model.backups(first.id).first?.reason == .beforeRestore && model.backups(first.id).first?.saveCount == 2)
        }

        // S-013 Update a game to a new version
        let newVersion = Fixtures.game("The_Question-8.0-pc", in: root, files: [
            "renpy/vc_version.py": "version = '8.6.1.26111705'\n",
            "game/options.rpy": Fixtures.options(name: "The Question", saves: "the_question-7"),
        ])
        let kept = model.game(first.id)
        model.prepareUpdate(first.id, from: newVersion)
        check("S-013 picking a new version asks first", model.confirmUpdate?.url == newVersion && model.game(first.id)?.sourcePath == question.path)
        if let request = model.confirmUpdate { model.applyUpdate(request) }
        let updated = model.game(first.id)
        check("S-013 the game now plays the new version", updated?.sourcePath == newVersion.path && updated?.basePath == newVersion.path
              && !FileManager.default.fileExists(atPath: Store.workingCopy(first.id).path))
        check("S-013 playtime, labels, notes and backups carry over",
              updated?.playtime == kept?.playtime && updated?.labels == kept?.labels && updated?.notes == kept?.notes
              && updated?.status == kept?.status && !model.backups(first.id).isEmpty)
        check("S-013 the old version is left as it was", digest(question) == before)
        model.prepareUpdate(first.id, from: newVersion)
        check("S-013 picking the same version again says so", model.confirmUpdate == nil && model.notice != nil)
        model.notice = nil
        if let zipped = fromZip {
            let oldBase = URL(fileURLWithPath: zipped.basePath)
            Fixtures.game("Zipped-2.0-pc", in: zipSource, files: ["game/options.rpy": Fixtures.options(name: "Zipped", saves: "zipped-1")])
            let zip2 = root.appending(path: "Zipped-2.0-pc.zip")
            let zipper2 = Process()
            zipper2.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zipper2.arguments = ["-qr", zip2.path, "Zipped-2.0-pc"]
            zipper2.currentDirectoryURL = zipSource
            try? zipper2.run()
            zipper2.waitUntilExit()
            model.prepareUpdate(zipped.id, from: zip2)
            if let request = model.confirmUpdate { model.applyUpdate(request) }
            let now = model.game(zipped.id)
            check("S-013 a zip update unpacks the new zip and drops RenChan's copy of the old one",
                  now?.sourcePath == zip2.path && now?.basePath.hasSuffix("Zipped-2.0-pc") == true
                  && now.map { FileManager.default.fileExists(atPath: $0.basePath) } == true
                  && !FileManager.default.fileExists(atPath: oldBase.path),
                  "\(now?.sourcePath ?? "nil") \(now?.basePath ?? "nil") old \(oldBase.path) \(model.notice ?? "")")
        }

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

        // S-035 Browse saves, S-036 change a save's variables (the pretend runtime stands in for Ren'Py)
        if let folder = model.savesFolder(model.game(first.id)!, modded: false) {
            Fixtures.save("1-2", name: "At the bridge", minutesAgo: 5, color: .systemPink, in: folder)
            Fixtures.save("quick-1", name: "", minutesAgo: 60, color: .systemBlue, in: folder)
            let listed = SaveList.list(in: folder)
            check("S-035 saves are listed newest first with their name and picture",
                  listed.first?.slot == "1-2" && listed.first?.name == "At the bridge" && listed.first?.screenshot() != nil
                  && listed.contains { $0.place == "Quick 1" }, "\(listed.map(\.slot))")
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

        await newChecks(model, first: first, shelf: shelf)

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
        let sqlite = Process()
        sqlite.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        sqlite.arguments = [db.path, """
            CREATE TABLE games (id INTEGER PRIMARY KEY, name TEXT, version TEXT, executables TEXT);
            INSERT INTO games VALUES (4242, 'Night Ferry', 'v0.3', '["\(shelf.path)/Night_Ferry-0.3-pc/NightFerry.exe"]');
            INSERT INTO games VALUES (77, 'Far Away', '1.0', '["/Volumes/Nowhere/FarAway/FarAway.exe"]');
            """]
        try? sqlite.run()
        sqlite.waitUntilExit()
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

        // S-008 Remove a game
        model.remove(first.id)
        check("removing deletes the working copy and keeps the original and saves",
              !FileManager.default.fileExists(atPath: copy.path) && FileManager.default.fileExists(atPath: question.path)
              && FileManager.default.fileExists(atPath: Store.saveRoot.appending(path: "the_question-7").path)
              && model.game(first.id) == nil)
        check("S-012 removing a game keeps its save backups", FileManager.default.fileExists(atPath: Store.backupsFolder(first.id).path))
        model.notice = nil
    }

    /// S-037 to S-040: open from the Finder, back up before play, language, persistent data.
    private static func newChecks(_ model: AppModel, first: Game, shelf: URL) async {
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
        model.addOpenedMods()
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

    private static func waitUntilStopped(_ model: AppModel, _ id: UUID) async {
        for _ in 0..<100 where model.playing.contains(id) {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func digest(_ folder: URL) -> [String: Date] {
        var all: [String: Date] = [:]
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        while let file = walker?.nextObject() as? URL {
            all[file.path] = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        return all
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
