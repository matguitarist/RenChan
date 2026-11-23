import Foundation
import ImageIO
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
        let python = Process()
        python.executableURL = runtime.python
        python.arguments = ["-EO", "-c", "import sys; print(sys.version)"]
        try python.run()
        python.waitUntilExit()
        #expect(python.terminationStatus == 0)
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
            #expect(try FilterLoader.install(setting, runtime: version, copy: copy, custom: [sepia]) == (setting == nil ? .unsupported : .layerTransforms))
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
        // S-031: FSR Upscale draws from the game's resolution: a 640×360 game in a 1920×1080 window keeps a hard edge
        // narrower than Ren'Py's own bilinear scaling.
        func edgeWidth(_ setting: FilterSetting?) throws -> Int {
            let name = "edge-\(setting?.filter.rawValue ?? "none")"
            let copy = root.appending(path: "play-\(name)")
            let shot = root.appending(path: "shot-\(name).png")
            Fixture.game(at: copy, files: [
                "game/options.rpy": "init -10 python:\n    config.screen_width = 640\n    config.screen_height = 360\n    config.physical_width = 1920\n    config.physical_height = 1080\n",
                "game/script.rpy": """
                label start:
                    scene expression "edge.png"
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
            return stride(from: 0, to: image.width / 2 + image.width / 4, by: 1).filter { row[$0 * 4] > 10 && row[$0 * 4] < 245 }.count
        }
        let fsr = try shoot(FilterSetting(filter: .fsrUpscale), name: "fsr")
        #expect(fsr.r > 200 && fsr.g < 40, "FSR on red: \(fsr)")
        let sharpened = try shoot(FilterSetting(filter: .fsrSharpen), name: "fsr-sharpen")
        #expect(sharpened.r > 200 && sharpened.g < 40, "FSR Sharpen on red: \(sharpened)")
        let plainEdge = try edgeWidth(nil), fsrEdge = try edgeWidth(FilterSetting(filter: .fsrUpscale))
        print("edge width: plain \(plainEdge), FSR \(fsrEdge)")
        #expect(plainEdge > 0 && fsrEdge < plainEdge, "FSR edge \(fsrEdge) vs plain \(plainEdge)")

        // S-016: a person's own shader runs like a built-in one. Sepia turns pure red brown.
        let brown = try shoot(FilterSetting(custom: "Sepia.glsl"), name: "sepia")
        #expect(brown.r > brown.g && brown.g > brown.b && brown.g > 40, "sepia: \(brown)")
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
