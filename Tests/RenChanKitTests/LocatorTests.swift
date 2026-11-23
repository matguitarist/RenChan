import Foundation
import Testing
@testable import RenChanKit

@Test func findsTheBaseFolderInEveryLayout() throws {
    let root = Fixture.folder()
    let plain = Fixture.game(at: root.appending(path: "Plain"))
    #expect(try GameLocator.locate(plain) == (plain.standardizedFileURL, .folder))

    let nested = root.appending(path: "Zipped")
    let inner = Fixture.game(at: nested.appending(path: "Nested-1.0-pc"))
    let found = try GameLocator.locate(nested)
    #expect(found.base.lastPathComponent == inner.lastPathComponent && found.kind == .folder)

    let app = root.appending(path: "Mac.app")
    Fixture.game(at: app.appending(path: "Contents/Resources/autorun"))
    let fromApp = try GameLocator.locate(app)
    #expect(fromApp.kind == .app && fromApp.base.path.hasSuffix("Contents/Resources/autorun"))
}

@Test func refusesFoldersThatArentGames() {
    let root = Fixture.folder()
    #expect(throws: LocateError.noGameFolder) { try GameLocator.locate(root) }
    try? FileManager.default.createDirectory(at: root.appending(path: "game"), withIntermediateDirectories: true)
    try? "hello".write(to: root.appending(path: "game/readme.txt"), atomically: true, encoding: .utf8)
    #expect(throws: LocateError.noScripts) { try GameLocator.locate(root) }
}

@Test func readsTitleAndSaveFolderFromOptions() {
    let base = Fixture.game(at: Fixture.folder().appending(path: "the_question-7.0-pc"), files: [
        "game/options.rpy": "define config.name = _(\"The Question\")\ndefine config.save_directory = \"the_question-7\"\n",
    ])
    #expect(GameLocator.title(base: base, source: base) == "The Question")
    #expect(GameLocator.saveDirectory(base: base) == "the_question-7")
    let bare = Fixture.game(at: Fixture.folder().appending(path: "My_Game-1.2-pc"))
    #expect(GameLocator.title(base: bare, source: bare) == "My Game 1.2")
}

/// An expired itch.io link saves a 118-byte XML error page under the zip's name.
@Test func aDownloadThatIsntAZipIsRefusedPlainly() throws {
    let file = Fixture.folder().appending(path: "cosy-cafe-mac.zip")
    try #"<?xml version="1.0" encoding="UTF-8"?><Error><Code>ExpiredRequest</Code><Message>Request has expired</Message></Error>"#
        .write(to: file, atomically: true, encoding: .utf8)
    #expect(throws: LocateError.notAZip(size: 118)) { try ZipImport.check(file) }
    #expect(throws: LocateError.notAZip(size: 118)) { try ZipImport.unpack(file, into: file.deletingLastPathComponent().appending(path: "out")) }
}

@Test func zipSlipIsRefused() {
    #expect(ZipImport.unsafeEntry(["Game/game/script.rpy", "Game/./lib/"]) == nil)
    #expect(ZipImport.unsafeEntry(["Game/../../evil.sh"]) == "Game/../../evil.sh")
    #expect(ZipImport.unsafeEntry(["/etc/passwd"]) == "/etc/passwd")
    #expect(ZipImport.unsafeEntry(["a/b/../../../c"]) == "a/b/../../../c")
}

@Test func unpacksAZipAndFindsTheGame() throws {
    let root = Fixture.folder()
    Fixture.game(at: root.appending(path: "src/Zipped-1.0-pc"))
    let zip = root.appending(path: "game.zip")
    let zipper = Process()
    zipper.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zipper.arguments = ["-qr", zip.path, "Zipped-1.0-pc"]
    zipper.currentDirectoryURL = root.appending(path: "src")
    try zipper.run()
    zipper.waitUntilExit()
    let target = root.appending(path: "unpacked")
    try ZipImport.unpack(zip, into: target)
    let found = try GameLocator.locate(target)
    #expect(found.base.lastPathComponent == "Zipped-1.0-pc")
    #expect((ZipImport.size(of: zip) ?? 0) > 0)
}
