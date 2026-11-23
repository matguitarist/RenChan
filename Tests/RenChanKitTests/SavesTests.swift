import Foundation
import Testing
@testable import RenChanKit

private func makeSave(_ url: URL, json: String, name: String) throws {
    let work = Fixture.folder()
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: work.appending(path: "screenshot.png"))
    try name.write(to: work.appending(path: "extra_info"), atomically: true, encoding: .utf8)
    try json.write(to: work.appending(path: "json"), atomically: true, encoding: .utf8)
    try String(repeating: "pickled log ", count: 400).write(to: work.appending(path: "log"), atomically: true, encoding: .utf8)
    let zip = Process()
    zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zip.currentDirectoryURL = work
    zip.arguments = ["-q", url.path, "screenshot.png", "extra_info", "json", "log"]
    try zip.run()
    zip.waitUntilExit()
}

@Test func savesAreListedWithTheirDetails() throws {
    let folder = Fixture.folder()
    try makeSave(folder.appending(path: "1-3-LT1.save"), json: #"{"_save_name": "Bridge", "_renpy_version": [8, 6, 1, 0], "_game_runtime": 125.5, "_ctime": 1790000000}"#, name: "Bridge")
    try makeSave(folder.appending(path: "quick-2-LT1.save"), json: #"{"_ctime": 1790100000}"#, name: "")
    try Data(repeating: 1, count: 100).write(to: folder.appending(path: "auto-1-LT1.save"))   // not a zip: left out
    try "x".write(to: folder.appending(path: "persistent"), atomically: true, encoding: .utf8)
    let saves = SaveList.list(in: folder)
    #expect(saves.map(\.slot) == ["quick-2", "1-3"])
    #expect(saves[1].name == "Bridge" && saves[1].renpyVersion == "8.6.1.0" && saves[1].playtime == 125.5)
    #expect(saves[1].place == "Page 1, slot 3" && saves[0].place == "Quick 2")
    #expect(saves[1].screenshot() == Data([0x89, 0x50, 0x4E, 0x47]))
    let zip = try ZipReader(saves[1].url)
    #expect(zip.read("log").map { String(decoding: $0, as: UTF8.self) } == String(repeating: "pickled log ", count: 400))
    #expect(throws: (any Error).self) { try ZipReader(data: Data(repeating: 0, count: 50)) }
}

@Test func editedValuesMustFitTheirKind() {
    let n = SaveVariable(name: "points", kind: .int, value: "3")
    #expect(n.encode(" 42 ") as? Int == 42 && n.encode("4.5") == nil)
    let f = SaveVariable(name: "speed", kind: .float, value: "1.0")
    #expect(f.encode("2,5") as? Double == 2.5)
    let b = SaveVariable(name: "met", kind: .bool, value: "false")
    #expect(b.encode("TRUE") as? Bool == true && b.encode("yes") == nil)
    let s = SaveVariable(name: "hero", kind: .string, value: "Ana")
    #expect(s.encode(" Bo") as? String == " Bo")
    #expect(SaveVariable(name: "bag", kind: .other, value: "list (1)").editable == false)
}

@Test func theSaveToolGoesInTheCopyOnly() throws {
    let copy = Fixture.game(at: Fixture.folder().appending(path: "play"))
    try SaveTool.install(copy: copy)
    let text = try String(contentsOf: copy.appending(path: "game/\(SaveTool.fileName)"), encoding: .utf8)
    #expect(text.contains("register_command(\"renchan_saves\"") && text.contains("sign_data"))
    #expect(SaveTool.setArguments(slot: "1-1", changes: URL(fileURLWithPath: "/c.json"), output: URL(fileURLWithPath: "/o.json"))
            == ["renchan_saves", "set", "1-1", "/c.json", "/o.json"])
}
