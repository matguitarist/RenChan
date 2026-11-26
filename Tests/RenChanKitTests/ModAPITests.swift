import Foundation
import Testing
@testable import RenChanKit

@Test func aManifestNamesTheModAndStaysOutOfTheGame() async throws {
    let root = Fixture.folder()
    let source = root.appending(path: "download/Cheat-Menu-1.2")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try #"{"name": "Cheat Menu", "version": "1.2", "author": "Ana"}"#.write(to: source.appending(path: "renchan-mod.json"), atomically: true, encoding: .utf8)
    try "init python: pass".write(to: source.appending(path: "cheat.rpy"), atomically: true, encoding: .utf8)
    let library = root.appending(path: "Mods")
    let mod = try await ModLibrary.importMod(root.appending(path: "download"), into: library)
    #expect(mod.name == "Cheat Menu" && mod.files == ["cheat.rpy"])
    #expect(ModLibrary.manifest(mod, root: library)?.version == "1.2")
}

@Test func aTemplateModUsesTheAPIAndPicksUpNewFiles() throws {
    let root = Fixture.folder()
    let library = root.appending(path: "Mods")
    #expect(ModTemplate.slug("My Cheat Menu!") == "my_cheat_menu" && ModTemplate.slug("2nd Try") == "mod_2nd_try")
    let mod = try ModTemplate.create("My Cheat Menu", into: library)
    #expect(mod.files == ["my_cheat_menu.rpy"])
    let script = try String(contentsOf: ModLibrary.folder(mod, root: library).appending(path: "my_cheat_menu.rpy"), encoding: .utf8)
    #expect(script.contains("renchan.on_start(my_cheat_menu_started)") && script.contains("renchan.menu_entry(\"My Cheat Menu\""))
    // The author adds a file: it goes in at the next launch.
    try "init python: pass".write(to: ModLibrary.folder(mod, root: library).appending(path: "extra.rpy"), atomically: true, encoding: .utf8)
    let base = Fixture.game(at: root.appending(path: "Base"))
    let copy = root.appending(path: "play-modded")
    try FileManager.default.copyItem(at: base, to: copy)
    let placed = try ModInstaller.apply([mod], root: library, base: base, copy: copy)
    #expect(placed.sorted() == ["extra.rpy", "my_cheat_menu.rpy"])
    try ModAPI.install(copy: copy)
    let api = try String(contentsOf: copy.appending(path: "game/\(ModAPI.fileName)"), encoding: .utf8)
    #expect(api.contains("init -999 python in renchan:") && api.contains(ModAPI.stateFolder(copy).path))
    #expect(!api.contains("f\""))
}

@Test func modStateLivesOutsideTheCopyAndOldStateMovesThere() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "renchan-state-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let copy = root.appending(path: "play-modded")
    try FileManager.default.createDirectory(at: copy.appending(path: "game"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: ModAPI.stateFolder(copy), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: ModAPI.stateFolder(copy).appending(path: "checker.json"))
    let state = root.appending(path: "Mod State")
    try ModAPI.install(copy: copy, state: state)
    #expect(FileManager.default.fileExists(atPath: state.appending(path: "checker.json").path))
    #expect(!FileManager.default.fileExists(atPath: ModAPI.stateFolder(copy).path))
    let api = try String(contentsOf: copy.appending(path: "game/\(ModAPI.fileName)"), encoding: .utf8)
    #expect(api.contains(state.path))
    // A new copy (after an update) finds the same state.
    try FileManager.default.removeItem(at: copy)
    try FileManager.default.createDirectory(at: copy.appending(path: "game"), withIntermediateDirectories: true)
    try ModAPI.install(copy: copy, state: state)
    #expect(FileManager.default.fileExists(atPath: state.appending(path: "checker.json").path))
}
