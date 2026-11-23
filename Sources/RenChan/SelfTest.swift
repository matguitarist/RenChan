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
                  model.backups(first.id).count == 1 && model.backups(first.id).first?.saveCount == 1)
            try? "later".write(to: saves.appending(path: "2-1-LT1.save"), atomically: true, encoding: .utf8)
            if let backup = model.backups(first.id).first { model.restore(backup, for: first.id) }
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

        // S-008 Remove a game
        model.remove(first.id)
        check("removing deletes the working copy and keeps the original and saves",
              !FileManager.default.fileExists(atPath: copy.path) && FileManager.default.fileExists(atPath: question.path)
              && FileManager.default.fileExists(atPath: Store.saveRoot.appending(path: "the_question-7").path)
              && model.game(first.id) == nil)
        check("S-012 removing a game keeps its save backups", FileManager.default.fileExists(atPath: Store.backupsFolder(first.id).path))
        model.notice = nil
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
