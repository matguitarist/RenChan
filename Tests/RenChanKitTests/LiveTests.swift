import Foundation
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
