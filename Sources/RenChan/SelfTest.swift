import AppKit
import AppTestKit
import PDFKit
import PictureKitUI
import ProcessKit
import RenChanKit

/// Self-test for agents: drives the app model on a library in /tmp,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/RenChan-self.json ~/Applications/RenChan.app/Contents/MacOS/RenChan --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
/// AppTestKit prints the lines, refuses without APP_STORE in /tmp, and quits with the exit code.
extension SelfTest {
    static func runIfRequested(model: AppModel) {
        run(refusal: "set APP_STORE to a file in /tmp so the test never touches the real library") {
            check("the library folder is the test one", Store.url.path.hasPrefix("/tmp") || Store.url.path.hasPrefix("/private/tmp"))
            check("the app wrote its start line to the log", model.log.entries.contains { $0.message.hasPrefix("RenChan ") && $0.message.hasSuffix(" started") })
            model.log.post(.info, "Self-test line", source: "SelfTest")
            model.log.flushFile()
            let written = (try? String(contentsOf: Store.logURL, encoding: .utf8)) ?? ""
            check("log lines reach the log file next to the store", written.contains("Self-test line"))
            let issue = RepositoryLinks(repository: "matguitarist/RenChan").newIssue(app: "RenChan").absoluteString
            check("Help › Report a Problem opens a new GitHub issue with the version and macOS filled in",
                  issue.hasPrefix("https://github.com/matguitarist/RenChan/issues/new?body=") && issue.contains("macOS"), issue)

            whatsNewChecks()

            await damagedLibraryCheck(model)

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
        }
    }

    /// What's New: a newer version shows its bundled notes once; a fresh install and test runs show nothing.
    private static func whatsNewChecks() {
        check("What's New compares versions number by number",
              WhatsNew.isNewer("0.10.0", than: "0.9.2") && WhatsNew.isNewer("1.0", than: "0.9.9") && !WhatsNew.isNewer("0.9.0", than: "0.9.0")
              && !WhatsNew.isNewer("2.4", than: "2.4.0") && !WhatsNew.isNewer("0.8.2", than: "0.9.0"))
        check("What's New stays quiet on a fresh install", !WhatsNew.isNewer("0.9.0", than: nil))
        check("What's New never shows in a test run", WhatsNew.isTestRun && WhatsNew.pending(defaults: UserDefaults(suiteName: "RenChan-selftest") ?? .standard) == nil)
        check("this version's release notes are in the app", WhatsNew.bundled(WhatsNew.currentVersion) != nil, WhatsNew.currentVersion)
        check("release notes read as headings, list items and paragraphs",
              NotesBlock.parse("## New\n\n- **One**\n  more\n- Two\n\nText\non two lines") ==
              [.heading("New"), .item(marker: "•", text: "**One** more"), .item(marker: "•", text: "Two"), .paragraph("Text on two lines")])
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
        _ = try? Shell.runSync("/usr/bin/zip", ["-qr", zip.path, "Zipped-1.0-pc"], in: zipSource)
        // Two zips dropped together: each is asked about in turn.
        let zip2 = root.appending(path: "Zipped-copy.zip")
        try? FileManager.default.copyItem(at: zip, to: zip2)
        model.add([zip, zip2])
        let firstAsked = model.confirmZip?.url
        model.zipAnswered()
        for _ in 0..<50 where model.confirmZip == nil { await Task.yield() }
        check("dropping two zips asks about each in turn", firstAsked == zip && model.confirmZip?.url == zip2 && (model.confirmZip?.size ?? 0) > 0,
              "\(String(describing: firstAsked)) \(String(describing: model.confirmZip))")
        model.zipAnswered()
        model.add([zip])
        check("a zip asks before unpacking, with its size", model.confirmZip?.url == zip && (model.confirmZip?.size ?? 0) > 0)
        let fromZip = await model.addZip(zip)
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
        check("Play makes the working copy in the background, without blocking", model.copying[first.id] != nil && !model.playing.contains(first.id))
        for _ in 0..<100 where model.copying[first.id] != nil { try? await Task.sleep(for: .milliseconds(50)) }
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
        await model.addMod(modFolder("Question_Walkthrough", ["Question-7.0/game/walkthrough.rpy": "screen choice(items): pass"]), to: first.id)
        await model.addMod(modFolder("URM", ["0x52_URM.rpy": "screen choice(items): pass"]), to: first.id)
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
        await moddedSavesChecks(model, first: first)
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
            // Try Exact Version can be undone: the inspector's runtime menu goes back to Automatic.
            model.update(crash.id) { $0.runtimeOverride = "7.4.11" }
            let offered = model.runtimeChoices(model.game(crash.id)!)
            model.setRuntime(nil, for: crash.id)
            check("S-004 a game's runtime can be picked and set back to Automatic",
                  offered.exact == "7.4.11" && offered.automatic == RuntimeCatalog.python2
                  && model.game(crash.id)?.runtimeOverride == nil && model.runtimeVersion(for: model.game(crash.id)!) == RuntimeCatalog.python2,
                  "\(offered)")
        }
        // Stop is the person's choice, not a crash: no error sheet, and the report says it worked.
        let slow = Fixtures.game("Slow-1.0-pc", in: root, files: [
            "game/script.rpy": "label start:\n    $ hang()\n",
            "renpy/__init__.py": "version_tuple = (8, 6, 1, vc_version)\n",
        ])
        if let hanging = model.addFolder(slow) {
            model.play(hanging.id)
            for _ in 0..<50 where !model.playing.contains(hanging.id) { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(500))
            model.stop(hanging.id)
            await waitUntilStopped(model, hanging.id)
            check("S-004 Stop ends the game without an error sheet, and the run counts as worked",
                  model.launchError == nil && model.game(hanging.id)?.runs.first?.outcome == .worked
                  && model.game(hanging.id)?.runs.first?.exitCode == SIGTERM,
                  "\(String(describing: model.game(hanging.id)?.runs.first))")
            model.launchError = nil
            model.remove(hanging.id)
        }
        await downloadQueueChecks(model, root: root)

        // S-010 Details from VNDB: a cover the person chose stays when VNDB details change
        // A big PNG, as a person might pick: it's kept as a HEIC at most 1200 px.
        let picture = root.appending(path: "cover.png")
        Fixtures.picture(.systemPink, to: picture, size: NSSize(width: 1600, height: 2400))
        await model.setCover(first.id, from: picture)
        let shown = await PictureCache.shared.image(Cover.source(model.game(first.id)!), maxPixels: 720)
        let storedCover = Store.coverFile(first.id)
        check("S-010 a chosen cover is stored by RenChan as HEIC at most 1200 px, not in the game, and shown",
              model.game(first.id)?.customCover == true && storedCover?.pathExtension == "heic"
              && (storedCover.flatMap { Pictures.info(at: $0)?.longSide } ?? 0) <= 1200 && shown != nil && FileManager.default.fileExists(atPath: picture.path),
              "\(storedCover?.lastPathComponent ?? "none")")
        model.update(first.id) { _ = VNDB.apply(VNDBInfo(id: "v3625", title: "The Question", imageURL: "https://t.vndb.org/x.jpg"), to: &$0) }
        model.unlinkVNDB(first.id)
        check("S-010 linking and unlinking VNDB keeps the chosen cover",
              model.game(first.id)?.vndb == nil && Store.coverFile(first.id) != nil)
        model.resetCover(first.id)
        check("S-010 Reset Cover goes back to the game's own art", model.game(first.id)?.customCover == false
              && Store.coverFile(first.id) == nil)

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
        let modStateFile = Store.modState(first.id).appending(path: "bridge.json")
        try? FileManager.default.createDirectory(at: Store.modState(first.id), withIntermediateDirectories: true)
        try? "{\"crossed\": true}".write(to: modStateFile, atomically: true, encoding: .utf8)
        model.prepareUpdate(first.id, from: newVersion)
        check("S-013 picking a new version asks first", model.confirmUpdate?.url == newVersion && model.game(first.id)?.sourcePath == question.path)
        if let request = model.confirmUpdate { await model.applyUpdate(request) }
        let updated = model.game(first.id)
        check("S-013 the game now plays the new version", updated?.sourcePath == newVersion.path && updated?.basePath == newVersion.path
              && !FileManager.default.fileExists(atPath: Store.workingCopy(first.id).path))
        check("S-013 playtime, labels, notes and backups carry over",
              updated?.playtime == kept?.playtime && updated?.labels == kept?.labels && updated?.notes == kept?.notes
              && updated?.status == kept?.status && !model.backups(first.id).isEmpty)
        check("S-013 the old version is left as it was", digest(question) == before)
        check("S-023 a mod's saved state outlives an update", FileManager.default.fileExists(atPath: modStateFile.path))
        model.prepareUpdate(first.id, from: newVersion)
        check("S-013 picking the same version again says so", model.confirmUpdate == nil && model.notice != nil)
        model.notice = nil
        if let zipped = fromZip {
            let oldBase = URL(fileURLWithPath: zipped.basePath)
            Fixtures.game("Zipped-2.0-pc", in: zipSource, files: ["game/options.rpy": Fixtures.options(name: "Zipped", saves: "zipped-1")])
            let zip2 = root.appending(path: "Zipped-2.0-pc.zip")
            _ = try? Shell.runSync("/usr/bin/zip", ["-qr", zip2.path, "Zipped-2.0-pc"], in: zipSource)
            model.prepareUpdate(zipped.id, from: zip2)
            if let request = model.confirmUpdate {
                let updating = Task { await model.applyUpdate(request) }
                for _ in 0..<100 where !model.updatingGames.contains(zipped.id) { await Task.yield() }
                model.play(zipped.id)
                check("Play waits while an update is being put in", !model.playing.contains(zipped.id) && model.copying[zipped.id] == nil
                      && model.notice != nil && model.updatingGames.contains(zipped.id))
                model.notice = nil
                _ = await updating.value
            }
            let now = model.game(zipped.id)
            check("S-013 a zip update unpacks the new zip and drops RenChan's copy of the old one",
                  now?.sourcePath == zip2.path && now?.basePath.hasSuffix("Zipped-2.0-pc") == true
                  && now.map { FileManager.default.fileExists(atPath: $0.basePath) } == true
                  && !FileManager.default.fileExists(atPath: oldBase.path),
                  "\(now?.sourcePath ?? "nil") \(now?.basePath ?? "nil") old \(oldBase.path) \(model.notice ?? "")")
        }

        // S-028 to S-030 Discover and Find Games
        let shelf = await discoverChecks(model, root: root)

        // S-035, S-036 and the gallery
        await savesChecks(model, first: first)

        await newChecks(model, first: first, shelf: shelf)

        // S-033, S-034
        await watchAndImportChecks(model, first: first, shelf: shelf)

        // S-008 Remove a game
        let moddedSaveDir = model.game(first.id)?.saveDirectory ?? ""
        let hadModdedSaves = FileManager.default.fileExists(atPath: Store.moddedSaves(first.id).appending(path: moddedSaveDir).path)
        model.remove(first.id)
        let trashed = Store.dataFolder.appending(path: "Trash/The Question/Modded Saves/\(moddedSaveDir)/1-1-LT1.save")
        check("removing a game puts its modded saves in the Trash, not nowhere",
              hadModdedSaves && FileManager.default.fileExists(atPath: trashed.path), trashed.path)
        check("removing deletes the working copy and keeps the original and saves",
              !FileManager.default.fileExists(atPath: copy.path) && FileManager.default.fileExists(atPath: question.path)
              && FileManager.default.fileExists(atPath: Store.saveRoot.appending(path: "the_question-7").path)
              && model.game(first.id) == nil)
        check("S-012 removing a game keeps its save backups", FileManager.default.fileExists(atPath: Store.backupsFolder(first.id).path))
        model.notice = nil
    }

    /// A library.json that can't be read is kept aside, never saved over, and the person is told where it went.
    private static func damagedLibraryCheck(_ model: AppModel) async {
        model.flushLibrary()
        let good = try? Data(contentsOf: Store.url)
        try? Data("[{\"title\": ".utf8).write(to: Store.url)
        model.loadLibrary()
        let folder = Store.url.deletingLastPathComponent()
        let prefix = Store.url.deletingPathExtension().lastPathComponent + " (damaged "
        let aside = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
        check("a damaged library is kept aside and the person is told", aside.count == 1 && !FileManager.default.fileExists(atPath: Store.url.path)
              && model.notice?.contains(aside.first?.lastPathComponent ?? "-") == true, model.notice ?? "no notice")
        for file in aside { try? FileManager.default.removeItem(at: file) }
        if let good { try? good.write(to: Store.url) }
        model.notice = nil
        model.loadLibrary()
    }

    static func waitUntilStopped(_ model: AppModel, _ id: UUID) async {
        // A first launch makes its copy before it plays.
        for _ in 0..<100 where model.copying[id] != nil { try? await Task.sleep(for: .milliseconds(50)) }
        for _ in 0..<100 where model.playing.contains(id) {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    static func digest(_ folder: URL) -> [String: Date] {
        var all: [String: Date] = [:]
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        while let file = walker?.nextObject() as? URL {
            all[file.path] = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        return all
    }
}
