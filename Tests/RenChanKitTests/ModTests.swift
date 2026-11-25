import FileKit
import Foundation
import ProcessKit
import Testing
@testable import RenChanKit

private func zip(_ folder: URL, to zip: URL) throws {
    try Shell.runSync("/usr/bin/ditto", ["-c", "-k", "--keepParent", folder.path, zip.path]).check()
}

@Test func aZipsGameFolderIsFoundAtAnyDepth() async throws {
    let root = Fixture.folder()
    let made = root.appending(path: "Eternum_Walkthrough_Mod-0.8")
    try FileManager.default.createDirectory(at: made.appending(path: "Eternum-0.8-pc/game/mod"), withIntermediateDirectories: true)
    try "label wt: pass".write(to: made.appending(path: "Eternum-0.8-pc/game/walkthrough.rpy"), atomically: true, encoding: .utf8)
    try "x".write(to: made.appending(path: "Eternum-0.8-pc/game/mod/hint.png"), atomically: true, encoding: .utf8)
    try "read me".write(to: made.appending(path: "README.txt"), atomically: true, encoding: .utf8)
    let archive = root.appending(path: "Eternum_Walkthrough_Mod-0.8.zip")
    try zip(made, to: archive)
    let library = root.appending(path: "Mods")
    let mod = try await ModLibrary.importMod(archive, into: library)
    #expect(mod.name == "Eternum Walkthrough Mod 0.8")
    #expect(mod.files == ["mod/hint.png", "walkthrough.rpy"])
    #expect(FileManager.default.fileExists(atPath: ModLibrary.folder(mod, root: library).appending(path: "walkthrough.rpy").path))
    // A lone .rpa and a folder of scripts with no game/ folder.
    let rpa = root.appending(path: "0x52_URM.rpa")
    try "rpa".write(to: rpa, atomically: true, encoding: .utf8)
    #expect(try await ModLibrary.importMod(rpa, into: library).files == ["0x52_URM.rpa"])
    let loose = root.appending(path: "Loose/Inner")
    try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)
    try "init: pass".write(to: loose.appending(path: "cheat.rpy"), atomically: true, encoding: .utf8)
    #expect(try await ModLibrary.importMod(root.appending(path: "Loose"), into: library).files == ["cheat.rpy"])
}

@Test func filesWithoutScriptsAreRefused() async throws {
    let root = Fixture.folder()
    let pictures = root.appending(path: "Pictures")
    try FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
    try "x".write(to: pictures.appending(path: "a.png"), atomically: true, encoding: .utf8)
    await #expect(throws: ModError.noScripts) { try await ModLibrary.importMod(pictures, into: root.appending(path: "Mods")) }
    let text = root.appending(path: "notes.txt")
    try "x".write(to: text, atomically: true, encoding: .utf8)
    await #expect(throws: ModError.notAMod) { try await ModLibrary.importMod(text, into: root.appending(path: "Mods")) }
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Mods").path)
            || ModLibrary.children(root.appending(path: "Mods")).isEmpty)
}

@Test func turningAModOffBringsBackTheGamesOwnFiles() async throws {
    let root = Fixture.folder()
    let base = Fixture.game(at: root.appending(path: "Base"), files: ["game/screens.rpy": "screen say(): pass"])
    let copy = root.appending(path: "play-modded")
    try FileManager.default.copyItem(at: base, to: copy)
    try "compiled".write(to: copy.appending(path: "game/screens.rpyc"), atomically: true, encoding: .utf8)
    let library = root.appending(path: "Mods")
    func make(_ name: String, _ files: [String: String]) async throws -> Mod {
        let folder = root.appending(path: name)
        for (path, text) in files {
            try FileManager.default.createDirectory(at: folder.appending(path: path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: folder.appending(path: path), atomically: true, encoding: .utf8)
        }
        return try await ModLibrary.importMod(folder, into: library)
    }
    let a = try await make("A", ["screens.rpy": "screen say(): mod A", "a.rpy": "screen choice(): pass"])
    let b = try await make("B", ["screens.rpy": "screen say(): mod B", "b.rpy": "screen choice(): pass"])
    try ModInstaller.apply([a, b], root: library, base: base, copy: copy)
    let screens = copy.appending(path: "game/screens.rpy")
    #expect(try String(contentsOf: screens, encoding: .utf8) == "screen say(): mod B")
    #expect(!FileManager.default.fileExists(atPath: copy.appending(path: "game/screens.rpyc").path))
    #expect(FileManager.default.fileExists(atPath: copy.appending(path: "game/a.rpy").path))
    // S-019: both replace screens.rpy (B wins) and both define the choice and say screens.
    let conflicts = ModConflicts.find([a, b], root: library)
    #expect(conflicts.contains(ModConflict(kind: .file("screens.rpy"), mods: ["A", "B"])))
    #expect(conflicts.first { $0.kind == .file("screens.rpy") }?.winner == "B")
    #expect(conflicts.contains(ModConflict(kind: .screen("choice"), mods: ["A", "B"])))
    // Only A on: B's files leave; then none: the game's own screens.rpy is back.
    try "compiled b".write(to: copy.appending(path: "game/b.rpyc"), atomically: true, encoding: .utf8)
    try ModInstaller.apply([a], root: library, base: base, copy: copy)
    #expect(!FileManager.default.fileExists(atPath: copy.appending(path: "game/b.rpy").path))
    #expect(!FileManager.default.fileExists(atPath: copy.appending(path: "game/b.rpyc").path))
    #expect(try String(contentsOf: screens, encoding: .utf8) == "screen say(): mod A")
    try ModInstaller.apply([], root: library, base: base, copy: copy)
    #expect(try String(contentsOf: screens, encoding: .utf8) == "screen say(): pass")
    #expect(!FileManager.default.fileExists(atPath: copy.appending(path: "game/a.rpy").path))
}

@Test func moddedPlayKeepsItsOwnSaves() {
    let saves = URL(fileURLWithPath: "/tmp/RenChan/ModdedSaves/x")
    #expect(ModInstaller.environment(modded: true, saves: saves) == ["RENPY_PATH_TO_SAVES": saves.path])
    #expect(ModInstaller.environment(modded: false, saves: saves).isEmpty)
}

@Test func olderLibrariesOpenWithNoMods() throws {
    var game = Game(title: "T", sourcePath: "/x", kind: .folder, basePath: "/x")
    game.mods = [ModUse(mod: UUID(), enabled: false)]
    #expect(!game.hasModsOn)
    let json = #"[{"id":"\#(UUID().uuidString)","title":"T","sourcePath":"/x","kind":"folder","basePath":"/x","added":"2026-11-01T00:00:00Z"}]"#
    let file = Fixture.folder().appending(path: "library.json")
    try json.write(to: file, atomically: true, encoding: .utf8)
    #expect(try JSONFile<[Game]>(file).load()?.first?.mods == [])
}
