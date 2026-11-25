import Foundation
import ProcessKit
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
@Test func aDownloadThatIsntAZipIsRefusedPlainly() async throws {
    let file = Fixture.folder().appending(path: "cosy-cafe-mac.zip")
    try #"<?xml version="1.0" encoding="UTF-8"?><Error><Code>ExpiredRequest</Code><Message>Request has expired</Message></Error>"#
        .write(to: file, atomically: true, encoding: .utf8)
    #expect(throws: LocateError.notAZip(size: 118)) { try ZipImport.check(file) }
    await #expect(throws: LocateError.notAZip(size: 118)) { try await ZipImport.unpack(file, into: file.deletingLastPathComponent().appending(path: "out")) }
}

/// Zip Slip: a link that points outside the folder refuses the whole zip, and nothing is unpacked.
@Test func aZipThatWritesOutsideItsFolderIsRefused() async throws {
    let root = Fixture.folder()
    let game = Fixture.game(at: root.appending(path: "src/Evil-1.0-pc"))
    try FileManager.default.createSymbolicLink(atPath: game.appending(path: "game/escape").path, withDestinationPath: "/etc")
    let zip = root.appending(path: "evil.zip")
    try Shell.runSync("/usr/bin/zip", ["-qry", zip.path, "Evil-1.0-pc"], in: root.appending(path: "src")).check()
    let target = root.appending(path: "unpacked")
    await #expect(throws: LocateError.unsafeZip("Evil-1.0-pc/game/escape")) { try await ZipImport.unpack(zip, into: target) }
    #expect(!FileManager.default.fileExists(atPath: target.path))
}

@Test func unpacksAZipAndFindsTheGame() async throws {
    let root = Fixture.folder()
    Fixture.game(at: root.appending(path: "src/Zipped-1.0-pc"))
    let zip = root.appending(path: "game.zip")
    try Shell.runSync("/usr/bin/zip", ["-qr", zip.path, "Zipped-1.0-pc"], in: root.appending(path: "src")).check()
    let target = root.appending(path: "unpacked")
    try await ZipImport.unpack(zip, into: target)
    let found = try GameLocator.locate(target)
    #expect(found.base.lastPathComponent == "Zipped-1.0-pc")
    #expect((ZipImport.size(of: zip) ?? 0) > 0)
}
