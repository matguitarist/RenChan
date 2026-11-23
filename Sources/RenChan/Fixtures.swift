import AppKit
import Foundation
import RenChanKit

/// Tiny Ren'Py games and pretend runtimes in a test folder, for seed data and the self-test. Never used on a real library.
enum Fixtures {
    @discardableResult
    static func game(_ name: String, in root: URL, files: [String: String]) -> URL {
        let base = root.appending(path: name, directoryHint: .isDirectory)
        var all = ["game/script.rpy": "label start:\n    \"Hello.\"\n    return\n"]
        for (path, text) in files { all[path] = text }
        for (path, text) in all {
            let file = base.appending(path: path)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
        return base
    }

    static func options(name: String, saves: String) -> String {
        "define config.name = _(\"\(name)\")\ndefine config.save_directory = \"\(saves)\"\n"
    }

    /// A runtime whose "python" is a script: it compiles nothing, writes a save, and fails with a
    /// traceback when the game's script says crash. Ren'Py's real arguments: -EO renpy.py <base>.
    static func runtime(_ version: String, folder: String, in store: URL) {
        let sdk = store.appending(path: version, directoryHint: .isDirectory)
        let python = sdk.appending(path: "lib/\(folder)/python")
        try? FileManager.default.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = """
        #!/bin/sh
        base="$3"
        touch "$base/game/script.rpyc"
        saves=$(sed -n 's/.*save_directory = "\\(.*\\)".*/\\1/p' "$base/game/options.rpy" 2>/dev/null)
        [ -n "$saves" ] && mkdir -p "$HOME/Library/RenPy/$saves" && touch "$HOME/Library/RenPy/$saves/1-1-LT1.save"
        if grep -q crash "$base/game/script.rpy"; then
          printf 'I am sorry, but an uncaught exception occurred.\\n\\n  File "game/script.rpy", line 2, in script\\nNameError: name '"'"'crash'"'"' is not defined\\n' > "$base/traceback.txt"
          exit 1
        fi
        echo "Ren'Py \(version) ran $base"
        """
        try? script.write(to: python, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        try? "".write(to: sdk.appending(path: "renpy.py"), atomically: true, encoding: .utf8)
    }
}

/// Seed data for snapshots (APP_SEED=1 with APP_STORE): a few games, two runtimes, a morning of log.
enum SeedData {
    static func addIfRequested(model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1", Store.isOverridden, model.games.isEmpty else { return }
        let root = Store.dataFolder.appending(path: "SeedGames", directoryHint: .isDirectory)
        Fixtures.runtime(RuntimeCatalog.python3, folder: "py3-mac-universal", in: Store.runtimesFolder)
        Fixtures.runtime("7.4.11", folder: "mac-x86_64", in: Store.runtimesFolder)
        let games: [(String, String, [String: String])] = [
            ("The_Question-7.0-pc", "The Question", ["renpy/vc_version.py": "version = '8.6.1.26111705'\n"]),
            ("Moonlit_Letters-1.2-pc", "Moonlit Letters", ["game/script_version.txt": "(7, 4, 11)"]),
            ("Harbor_Lights-0.9-pc", "Harbor Lights", ["renpy/vc_version.py": "version = '8.3.7.25031702'\n"]),
            ("Paper_Cranes-2.0-mac", "Paper Cranes", ["lib/py2-mac-universal/readme": ""]),
            ("Seven_Days-1.0-pc", "Seven Days", ["log.txt": "Ren'Py 6.99.14.3.3347\n"]),
        ]
        for (folder, title, files) in games {
            var all = files
            all["game/options.rpy"] = Fixtures.options(name: title, saves: folder)
            model.addFolder(Fixtures.game(folder, in: root, files: all))
        }
        if let first = model.games.first {
            model.update(first.id) { $0.lastPlayed = Date(timeIntervalSinceNow: -3600); $0.playtime = 3 * 3600 + 20 * 60 }
            if model.games.count > 2 { model.update(model.games[2].id) { $0.lastPlayed = Date(timeIntervalSinceNow: -86400 * 3); $0.playtime = 47 * 60 } }
            model.update(first.id) {
                $0.vndb = VNDBInfo(id: "v3625", title: "The Question", developer: "ATP Projects", released: "2006-12-03",
                                   description: "A short story about a boy, a girl, and a question he has been meaning to ask her for a while. Made as a sample game for Ren'Py, it shows what a visual novel can do in a few minutes.")
            }
            model.update(first.id) {
                $0.status = .playing; $0.rating = 4; $0.labels = ["Romance", "Short"]
                $0.notes = "Both endings done. Try the other answer at the bridge."
            }
            if model.games.count > 2 {
                model.update(model.games[2].id) { $0.status = .finished; $0.rating = 5; $0.labels = ["Mystery", "Romance"] }
                model.update(model.games[1].id) { $0.labels = ["Short"] }
            }
            // A 2:3 portrait like VNDB's covers, so snapshots show how one is framed.
            let portrait = NSImage(size: NSSize(width: 600, height: 900), flipped: false) { rect in
                NSGradient(colors: [.systemIndigo, .systemPink, .systemOrange])?.draw(in: rect, angle: 90)
                NSColor.white.withAlphaComponent(0.85).setFill()
                NSBezierPath(ovalIn: NSRect(x: 200, y: 420, width: 200, height: 200)).fill()
                return true
            }
            if let tiff = portrait.tiffRepresentation, let jpeg = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [:]) {
                try? FileManager.default.createDirectory(at: Store.gameFolder(first.id), withIntermediateDirectories: true)
                try? jpeg.write(to: Store.coverFile(first.id))
            }
            let saves = Store.saveRoot.appending(path: "The_Question-7.0-pc", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
            for name in ["1-1-LT1.save", "1-2-LT1.save", "auto-1-LT1.save", "persistent"] {
                try? Data(repeating: 7, count: 48_000).write(to: saves.appending(path: name))
            }
            _ = try? SaveBackups.backUp(saves: saves, into: Store.backupsFolder(first.id), at: Date(timeIntervalSinceNow: -86400 * 6))
            _ = try? SaveBackups.backUp(saves: saves, into: Store.backupsFolder(first.id), reason: .beforeRestore, at: Date(timeIntervalSinceNow: -86400 * 2))
            _ = try? SaveBackups.backUp(saves: saves, into: Store.backupsFolder(first.id), at: Date(timeIntervalSinceNow: -7200))
            model.selection = first.id
        }
        model.runtimes = model.runtimeStore.installed()
        model.log.post(.info, "Downloaded Ren'Py 8.6.1 (148 MB), checksum matches", source: "Runtimes")
        model.log.post(.info, "Made a working copy of The Question (APFS clone)", source: "Play")
        model.log.post(.info, "Started The Question on Ren'Py 8.6.1", source: "Play")
        model.log.post(.warning, "Started Seven Days on Ren'Py 6.99.14.3 under Rosetta", source: "Play")
        model.log.post(.error, "Seven Days quit with an error (exit 1) on Ren'Py 6.99.14.3", source: "Play")
    }
}
