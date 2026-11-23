import Foundation
import Testing
@testable import RenChanKit

@Test func developerToolsGoInTheCopyAndLeaveWhenOff() throws {
    let copy = Fixture.game(at: Fixture.folder().appending(path: "play"))
    let file = copy.appending(path: "game/\(DevToolsLoader.fileName)")
    try DevToolsLoader.install(DevTools(console: true), copy: copy)
    let text = try String(contentsOf: file, encoding: .utf8)
    #expect(text.contains("config.console = True") && !text.contains("fast_skipping"))
    try DevToolsLoader.install(DevTools(console: true, fastSkip: true), copy: copy)
    #expect(try String(contentsOf: file, encoding: .utf8).contains("config.fast_skipping = True"))
    try DevToolsLoader.install(DevTools(), copy: copy)
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test func theCompatibilityReportListsEachGamesLastRun() throws {
    var a = Game(title: "Eternum", sourcePath: "/a", kind: .folder, basePath: "/a", version: RenPyVersion("8.1.3"), pythonLine: .python3)
    a.record(RunRecord(date: Date(timeIntervalSince1970: 1_790_000_000), runtime: "8.6.1", outcome: .failed, exitCode: 1, seconds: 3, error: "NameError: name 'x' is not defined"))
    a.record(RunRecord(date: Date(timeIntervalSince1970: 1_790_100_000), runtime: "8.6.1", outcome: .worked, exitCode: 0, seconds: 3600, modded: true))
    let b = Game(title: "Butterfly Soup", sourcePath: "/b", kind: .folder, basePath: "/b")
    let report = CompatibilityReport.markdown([a, b], app: "RenChan 0.5.0", system: "macOS 26.1", chip: "Apple M4")
    #expect(report.contains("| Butterfly Soup | unknown | ? | — | — | not played | 0/0 |"))
    #expect(report.contains("| Eternum | 8.1.3 | 3 |") && report.contains("| 8.6.1 | worked (mods) | 1/2 |"))
    #expect(report.firstRange(of: "Butterfly")!.lowerBound < report.firstRange(of: "Eternum")!.lowerBound)
    for _ in 0..<25 { a.record(RunRecord(date: .now, runtime: "8.6.1", outcome: .worked, exitCode: 0, seconds: 1)) }
    #expect(a.runs.count == 20)
    #expect(try JSONSerialization.jsonObject(with: CompatibilityReport.json([a, b])) is [Any])
}
