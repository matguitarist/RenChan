import Foundation
import Testing
@testable import RenChanKit

@Test func aRestoreKeepsABackupOfTheSavesItReplaces() throws {
    let root = Fixture.folder()
    let saves = root.appending(path: "RenPy/game-1", directoryHint: .isDirectory)
    let working = root.appending(path: "play/game/saves", directoryHint: .isDirectory)
    let backups = root.appending(path: "Backups/one", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
    try "first".write(to: saves.appending(path: "1-1-LT1.save"), atomically: true, encoding: .utf8)

    let monday = Date(timeIntervalSince1970: 1_800_000_000)
    let backup = try SaveBackups.backUp(saves: saves, into: backups, at: monday)
    #expect(backup.saveCount == 1 && backup.reason == .manual && backup.size > 0)

    // Play on: the first save changes and a second appears, in both places Ren'Py keeps them.
    for folder in [saves, working] {
        try "later".write(to: folder.appending(path: "1-1-LT1.save"), atomically: true, encoding: .utf8)
        try "new".write(to: folder.appending(path: "1-2-LT1.save"), atomically: true, encoding: .utf8)
    }

    let before = try #require(try SaveBackups.restore(backup, saves: saves, workingSaves: working, root: backups, at: monday.addingTimeInterval(60)))
    #expect(before.reason == .beforeRestore && before.saveCount == 2)
    for folder in [saves, working] {
        #expect(try String(contentsOf: folder.appending(path: "1-1-LT1.save"), encoding: .utf8) == "first")
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "1-2-LT1.save").path))
    }
    #expect(SaveBackups.list(backups).map(\.reason) == [.beforeRestore, .manual])
}

@Test func twoBackupsInOneSecondBothStay() throws {
    let root = Fixture.folder()
    let saves = root.appending(path: "saves", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try SaveBackups.backUp(saves: saves, into: root.appending(path: "b"), at: now)
    try SaveBackups.backUp(saves: saves, into: root.appending(path: "b"), at: now)
    #expect(SaveBackups.list(root.appending(path: "b")).count == 2)
    #expect(throws: (any Error).self) { try SaveBackups.backUp(saves: root.appending(path: "missing"), into: root.appending(path: "b")) }
}
