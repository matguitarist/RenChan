import AppKit
import AppTestKit
import Foundation
import ProcessKit
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
        # RenChan's save tool (S-036): canned answers, and the changes kept for the self-test to read.
        if [ "$4" = "renchan_saves" ]; then
          for last; do :; done
          if [ "$5" = "dump" ]; then
            printf '%s' '{"variables":[{"name":"affection_mei","kind":"int","value":"12"},{"name":"bag","kind":"other","value":"list (3)"},{"name":"chapter","kind":"float","value":"2.5"},{"name":"hero","kind":"string","value":"Ana"},{"name":"met_aoi","kind":"bool","value":"true"}]}' > "$last"
          elif [ "$5" = "pdump" ]; then
            printf '%s' '{"variables":[{"name":"endings_seen","kind":"int","value":"1"},{"name":"gallery_lucy1","kind":"bool","value":"false"},{"name":"lucy_img_201_unlocked","kind":"bool","value":"true"},{"name":"renders[0].unlocked","kind":"bool","value":"false","note":"Hawaiian Dream"},{"name":"true_ending","kind":"bool","value":"false"}],"images":42,"labels":120,"seenLabels":30}' > "$last"
          elif [ "$5" = "pictures" ]; then
            printf '{"pictures":[' > "$last"
            find "$base/game" -name '*.png' | sort | {
              sep=""
              while read -r f; do
                printf '%s{"path":"%s","file":"%s"}' "$sep" "${f#"$base/game/"}" "$f" >> "$last"
                sep=","
              done
            }
            printf ']}' >> "$last"
          elif [ "$5" = "replays" ]; then
            printf '%s' '{"unlocked":90,"labels":120}' > "$last"
          elif [ "$5" = "unlock" ]; then
            touch "$base/renchan_unlocked"
            printf '%s' '{"unlocked":40,"images":42}' > "$last"
          else
            cp "$7" "$base/renchan_last_changes.json"
            printf '%s' "$6" > "$base/renchan_last_slots"
            printf '%s' '{"changed":["affection_mei"],"refused":[]}' > "$last"
          fi
          exit 0
        fi
        touch "$base/game/script.rpyc"
        saves=$(sed -n 's/.*save_directory = "\\(.*\\)".*/\\1/p' "$base/game/options.rpy" 2>/dev/null)
        root="${RENPY_PATH_TO_SAVES:-$HOME/Library/RenPy}"
        [ -n "$saves" ] && mkdir -p "$root/$saves" && touch "$root/$saves/1-1-LT1.save"
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

extension Fixtures {
    /// A gradient picture for the gallery's seed data (S-042).
    static func picture(_ color: NSColor, to file: URL, size: NSSize = NSSize(width: 640, height: 360)) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: color, ending: color.blended(withFraction: 0.7, of: .black) ?? color)?.draw(in: rect, angle: -35)
            return true
        }
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: file)
        }
    }

    /// A save file laid out as Ren'Py writes one: a zip with a screenshot, its name, json and log (S-035).
    static func save(_ slot: String, name: String, minutesAgo: Double, color: NSColor, in folder: URL) {
        let work = FileManager.default.temporaryDirectory.appending(path: "renchan-save-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 384, height: 216), flipped: false) { rect in
            NSGradient(starting: color, ending: color.blended(withFraction: 0.6, of: .black) ?? color)?.draw(in: rect, angle: -60)
            return true
        }
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: work.appending(path: "screenshot.png"))
        }
        let ctime = Date().addingTimeInterval(-minutesAgo * 60).timeIntervalSince1970
        try? name.write(to: work.appending(path: "extra_info"), atomically: true, encoding: .utf8)
        try? #"{"_save_name": "\#(name)", "_renpy_version": [8, 6, 1, 0], "_game_runtime": \#(minutesAgo * 30), "_ctime": \#(ctime)}"#
            .write(to: work.appending(path: "json"), atomically: true, encoding: .utf8)
        try? "8.6.1".write(to: work.appending(path: "renpy_version"), atomically: true, encoding: .utf8)
        try? "pretend".write(to: work.appending(path: "log"), atomically: true, encoding: .utf8)
        _ = try? Shell.runSync("/usr/bin/zip", ["-q", folder.appending(path: "\(slot)-LT1.save").path, "screenshot.png", "extra_info", "json", "renpy_version", "log"], in: work)
        try? FileManager.default.removeItem(at: work)
    }

    /// A small PDF with one page of text per item, for walkthrough seed data and the self-test.
    static func pdf(_ pages: [String], to url: URL) {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        for text in pages {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black])
                .draw(in: CGRect(x: 54, y: 54, width: 504, height: 684))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
    }
}

/// Seed data for snapshots (APP_SEED=1 with APP_STORE): a few games, two runtimes, a morning of log.
enum SeedData {
    static func addIfRequested(model: AppModel) async {
        guard TestRun.isSeeded(), model.games.isEmpty else { return }
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
                $0.filter = FilterSetting(filter: .crt, strength: 0.6)
            }
            try? "// {\"name\": \"Sepia\"}\nc = mix(c, vec3(dot(c, vec3(0.393, 0.769, 0.189))), s);"
                .write(to: root.appending(path: "Sepia.glsl"), atomically: true, encoding: .utf8)
            _ = try? CustomFilters.add(root.appending(path: "Sepia.glsl"), to: Store.filtersFolder)
            model.customFilters = CustomFilters.list(in: Store.filtersFolder)
            if model.games.count > 1 {
                let modsRoot = Store.dataFolder.appending(path: "SeedMods", directoryHint: .isDirectory)
                for (name, files) in [("Moonlit_Letters_Walkthrough_Mod", ["game/walkthrough.rpy": "screen choice(items): pass", "game/screens.rpy": ""]),
                                      ("Gallery_Unlocker", ["screens.rpy": "", "unlock.rpy": "init: pass"]),
                                      ("0x52_URM", ["0x52_URM.rpa": "rpa"])] {
                    let folder = modsRoot.appending(path: name)
                    for (path, text) in files {
                        try? FileManager.default.createDirectory(at: folder.appending(path: path).deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? text.write(to: folder.appending(path: path), atomically: true, encoding: .utf8)
                    }
                    await model.addMod(folder, to: model.games[1].id)
                }
                if let urm = model.mods.last { model.setMod(urm.id, enabled: false, in: model.games[1].id) }
                let pdf = modsRoot.appending(path: "Moonlit_Letters_Walkthrough_v1.2.pdf")
                Fixtures.pdf([
                    "Moonlit Letters — Walkthrough v1.2\n\nChapter 1\n\n• Answer the first letter: \"I remember the lake.\" (+1 Mei)\n• At the station, wait for the last train. (+1 Aoi)\n• Keep the pressed flower.",
                    "Chapter 2\n\n• Read the letter aloud. (+1 Mei)\n• Skip the festival only if you want Aoi's route.\n• The bridge: say \"Not yet.\" for the good ending.",
                ], to: pdf)
                if let walkthrough = model.addWalkthrough(pdf, to: model.games[1].id) {
                    model.setWalkthroughPage(1, WalkthroughRef(game: model.games[1].id, walkthrough: walkthrough.id))
                }
            }
            if model.games.count > 2 {
                model.update(model.games[2].id) {
                    $0.status = .finished; $0.rating = 5; $0.labels = ["Mystery", "Romance"]
                    // S-033: its itch.io page shows a newer version.
                    $0.gameVersion = "1.0"
                    var watch = UpdateWatch(page: "https://lanternworks.itch.io/harbor-lights")
                    watch.record(version: "1.1", error: nil, at: .now.addingTimeInterval(-7200))
                    $0.watch = watch
                }
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
                _ = try? Covers.store(jpeg, at: Store.coverBase(first.id))
            }
            // S-039: two translations, one picked.
            for language in ["french", "spanish"] {
                let folder = first.baseURL.appending(path: "game/tl/\(language)", directoryHint: .isDirectory)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? "".write(to: folder.appending(path: "strings.rpy"), atomically: true, encoding: .utf8)
            }
            model.update(first.id) { $0.language = "french"; $0.pinnedVariables = ["affection_mei"] }
            // S-042: story pictures in two folders, and an interface picture the gallery hides at first.
            let pictures: [(String, NSColor)] = [("images/cg/bridge_dusk.png", .systemOrange), ("images/cg/bridge_night.png", .systemIndigo),
                                                 ("images/cg/confession.png", .systemPink), ("images/cg/epilogue.png", .systemTeal),
                                                 ("images/bg/cafe.png", .systemBrown), ("images/bg/park.png", .systemGreen),
                                                 ("images/bg/station.png", .systemBlue), ("gui/button/idle.png", .systemGray)]
            for (path, color) in pictures { Fixtures.picture(color, to: first.baseURL.appending(path: "game/\(path)")) }
            let saves = Store.saveRoot.appending(path: "The_Question-7.0-pc", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
            // Saves laid out as Ren'Py writes them, to browse (S-035) and back up (S-012).
            Fixtures.save("1-1", name: "The bridge at dusk", minutesAgo: 35, color: .systemOrange, in: saves)
            Fixtures.save("1-2", name: "Before the question", minutesAgo: 190, color: .systemPurple, in: saves)
            Fixtures.save("auto-1", name: "", minutesAgo: 600, color: .systemTeal, in: saves)
            try? Data(repeating: 7, count: 4_000).write(to: saves.appending(path: "persistent"))
            _ = try? SaveBackups.backUp(saves: saves, into: Store.backupsFolder(first.id), at: Date(timeIntervalSinceNow: -86400 * 6))
            _ = try? SaveBackups.backUp(saves: saves, into: Store.backupsFolder(first.id), reason: .beforeRestore, at: Date(timeIntervalSinceNow: -86400 * 2))
            _ = try? SaveBackups.backUp(saves: saves, into: Store.backupsFolder(first.id), at: Date(timeIntervalSinceNow: -7200))
            _ = try? SaveBackups.backUp(saves: saves, into: Store.backupsFolder(first.id), reason: .beforePlay, at: Date(timeIntervalSinceNow: -3600))
            // Discover (S-028) without the network: a few results and their releases.
            let links = { (pairs: [(String, String)]) in pairs.compactMap { pair in URL(string: pair.1).map { VNDBRelease.Link(label: pair.0, url: $0) } } }
            model.discover = DiscoverState(results: [
                VNDBInfo(id: "v90001", title: "Starlit Harbor", developer: "Lantern Works", released: "2025-08-14",
                         description: "A lighthouse keeper's daughter, a missing ship, and one summer to find out what happened."),
                VNDBInfo(id: "v90002", title: "Paper Cranes", developer: "Fold Studio", released: "2024-03-02"),
                VNDBInfo(id: "v90003", title: "Night Train to Aoi", developer: "Kumo Kumo", released: "2026-01-10"),
                VNDBInfo(id: "v90004", title: "The Bakery on Fifth", developer: "Small Oven", released: "2023-11-30"),
                VNDBInfo(id: "v3625", title: "The Question", developer: "ATP Projects", released: "2006-12-03"),
            ], selection: "v90001", searched: true)
            model.releases["v90001"] = [
                VNDBRelease(id: "r1", title: "Starlit Harbor [v1.2]", released: "2026-02-01", platforms: ["win", "mac", "lin"], freeware: false,
                            links: links([("Itch.io", "https://example.itch.io/starlit-harbor"), ("Steam", "https://store.steampowered.com/app/1"), ("Patreon", "https://www.patreon.com/example")])),
                VNDBRelease(id: "r2", title: "Starlit Harbor (French)", released: "2026-04-11", platforms: ["win"], freeware: true, official: false,
                            links: links([("Official website", "https://example.org/fr")])),
            ]
            model.releases["v3625"] = [VNDBRelease(id: "r3", title: "The Question", released: "2006-12-03", platforms: ["win", "mac", "lin"],
                                                   freeware: true, links: links([("Official website", "https://www.renpy.org")]))]
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
