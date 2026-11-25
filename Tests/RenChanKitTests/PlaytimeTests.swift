import FileKit
import Foundation
import ProcessKit
import Testing
@testable import RenChanKit

@Test func timeCountsFromLaunchToQuit() {
    let file = Fixture.folder().appending(path: "session.json")
    let start = Date(timeIntervalSince1970: 1_000_000)
    PlaySession.begin(at: start, file: file)
    #expect(PlaySession.end(at: start.addingTimeInterval(125), file: file) == 125)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    // A second end without a begin adds nothing.
    #expect(PlaySession.end(at: start.addingTimeInterval(500), file: file) == 0)
}

@Test func aCrashStillRecordsTheTime() throws {
    // A run that fails: the fake runtime exits 1 with a traceback; the session still ends with its time.
    let root = Fixture.folder()
    let copy = Fixture.game(at: root.appending(path: "play"), files: ["game/script.rpy": "label start:\n    $ crash()\n"])
    let runtime = fakeRuntime(in: root)
    let plan = LaunchPlan(runtime: runtime, copy: copy, outputFile: root.appending(path: "run.log"))
    let session = root.appending(path: "session.json")
    let started = Date()
    PlaySession.begin(at: started, file: session)
    let output = try plan.start().waitSync()
    #expect(LaunchPlan.exitCode(of: output) != 0)
    let seconds = PlaySession.end(at: started.addingTimeInterval(42), file: session)
    #expect(abs(seconds - 42) < 0.01)
}

@Test func aSessionRenChanMissedCountsToTheLastLogLine() throws {
    let root = Fixture.folder()
    let file = root.appending(path: "session.json")
    let log = root.appending(path: "run.log")
    let start = Date(timeIntervalSince1970: 2_000_000)
    PlaySession.begin(at: start, file: file)
    try "Ren'Py ran".write(to: log, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: start.addingTimeInterval(600)], ofItemAtPath: log.path)
    #expect(PlaySession.recover(file: file, lastActivity: log) == 600)
    #expect(PlaySession.recover(file: file, lastActivity: log) == nil)
}

@Test func anOldLibraryOpensWithDefaults() throws {
    let json = """
    [{"added":"2026-11-22T10:00:00Z","basePath":"/g","id":"\(UUID().uuidString)","kind":"folder","sourcePath":"/g","title":"Old"}]
    """
    let url = Fixture.folder().appending(path: "library.json")
    try json.write(to: url, atomically: true, encoding: .utf8)
    let games = try JSONFile<[Game]>(url).load() ?? []
    #expect(games.first?.playtime == 0)
}
