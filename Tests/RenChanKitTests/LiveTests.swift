import Foundation
import ImageIO
import ProcessKit
import Testing
@testable import RenChanKit

/// Live checks against renpy.org and real Ren'Py. Off unless RENCHAN_LIVE=1:
///   RENCHAN_LIVE=1 swift test --filter Live
/// RENCHAN_LIVE_GAME=<base folder> also plays that game for five seconds on the runtime it needs.
/// Ren'Py writes to ~/Library/RenPy, so HOME points at a temp folder.
private let live = ProcessInfo.processInfo.environment["RENCHAN_LIVE"] == "1"

@Suite(.enabled(if: live), .serialized)
struct Live {
    static let store = RuntimeStore(folder: FileManager.default.temporaryDirectory.appending(path: "RenChanLive/Runtimes"))

    @Test(arguments: [RuntimeCatalog.python2, RuntimeCatalog.python3])
    func downloadsAndInstallsARuntime(version: String) async throws {
        if Self.store.runtime(version) == nil {
            try await RuntimeDownload.install(version, into: Self.store) { _, _ in }
        }
        let runtime = try #require(Self.store.runtime(version))
        #expect(runtime.isUniversal)
        let python = try #require(runtime.python)
        #expect(try await Shell.run(python.path, ["-EO", "-c", "import sys; print(sys.version)"]).succeeded)
    }

    /// S-010: three known Ren'Py games are found by title, first.
    @Test(arguments: [("Katawa Shoujo", "v945"), ("Doki Doki Literature Club", "v21905"), ("Butterfly Soup", "v21875")])
    func matchesAKnownGameOnVNDB(title: String, id: String) async throws {
        let found = try await VNDB.search(title)
        #expect(found.first?.id == id, "\(found.prefix(3).map { "\($0.id) \($0.title)" })")
        let details = try await VNDB.details(id)
        #expect(details?.imageURL != nil && details?.developer != nil)
        let cover = Fixture.folder().appending(path: "cover")
        try await VNDB.downloadCover(try #require(details?.imageURL.flatMap(URL.init(string:))), to: cover)
        #expect(((try? Data(contentsOf: cover))?.count ?? 0) > 1000)
    }

    /// S-028: Discover finds Eternum among Ren'Py games, with an official release and its store links.
    @Test func discoversARenPyGameAndItsDownloadPages() async throws {
        let found = try await VNDB.search("Eternum", renpyOnly: true)
        #expect(found.first?.id == "v31929")
        let releases = try await VNDB.releases("v31929")
        #expect(releases.first?.official == true && releases.first?.links.isEmpty == false)
        #expect(try await !VNDB.search("", renpyOnly: true).isEmpty)
    }

    /// S-014: Grayscale on a red screen gives gray, on the 7.x and the 8.x runtime. Ren'Py takes its own screenshot.
    @Test(arguments: [RuntimeCatalog.python2, RuntimeCatalog.python3])
    func aFilterChangesWhatTheGameShows(version: String) async throws {
        if Self.store.runtime(version) == nil {
            try await RuntimeDownload.install(version, into: Self.store) { _, _ in }
        }
        let runtime = try #require(Self.store.runtime(version))
        let root = Fixture.folder()
        /// `then`: Ren'Py lines run after the first screenshot, before a second one 2.5 s later, which is returned instead.
        let sepia = try CustomFilter.parse("""
        // {"name": "Sepia"}
        c = mix(c, vec3(dot(c, vec3(0.393, 0.769, 0.189)), dot(c, vec3(0.349, 0.686, 0.168)), dot(c, vec3(0.272, 0.534, 0.131))), s);
        """, file: "Sepia.glsl")
        func shoot(_ setting: FilterSetting?, name: String? = nil, then: String? = nil) throws -> (r: Int, g: Int, b: Int) {
            let name = name ?? setting?.filter.rawValue ?? "none"
            let copy = root.appending(path: "play-\(name)")
            let shot = root.appending(path: "shot-\(name).png")
            let first = root.appending(path: "shot-\(name)-first.png")
            Fixture.game(at: copy, files: ["game/script.rpy": then.map { more in """
            label start:
                scene expression Solid("#ff0000")
                pause 1.0
                $ renpy.screenshot(\"\(first.path)\")
                \(more)
                pause 2.5
                $ renpy.screenshot(\"\(shot.path)\")
                $ renpy.quit()
            """ } ?? """
            label start:
                scene expression Solid("#ff0000")
                pause 1.0
                $ renpy.screenshot(\"\(shot.path)\")
                $ renpy.quit()
            """])
            #expect(try FilterLoader.install(setting, runtime: version, copy: copy, custom: [sepia]) == .layerTransforms)
            let home = root.appending(path: "home")
            let plan = LaunchPlan(runtime: runtime, copy: copy, outputFile: root.appending(path: "run.log"), environment: ["HOME": home.path])
            let process = try plan.makeProcess()
            try process.run()
            let deadline = Date().addingTimeInterval(60)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            if process.isRunning { process.terminate() }
            let log = (try? String(contentsOf: plan.outputFile, encoding: .utf8)) ?? ""
            let source = try #require(CGImageSourceCreateWithURL(shot as CFURL, nil), "no screenshot; log: \(log.suffix(1500))")
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
            return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
        }
        let plain = try shoot(nil)
        #expect(plain.r > 200 && plain.g < 40 && plain.b < 40, "without a filter: \(plain)")
        let gray = try shoot(FilterSetting(filter: .grayscale))
        #expect(abs(gray.r - gray.g) < 12 && abs(gray.g - gray.b) < 12 && gray.r > 40 && gray.r < 120, "grayscale: \(gray)")
        // Every filter's shader compiles and draws: a GLSL mistake would only show when Ren'Py renders.
        for filter in ScreenFilter.allCases where filter != .grayscale {
            let color = try shoot(FilterSetting(filter: filter))
            #expect(color.r > 60, "\(filter): \(color)")
            if [.nightWarmth, .crt, .sharpen, .fsrSharpen, .fsrUpscale].contains(filter) { continue }
            // Daltonizing moves some of the red into green or blue.
            #expect(color.g > 10 || color.b > 10, "\(filter) didn't change red: \(color)")
        }
        // S-015: Grayscale at 0 shows red; once the strength file says 1, the running game turns gray.
        let live = FilterLoader.liveFile(root.appending(path: "play-live"))
        let tuned = try shoot(FilterSetting(filter: .grayscale, strength: 0), name: "live",
                              then: "$ open(\"\(live.path)\", \"w\").write(\"1.0\")")
        #expect(abs(tuned.r - tuned.g) < 12 && tuned.r < 120, "after tuning live: \(tuned)")
        // Switching while the game runs: Grayscale, then Sepia, which the loader compiles on the spot.
        let swapCopy = root.appending(path: "play-swap")
        let sepiaState = root.appending(path: "sepia-state.json")
        FilterLoader.update(FilterSetting(custom: "Sepia.glsl"), custom: [sepia], copy: root)
        try FileManager.default.moveItem(at: FilterLoader.liveFile(root), to: sepiaState)
        let swapped = try shoot(FilterSetting(filter: .grayscale), name: "swap",
                                then: "$ open(\"\(FilterLoader.liveFile(swapCopy).path)\", \"w\").write(open(\"\(sepiaState.path)\").read())")
        #expect(swapped.r > swapped.g && swapped.g > swapped.b && swapped.g > 40, "after switching to sepia live: \(swapped)")
        // Switching live to a filter that reads its neighbours (v_tex_coord) compiles too, as it does at launch.
        let crtCopy = root.appending(path: "play-swapcrt")
        let crtState = root.appending(path: "crt-state.json")
        FilterLoader.update(FilterSetting(filter: .crt), custom: [sepia], copy: root)
        try FileManager.default.moveItem(at: FilterLoader.liveFile(root), to: crtState)
        let crt = try shoot(FilterSetting(filter: .grayscale), name: "swapcrt",
                            then: "$ open(\"\(FilterLoader.liveFile(crtCopy).path)\", \"w\").write(open(\"\(crtState.path)\").read())")
        #expect((FilterLoader.lastError(copy: crtCopy) ?? "").isEmpty, "CRT live: \(FilterLoader.lastError(copy: crtCopy) ?? "")")
        #expect(crt.r > crt.g + 40, "after switching to CRT live: \(crt)")
        // A shader with a mistake doesn't stop the game: it keeps Grayscale, and the error is there for RenChan.
        let brokenCopy = root.appending(path: "play-broken")
        let brokenState = root.appending(path: "broken-state.json")
        let broken = try CustomFilter.parse("// {\"name\": \"Broken\"}\nc = vec3(oops);", file: "Broken.glsl")
        FilterLoader.update(FilterSetting(custom: "Broken.glsl"), custom: [broken], copy: root)
        try FileManager.default.moveItem(at: FilterLoader.liveFile(root), to: brokenState)
        let kept = try shoot(FilterSetting(filter: .grayscale), name: "broken",
                             then: "$ open(\"\(FilterLoader.liveFile(brokenCopy).path)\", \"w\").write(open(\"\(brokenState.path)\").read())")
        #expect(abs(kept.r - kept.g) < 12 && kept.r > 40, "a broken shader kept grayscale: \(kept)")
        #expect(FilterLoader.lastError(copy: brokenCopy)?.contains("oops") == true, "the error names the mistake: \(FilterLoader.lastError(copy: brokenCopy) ?? "none")")
        print("broken shader error: \(FilterLoader.lastError(copy: brokenCopy) ?? "none")")
        // S-031: FSR Upscale draws from the game's resolution: a 640×360 game in a 1920×1080 window keeps a hard edge
        // narrower than Ren'Py's own bilinear scaling.
        /// `onScreen`: the white half is a Solid in a screen, which Ren'Py draws at the window's resolution, as it does text.
        func edgeWidth(_ setting: FilterSetting?, onScreen: Bool = false) throws -> Int {
            let name = "edge-\(setting?.filter.rawValue ?? "none")\(onScreen ? "-screen" : "")"
            let copy = root.appending(path: "play-\(name)")
            let shot = root.appending(path: "shot-\(name).png")
            Fixture.game(at: copy, files: [
                "game/options.rpy": "init -10 python:\n    config.screen_width = 640\n    config.screen_height = 360\n    config.physical_width = 1920\n    config.physical_height = 1080\n",
                "game/script.rpy": """
                screen renchan_edge():
                    add Solid("#ffffff", xsize=320, ysize=360) xpos 320
                label start:
                    \(onScreen ? "scene expression Solid(\"#000000\")\n    show screen renchan_edge" : "scene expression \"edge.png\"")
                    pause 1.0
                    $ renpy.screenshot(\"\(shot.path)\")
                    $ renpy.quit()
                """])
            // A picture at the game's size, black on the left half and white on the right: what Ren'Py scales up.
            var pixels = [UInt8](repeating: 0, count: 640 * 360 * 4)
            for y in 0..<360 { for x in 320..<640 { for c in 0..<3 { pixels[(y * 640 + x) * 4 + c] = 255 } } }
            for i in 0..<(640 * 360) { pixels[i * 4 + 3] = 255 }
            let picture = try #require(CGContext(data: &pixels, width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: 640 * 4,
                                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
            let destination = try #require(CGImageDestinationCreateWithURL(copy.appending(path: "game/edge.png") as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, picture, nil)
            #expect(CGImageDestinationFinalize(destination))
            try FilterLoader.install(setting, runtime: version, copy: copy)
            let plan = LaunchPlan(runtime: runtime, copy: copy, outputFile: root.appending(path: "\(name).log"), environment: ["HOME": root.appending(path: "home").path])
            let process = try plan.makeProcess()
            try process.run()
            let deadline = Date().addingTimeInterval(60)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
            let source = try #require(CGImageSourceCreateWithURL(shot as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            var row = [UInt8](repeating: 0, count: image.width * 4)
            let context = try #require(CGContext(data: &row, width: image.width, height: 1, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                 space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: -image.height / 2, width: image.width, height: image.height))
            // Pixels between dark and light, across the left edge.
            return stride(from: 0, to: image.width / 2 + image.width / 4, by: 1).filter { row[$0 * 4] > 2 && row[$0 * 4] < 253 }.count
        }
        let fsr = try shoot(FilterSetting(filter: .fsrUpscale), name: "fsr")
        #expect(fsr.r > 200 && fsr.g < 40, "FSR on red: \(fsr)")
        let sharpened = try shoot(FilterSetting(filter: .fsrSharpen), name: "fsr-sharpen")
        #expect(sharpened.r > 200 && sharpened.g < 40, "FSR Sharpen on red: \(sharpened)")
        let plainEdge = try edgeWidth(nil), fsrEdge = try edgeWidth(FilterSetting(filter: .fsrUpscale))
        print("edge width: plain \(plainEdge), FSR \(fsrEdge)")
        #expect(plainEdge > 0 && fsrEdge < plainEdge, "FSR edge \(fsrEdge) vs plain \(plainEdge)")
        // Screens (text, the dialogue box, menus) aren't upscaled from the game's size: their edges stay as hard as without FSR.
        let plainScreen = try edgeWidth(nil, onScreen: true), fsrScreen = try edgeWidth(FilterSetting(filter: .fsrUpscale), onScreen: true)
        print("screen edge width: plain \(plainScreen), FSR \(fsrScreen)")
        #expect(fsrScreen <= plainScreen, "FSR screen edge \(fsrScreen) vs plain \(plainScreen)")

        // S-016: a person's own shader runs like a built-in one. Sepia turns pure red brown.
        let brown = try shoot(FilterSetting(custom: "Sepia.glsl"), name: "sepia")
        #expect(brown.r > brown.g && brown.g > brown.b && brown.g > 40, "sepia: \(brown)")
    }

    /// S-018, S-020: a mod placed by ModInstaller runs in real Ren'Py, and RENPY_PATH_TO_SAVES takes the saves.
    @Test(arguments: [RuntimeCatalog.python2, RuntimeCatalog.python3])
    func aModRunsAndModdedSavesStayApart(version: String) async throws {
        if Self.store.runtime(version) == nil {
            try await RuntimeDownload.install(version, into: Self.store) { _, _ in }
        }
        let runtime = try #require(Self.store.runtime(version))
        let root = Fixture.folder()
        let marker = root.appending(path: "mod-ran.txt")
        let base = Fixture.game(at: root.appending(path: "Base"), files: [
            "game/options.rpy": "define config.save_directory = \"renchan-mod-test\"\n",
            "game/script.rpy": "label start:\n    $ renpy.save(\"1-1\")\n    $ renpy.quit()\n",
        ])
        let source = root.appending(path: "Walkthrough")
        try FileManager.default.createDirectory(at: source.appending(path: "game"), withIntermediateDirectories: true)
        try "init python:\n    open(\"\(marker.path)\", \"w\").write(\"yes\")\n".write(to: source.appending(path: "game/walkthrough.rpy"), atomically: true, encoding: .utf8)
        let library = root.appending(path: "Mods")
        let mod = try await ModLibrary.importMod(source, into: library)
        let copy = root.appending(path: "play-modded")
        try WorkingCopy.prepare(base: base, copy: copy, allowFullCopy: true)
        try ModInstaller.apply([mod], root: library, base: base, copy: copy)
        let saves = root.appending(path: "Modded Saves")
        let home = root.appending(path: "home")
        let plan = LaunchPlan(runtime: runtime, copy: copy, outputFile: root.appending(path: "run.log"),
                              environment: ModInstaller.environment(modded: true, saves: saves).merging(["HOME": home.path]) { a, _ in a })
        let process = try plan.makeProcess()
        try process.run()
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
        let log = (try? String(contentsOf: plan.outputFile, encoding: .utf8)) ?? ""
        #expect(FileManager.default.fileExists(atPath: marker.path), "the mod didn't run: \(log.suffix(1500))")
        #expect(FileManager.default.fileExists(atPath: saves.appending(path: "renchan-mod-test/1-1-LT1.save").path), "\(log.suffix(800))")
        #expect(!FileManager.default.fileExists(atPath: home.appending(path: "Library/RenPy/renchan-mod-test/1-1-LT1.save").path))
    }

    /// S-022, S-023, S-024: in real Ren'Py, the API loads, a template mod's hooks run, state is kept, dev tools are on.
    @Test(arguments: [RuntimeCatalog.python2, RuntimeCatalog.python3])
    func theModAPIAndDevToolsWork(version: String) async throws {
        if Self.store.runtime(version) == nil {
            try await RuntimeDownload.install(version, into: Self.store) { _, _ in }
        }
        let runtime = try #require(Self.store.runtime(version))
        let root = Fixture.folder()
        let report = root.appending(path: "report.txt")
        let base = Fixture.game(at: root.appending(path: "Base"), files: ["game/script.rpy": "label start:\n    pause 0.5\n    $ renpy.quit()\n"])
        let library = root.appending(path: "Mods")
        let template = try ModTemplate.create("Sample Mod", into: library)
        // A second mod checks what the API and the template did, from inside the game.
        let checker = root.appending(path: "Checker")
        try FileManager.default.createDirectory(at: checker, withIntermediateDirectories: true)
        try """
        init 20 python:
            def checker_started():
                s = renchan.state("checker")
                s["ran"] = True
                renchan.save_state("checker")
                open("\(report.path)", "w").write("api=%d entries=%s console=%s fast=%s" % (
                    renchan.version, ",".join(l for l, f in renchan.entries()), config.console, config.fast_skipping))
            renchan.on_start(checker_started)
            renchan.keymap("K_F9", checker_started)
        """.write(to: checker.appending(path: "checker.rpy"), atomically: true, encoding: .utf8)
        let check = try await ModLibrary.importMod(checker, into: library)
        let copy = root.appending(path: "play-modded")
        try WorkingCopy.prepare(base: base, copy: copy, allowFullCopy: true)
        try ModInstaller.apply([template, check], root: library, base: base, copy: copy)
        try ModAPI.install(copy: copy)
        try DevToolsLoader.install(DevTools(console: true, fastSkip: true), copy: copy)
        let plan = LaunchPlan(runtime: runtime, copy: copy, outputFile: root.appending(path: "run.log"),
                              environment: ["HOME": root.appending(path: "home").path])
        let process = try plan.makeProcess()
        try process.run()
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
        let log = (try? String(contentsOf: plan.outputFile, encoding: .utf8)) ?? ""
        let text = (try? String(contentsOf: report, encoding: .utf8)) ?? ""
        #expect(text == "api=1 entries=Sample Mod console=True fast=True", "\(text) \(log.suffix(1500))")
        let state = ModAPI.stateFolder(copy).appending(path: "checker.json")
        #expect((try? String(contentsOf: state, encoding: .utf8))?.contains("\"ran\": true") == true)
    }

    /// S-033: a real itch.io page gives a version.
    @Test func aRealItchPageShowsAVersion() async throws {
        let version = try await PageVersion.fetch(URL(string: "https://caribdis.itch.io/eternum")!, userAgent: "RenChan-tests")
        #expect(VersionOrder.compare(version, "0.9") != .orderedAscending, "\(version)")
    }

    /// S-033: a real F95zone thread gives the version in its title.
    @Test func aRealF95zoneThreadShowsAVersion() async throws {
        let version = try await PageVersion.fetch(URL(string: "https://f95zone.to/threads/32469/")!, userAgent: "RenChan-tests")
        #expect(version == "Final")
    }

    /// S-035, S-036: a real save is listed, its variables read and changed, and Ren'Py loads the changed save.
    @Test(arguments: [RuntimeCatalog.python2, RuntimeCatalog.python3])
    func aSaveIsReadChangedAndStillLoads(version: String) async throws {
        if Self.store.runtime(version) == nil {
            try await RuntimeDownload.install(version, into: Self.store) { _, _ in }
        }
        let runtime = try #require(Self.store.runtime(version))
        let root = Fixture.folder()
        let home = root.appending(path: "home")
        let report = root.appending(path: "loaded.txt")
        let marker = root.appending(path: "loadme")
        let script = """
        define config.save_directory = "renchan-save-test"
        default points = 3
        default hero = "Ana"
        default met = False
        default bag = ["key"]
        init python:
            def _after():
                open("\(report.path)", "w").write("%s %s %s" % (store.points, store.hero, store.met))
                renpy.quit()
            config.after_load_callbacks.append(_after)
        label start:
            if renpy.os.path.exists("\(marker.path)"):
                $ renpy.load("1-1")
            $ points = 7
            $ renpy.save("1-1", "Before the bridge")
            $ renpy.save("1-2", "Second")
            $ renpy.quit()
        """
        let copy = Fixture.game(at: root.appending(path: "Game"), files: ["game/script.rpy": script])
        func run(_ arguments: [String] = []) async throws -> String {
            let plan = LaunchPlan(runtime: runtime, copy: copy, outputFile: root.appending(path: "run-\(UUID()).log"),
                                  environment: ["HOME": home.path], arguments: arguments)
            let process = try plan.makeProcess()
            try process.run()
            let deadline = Date().addingTimeInterval(90)
            while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
            if process.isRunning { process.terminate() }
            return (try? String(contentsOf: plan.outputFile, encoding: .utf8)) ?? ""
        }
        // Play once: the game saves in slot 1-1 and quits.
        var log = try await run()
        let folder = home.appending(path: "Library/RenPy/renchan-save-test")
        let saves = SaveList.list(in: folder)
        #expect(Set(saves.map(\.slot)) == ["1-1", "1-2"], "\(log.suffix(1500))")
        #expect(saves.first { $0.slot == "1-1" }?.name == "Before the bridge" && saves.first?.screenshot() != nil)
        // Read and change it.
        try SaveTool.install(copy: copy)
        let out = root.appending(path: "dump.json")
        log = try await run(SaveTool.dumpArguments(slot: "1-1", output: out))
        let dump = try SaveTool.readReport(out)
        let vars = Dictionary(uniqueKeysWithValues: (dump.variables ?? []).map { ($0.name, $0) })
        // The save holds the state from the start of the statement it was made in, where points was still 3.
        #expect(vars["points"]?.value == "3" && vars["points"]?.kind == .int, "\(String(describing: dump)) \(log.suffix(1500))")
        #expect(vars["hero"]?.value == "Ana" && vars["met"]?.value == "false" && vars["bag"]?.editable == false)
        let changes = root.appending(path: "changes.json")
        try SaveTool.writeChanges(["points": 42, "hero": "Bo", "met": true, "bag": 1], to: changes)
        log = try await run(SaveTool.setArguments(slot: "1-1", changes: changes, output: out))
        let set = try SaveTool.readReport(out)
        #expect(set.changed == ["hero", "met", "points"] && set.refused == ["bag"], "\(String(describing: set)) \(log.suffix(1500))")
        // Ren'Py loads the changed save without asking, and sees the new values.
        try "".write(to: marker, atomically: true, encoding: .utf8)
        log = try await run()
        #expect((try? String(contentsOf: report, encoding: .utf8)) == "42 Bo True", "\(log.suffix(2000))")
        // The same change in every save at once.
        try SaveTool.writeChanges(["met": true], to: changes)
        log = try await run(SaveTool.setArguments(slots: ["1-1", "1-2"], changes: changes, output: out))
        let both = try SaveTool.readReport(out)
        #expect(both.changed == ["met"] && both.saves == 2, "\(String(describing: both)) \(log.suffix(1500))")
        log = try await run(SaveTool.dumpArguments(slot: "1-2", output: out))
        #expect(try SaveTool.readReport(out).variables?.first { $0.name == "met" }?.value == "true", "\(log.suffix(1500))")
    }

    /// Runs a game in `copy` with HOME in `home` until it quits; returns its output.
    static func runGame(_ runtime: Runtime, copy: URL, home: URL, arguments: [String] = []) async throws -> String {
        let plan = LaunchPlan(runtime: runtime, copy: copy, outputFile: copy.deletingLastPathComponent().appending(path: "run-\(UUID()).log"),
                              environment: ["HOME": home.path], arguments: arguments)
        let process = try plan.makeProcess()
        try process.run()
        let deadline = Date().addingTimeInterval(90)
        while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(200)) }
        if process.isRunning { process.terminate() }
        return (try? String(contentsOf: plan.outputFile, encoding: .utf8)) ?? ""
    }

    /// S-039: the game starts in the language RenChan sets, and its translated text shows.
    @Test(arguments: [RuntimeCatalog.python2, RuntimeCatalog.python3])
    func aGameStartsInTheChosenLanguage(version: String) async throws {
        if Self.store.runtime(version) == nil {
            try await RuntimeDownload.install(version, into: Self.store) { _, _ in }
        }
        let runtime = try #require(Self.store.runtime(version))
        let root = Fixture.folder()
        let report = root.appending(path: "language.txt")
        let copy = Fixture.game(at: root.appending(path: "Game"), files: [
            "game/script.rpy": """
            label start:
                $ open("\(report.path)", "w").write("%s %s" % (_preferences.language, __("Hello")))
                $ renpy.quit()
            """,
            "game/tl/french/strings.rpy": "translate french strings:\n    old \"Hello\"\n    new \"Bonjour\"\n",
        ])
        #expect(GameLanguages.find(base: copy) == ["french"])
        try LanguageLoader.install("french", copy: copy)
        var log = try await Self.runGame(runtime, copy: copy, home: root.appending(path: "home"))
        #expect((try? String(contentsOf: report, encoding: .utf8)) == "french Bonjour", "\(log.suffix(1500))")
        // Game's Choice: the file leaves, and Ren'Py starts in the language it used last.
        try LanguageLoader.install(nil, copy: copy)
        log = try await Self.runGame(runtime, copy: copy, home: root.appending(path: "home"))
        var text = (try? String(contentsOf: report, encoding: .utf8)) ?? ""
        #expect(text == "french Bonjour", "\(text) \(log.suffix(1500))")
        // Original: back to the language the game was written in.
        try LanguageLoader.install(LanguageLoader.original, copy: copy)
        log = try await Self.runGame(runtime, copy: copy, home: root.appending(path: "home"))
        text = (try? String(contentsOf: report, encoding: .utf8)) ?? ""
        #expect(text == "None Hello", "\(text) \(log.suffix(1500))")
    }

    /// S-042: the gallery finds a loose picture and one inside a real RPA-3.0 archive, and reads both without Ren'Py.
    @Test(arguments: [RuntimeCatalog.python2, RuntimeCatalog.python3])
    func picturesAreFoundInFilesAndArchives(version: String) async throws {
        for needed in [version, RuntimeCatalog.python3] where Self.store.runtime(needed) == nil {
            try await RuntimeDownload.install(needed, into: Self.store) { _, _ in }
        }
        let runtime = try #require(Self.store.runtime(version))
        let root = Fixture.folder()
        let copy = Fixture.game(at: root.appending(path: "Game"), files: ["game/script.rpy": """
            define config.save_directory = "renchan-pictures-test"
            label start:
                $ renpy.quit()
            """])
        // A 1x1 PNG, loose and archived; the archived one keeps its first bytes in the index, like Ren'Py 7's archiver can.
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
        let images = copy.appending(path: "game/images")
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try png.write(to: images.appending(path: "loose.png"))
        let raw = root.appending(path: "raw.png")
        try png.write(to: raw)
        let maker = """
            import sys, pickle, zlib
            data = open(sys.argv[1], "rb").read()
            key = 0x42424242
            out = open(sys.argv[2], "wb")
            out.write(b"RPA-3.0 %016x %08x\\n" % (0, key))
            offset = out.tell()
            out.write(data[3:])
            index = {u"images/cg/archived.png": [(offset ^ key, (len(data) - 3) ^ key, data[:3])]}
            at = out.tell()
            out.write(zlib.compress(pickle.dumps(index, 2)))
            out.seek(0)
            out.write(b"RPA-3.0 %016x %08x\\n" % (at, key))
            out.close()
            """
        let python = try #require(Self.store.runtime(RuntimeCatalog.python3)?.python)
        #expect(try await Shell.run(python.path, ["-I", "-c", maker, raw.path, copy.appending(path: "game/archive.rpa").path]).succeeded)
        let home = root.appending(path: "home")
        try SaveTool.install(copy: copy)
        let out = root.appending(path: "out.json")
        let log = try await Self.runGame(runtime, copy: copy, home: home, arguments: SaveTool.picturesArguments(output: out))
        let pictures = try SaveTool.readReport(out).pictures ?? []
        #expect(pictures.map(\.path) == ["images/cg/archived.png", "images/loose.png"], "\(log.suffix(2000))")
        for picture in pictures {
            #expect(try picture.data() == png, "\(picture)")
            #expect(picture.thumbnail(maxPixels: 64) != nil)
        }
    }

    /// S-040: persistent values are read and changed, every image is marked as seen, and the game reads them without asking.
    @Test(arguments: [RuntimeCatalog.python2, RuntimeCatalog.python3])
    func persistentDataIsReadChangedAndUnlocked(version: String) async throws {
        if Self.store.runtime(version) == nil {
            try await RuntimeDownload.install(version, into: Self.store) { _, _ in }
        }
        let runtime = try #require(Self.store.runtime(version))
        let root = Fixture.folder()
        let home = root.appending(path: "home")
        let report = root.appending(path: "persistent.txt")
        let marker = root.appending(path: "check")
        let copy = Fixture.game(at: root.appending(path: "Game"), files: ["game/script.rpy": """
            define config.save_directory = "renchan-persistent-test"
            default persistent.endings = 1
            default persistent.true_end = False
            default persistent.renders = [{"id": "a", "unlocked": False, "name": "Hawaiian Dream"}, {"id": "b", "unlocked": False, "name": "Pool day"}]
            default persistent.opts = {"hard mode": False}
            default persistent.pair = (1, 2)
            image bg one = Solid("#f00")
            image bg two = Solid("#0f0")
            label scene_one:
                return
            label scene_two:
                "A line nobody has read."
                return
            label start:
                if renpy.os.path.exists("\(marker.path)"):
                    $ open("\(report.path)", "w").write("%s %s %s %s %s %s %s" % (persistent.endings, persistent.true_end, renpy.seen_image("bg two"), persistent.renders[0]["unlocked"], persistent.renders[1]["unlocked"], persistent.opts["hard mode"], renpy.seen_label("scene_two")))
                $ renpy.quit()
            """])
        var log = try await Self.runGame(runtime, copy: copy, home: home)
        try SaveTool.install(copy: copy)
        let out = root.appending(path: "out.json")
        log = try await Self.runGame(runtime, copy: copy, home: home, arguments: SaveTool.persistentDumpArguments(output: out))
        let dump = try SaveTool.readReport(out)
        let vars = Dictionary(uniqueKeysWithValues: (dump.variables ?? []).map { ($0.name, $0) })
        #expect(vars["endings"]?.value == "1" && vars["endings"]?.kind == .int && vars["true_end"]?.value == "false", "\(String(describing: dump)) \(log.suffix(1500))")
        #expect(!vars.keys.contains { $0.hasPrefix("_") } && (dump.images ?? 0) >= 2)
        // Lists and dictionaries open up; each value inside carries its item's name.
        #expect(vars["renders[1].unlocked"]?.kind == .bool && vars["renders[1].unlocked"]?.note == "Pool day", "\(vars.keys.sorted())")
        #expect(vars[#"opts["hard mode"]"#]?.value == "false" && vars["pair"]?.kind == .other && vars["renders"] == nil)
        let changes = root.appending(path: "changes.json")
        try SaveTool.writeChanges(["endings": 3, "true_end": true, "_seen_ever": 1, "nope": 2, "renders[1].unlocked": true,
                                   #"opts["hard mode"]"#: true, "renders[9].unlocked": true, "pair": 5], to: changes)
        log = try await Self.runGame(runtime, copy: copy, home: home, arguments: SaveTool.persistentSetArguments(changes: changes, output: out))
        let set = try SaveTool.readReport(out)
        #expect(set.changed == [#"opts["hard mode"]"#, "endings", "renders[1].unlocked", "true_end"].sorted()
                 && set.refused == ["_seen_ever", "nope", "pair", "renders[9].unlocked"], "\(String(describing: set)) \(log.suffix(1500))")
        log = try await Self.runGame(runtime, copy: copy, home: home, arguments: SaveTool.unlockImagesArguments(output: out))
        let unlock = try SaveTool.readReport(out)
        #expect((unlock.unlocked ?? 0) >= 2 && unlock.error == nil, "\(String(describing: unlock)) \(log.suffix(1500))")
        // start ran in the first play; the two scenes never did.
        #expect(dump.labels == 3 && dump.seenLabels == 1, "\(String(describing: dump.labels)) \(String(describing: dump.seenLabels))")
        log = try await Self.runGame(runtime, copy: copy, home: home, arguments: SaveTool.unlockReplaysArguments(output: out))
        let replays = try SaveTool.readReport(out)
        #expect(replays.unlocked == 2 && replays.labels == 3, "\(String(describing: replays)) \(log.suffix(1500))")
        try "".write(to: marker, atomically: true, encoding: .utf8)
        log = try await Self.runGame(runtime, copy: copy, home: home)
        #expect((try? String(contentsOf: report, encoding: .utf8)) == "3 True True False True True True", "\(log.suffix(2000))")
    }

    @Test func playsARealGameFromAClone() async throws {
        let game = ProcessInfo.processInfo.environment["RENCHAN_LIVE_GAME"].map { URL(fileURLWithPath: $0) }
        let base = try #require(game, "set RENCHAN_LIVE_GAME to a game's base folder")
        let detected = VersionDetector.detect(base: base)
        // Like the app: no version found plays on the newest 8.x.
        let version = RuntimeCatalog.choose(version: detected.version, pythonLine: detected.pythonLine) ?? RuntimeCatalog.python3
        if Self.store.runtime(version) == nil {
            try await RuntimeDownload.install(version, into: Self.store) { _, _ in }
        }
        let runtime = try #require(Self.store.runtime(version))
        let root = FileManager.default.temporaryDirectory.appending(path: "RenChanLive/\(UUID().uuidString)")
        let copy = root.appending(path: "play")
        try WorkingCopy.prepare(base: base, copy: copy, allowFullCopy: true)
        let home = root.appending(path: "home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let plan = LaunchPlan(runtime: runtime, copy: copy, outputFile: root.appending(path: "run.log"), environment: ["HOME": home.path])
        let process = try plan.makeProcess()
        try process.run()
        try await Task.sleep(for: .seconds(6))
        let alive = process.isRunning
        process.terminate()
        process.waitUntilExit()
        let output = (try? String(contentsOf: plan.outputFile, encoding: .utf8)) ?? ""
        #expect(alive, "Ren'Py quit early: \(output.suffix(2000))")
        #expect(FileManager.default.fileExists(atPath: home.appending(path: "Library/RenPy").path))
    }
}
