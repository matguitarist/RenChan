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

        // S-008 Remove a game
        model.remove(first.id)
        check("removing deletes the working copy and keeps the original and saves",
              !FileManager.default.fileExists(atPath: copy.path) && FileManager.default.fileExists(atPath: question.path)
              && FileManager.default.fileExists(atPath: Store.saveRoot.appending(path: "the_question-7").path)
              && model.game(first.id) == nil)
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
