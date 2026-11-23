import Foundation
import Testing
@testable import RenChanKit

// S-037 Open from the Finder and the Dock

@Test func aZipWithAWholeGameIsAGameAndAZipOfScriptsIsAMod() {
    #expect(OpenedFile.zipHoldsGame(["Eternum-0.9/", "Eternum-0.9/game/script.rpa", "Eternum-0.9/renpy/__init__.py", "Eternum-0.9/Eternum.exe"]))
    #expect(OpenedFile.zipHoldsGame(["game/script.rpyc", "lib/py3-mac-universal/python"]))
    #expect(OpenedFile.zipHoldsGame(["Eternum.app/Contents/Resources/autorun/game/script.rpa"]))
    #expect(!OpenedFile.zipHoldsGame(["URM/game/0x52_URM.rpa", "URM/readme.txt"]))
    #expect(!OpenedFile.zipHoldsGame(["walkthrough.rpy"]))
    // game/ and renpy/ three folders down is too deep to be the zip's game.
    #expect(!OpenedFile.zipHoldsGame(["a/b/c/game/x.rpy", "a/b/c/renpy/y.py"]))
}

@Test func openedFilesAreSortedIntoGamesModsAndWalkthroughs() throws {
    let root = Fixture.folder()
    let game = Fixture.game(at: root.appending(path: "Eternum"), files: ["renpy/__init__.py": ""])
    let mod = Fixture.game(at: root.appending(path: "Walkthrough Mod"))
    #expect(OpenedFile.kind(game) == .game)
    #expect(OpenedFile.kind(mod) == .mod)
    #expect(OpenedFile.kind(root.appending(path: "0x52_URM.rpa")) == .mod)
    #expect(OpenedFile.kind(root.appending(path: "script.rpy")) == .mod)
    #expect(OpenedFile.kind(root.appending(path: "Guide.pdf")) == .walkthrough)
    #expect(OpenedFile.kind(root.appending(path: "Old Letters.app")) == .game)
    // Something that is neither goes to Add Game, which says what's missing.
    #expect(OpenedFile.kind(root.appending(path: "Holiday Photos")) == .game)
}

// S-039 Pick a game's language

@Test func languagesComeFromTlFoldersModsAndArchives() throws {
    let base = Fixture.game(at: Fixture.folder().appending(path: "Game"), files: [
        "game/tl/french/script.rpy": "",
        "game/tl/None/common.rpym": "",
        "game/tl/spanish/screens.rpy": "",
    ])
    // An RPA-3.0 archive whose index names a German translation.
    let index = Data("\u{80}\u{02}}q\u{00}(X\u{15}\u{00}\u{00}\u{00}tl/german/script.rpycq\u{01}]q\u{02}X\u{0B}\u{00}\u{00}\u{00}script.rpycq\u{03}".utf8)
    let deflated = try (index as NSData).compressed(using: .zlib) as Data
    let zlib = Data([0x78, 0x9C]) + deflated + Data([0, 0, 0, 0])
    let header = Data(String(format: "RPA-3.0 %016x %08x\n", 34, 0x42424242).utf8)
    try (header + zlib).write(to: base.appending(path: "game/archive.rpa"))
    #expect(GameLanguages.archivePaths(base.appending(path: "game/archive.rpa")).contains { $0.contains("tl/german/script.rpyc") })
    #expect(GameLanguages.find(base: base) == ["french", "german", "spanish"])
    #expect(GameLanguages.find(base: base, extraPaths: ["tl/italian/script.rpy", "tl/notafolder"]) == ["french", "german", "italian", "spanish"])
    #expect(GameLanguages.translationPath("Xgame/tl/russian/a.rpy") == "tl/russian/a.rpy")
    #expect(GameLanguages.translationPath("images/tl/x.png") == nil)
    #expect(GameLanguages.title("french") == "French" && GameLanguages.title("pt_br") == "Pt br")
}

@Test func theLanguageFileGoesInTheCopyAndLeavesWhenOff() throws {
    let copy = Fixture.game(at: Fixture.folder().appending(path: "play"))
    let file = copy.appending(path: "game/\(LanguageLoader.fileName)")
    try LanguageLoader.install("french", copy: copy)
    #expect(try String(contentsOf: file, encoding: .utf8).contains("    config.language = u\"french\""))
    #expect(LanguageLoader.source("fran\"çais").contains(#"u"fran\U00000022\U000000e7ais""#))
    try LanguageLoader.install(nil, copy: copy)
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test func anOldLibraryHasNoLanguage() throws {
    let json = #"[{"id":"7C9D7C2B-4B1F-4C1E-9A8E-1A2B3C4D5E6F","title":"A","sourcePath":"/a","kind":"folder","basePath":"/a","added":"2026-11-01T10:00:00Z"}]"#
    let url = Fixture.folder().appending(path: "library.json")
    try json.write(to: url, atomically: true, encoding: .utf8)
    #expect(try LibraryFile.load(url).first?.language == nil)
}

// S-038 Back up saves before each play

@Test func savesAreBackedUpBeforePlayOnlyWhenTheyChangedAndOnlyFiveKept() throws {
    let root = Fixture.folder()
    let saves = root.appending(path: "saves", directoryHint: .isDirectory)
    let backups = root.appending(path: "Backups", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
    // No saves yet: nothing to back up.
    #expect(try SaveBackups.backUpBeforePlay(saves: saves, into: backups) == nil)
    let file = saves.appending(path: "1-1-LT1.save")
    var day = Date(timeIntervalSince1970: 1_800_000_000)
    func play() throws -> SaveBackup? {
        try "save \(day)".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: day], ofItemAtPath: file.path)
        day += 3600
        return try SaveBackups.backUpBeforePlay(saves: saves, into: backups, keep: 5, at: day)
    }
    #expect(try play()?.reason == .beforePlay)
    // Nothing changed since: no new backup.
    #expect(try SaveBackups.backUpBeforePlay(saves: saves, into: backups, at: day + 60) == nil)
    let manual = try SaveBackups.backUp(saves: saves, into: backups, at: day + 120)
    for _ in 0..<7 { day += 3600; _ = try play() }
    let list = SaveBackups.list(backups)
    #expect(list.filter { $0.reason == .beforePlay }.count == 5)
    // Backups the person made are never pruned.
    #expect(list.contains { $0.id == manual.id })
}

// S-040 Change persistent data

@Test func theSaveToolHasPersistentCommands() {
    let out = URL(fileURLWithPath: "/tmp/out.json")
    #expect(SaveTool.persistentDumpArguments(output: out) == ["renchan_saves", "pdump", "-", "/tmp/out.json"])
    #expect(SaveTool.unlockImagesArguments(output: out) == ["renchan_saves", "unlock", "-", "/tmp/out.json"])
    #expect(SaveTool.persistentSetArguments(changes: URL(fileURLWithPath: "/tmp/c.json"), output: out) == ["renchan_saves", "pset", "-", "/tmp/c.json", "/tmp/out.json"])
    #expect(SaveTool.source.contains("renpy.save_persistent()") && SaveTool.source.contains("_seen_images"))
}
