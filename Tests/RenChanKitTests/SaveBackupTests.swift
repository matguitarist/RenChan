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

@Test func aBackupOfModdedSavesSaysSoAndOldBackupsDont() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "renchan-modded-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let saves = root.appending(path: "saves")
    try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
    try Data("a".utf8).write(to: saves.appending(path: "1-1-LT1.save"))
    let backups = root.appending(path: "b")
    let day = Date(timeIntervalSince1970: 1_800_000_000)
    let modded = try SaveBackups.backUp(saves: saves, into: backups, reason: .beforeEdit, modded: true, at: day)
    #expect(modded.modded && SaveBackups.list(backups).first?.modded == true)
    // A restore of it backs up what it replaces as modded saves too.
    let before = try #require(try SaveBackups.restore(modded, saves: saves, root: backups, at: day + 60))
    #expect(before.modded)
    // A backup.json from before 0.9.2 has no "modded": the game's own saves.
    let old = backups.appending(path: "old")
    try FileManager.default.createDirectory(at: old.appending(path: "saves"), withIntermediateDirectories: true)
    try Data(#"{"date": 1700000000, "reason": "manual"}"#.utf8).write(to: old.appending(path: "backup.json"))
    #expect(SaveBackups.list(backups).first { $0.id == "old" }?.modded == false)
}

@Test func aNewerModdedBackupDoesntSkipTheBackupBeforePlay() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "renchan-beforeplay-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let saves = root.appending(path: "saves")
    try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
    try Data("a".utf8).write(to: saves.appending(path: "1-1-LT1.save"))
    let backups = root.appending(path: "b")
    try SaveBackups.backUp(saves: saves, into: backups, reason: .beforeEdit, modded: true, at: .now + 3600)
    #expect(try SaveBackups.backUpBeforePlay(saves: saves, into: backups)?.modded == false)
}

@Test func removingAGameKeepsAsideOnlyFoldersWithFiles() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "renchan-removed-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let moddedSaves = root.appending(path: "Modded Saves/game-1")
    try FileManager.default.createDirectory(at: moddedSaves, withIntermediateDirectories: true)
    try Data("a".utf8).write(to: moddedSaves.appending(path: "1-1-LT1.save"))
    let walkthroughs = root.appending(path: "Walkthroughs")
    try FileManager.default.createDirectory(at: walkthroughs, withIntermediateDirectories: true)
    let missing = root.appending(path: "Mod State")
    let kept = try #require(try RemovedGame.keepAside([root.appending(path: "Modded Saves"), walkthroughs, missing], title: "Act 1: Spring/Summer", in: root))
    #expect(kept.lastPathComponent == "Act 1- Spring-Summer")
    #expect(FileManager.default.fileExists(atPath: kept.appending(path: "Modded Saves/game-1/1-1-LT1.save").path))
    #expect(!FileManager.default.fileExists(atPath: kept.appending(path: "Walkthroughs").path))
    #expect(try RemovedGame.keepAside([walkthroughs], title: "Empty", in: root) == nil)
}
