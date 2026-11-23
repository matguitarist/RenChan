import Foundation
import Testing
@testable import RenChanKit

@Test func findsMacBuildsAndGameFoldersButNothingElse() throws {
    let root = Fixture.folder()
    let apps = root.appending(path: "Applications")
    let games = root.appending(path: "Games")
    Fixture.game(at: apps.appending(path: "Eternum.app/Contents/Resources/autorun"))
    try FileManager.default.createDirectory(at: apps.appending(path: "Safari.app/Contents/MacOS"), withIntermediateDirectories: true)
    Fixture.game(at: games.appending(path: "Moonlit-1.0-pc"), files: ["renpy/__init__.py": ""])
    Fixture.game(at: games.appending(path: "Patreon/Starlit-0.3-pc"), files: ["lib/readme": ""])
    // A game/ folder alone is not enough: plenty of things have one.
    try FileManager.default.createDirectory(at: games.appending(path: "Unity Thing/game"), withIntermediateDirectories: true)
    // Too deep for the default depth.
    Fixture.game(at: games.appending(path: "a/b/c/Deep-1.0-pc"), files: ["renpy/x": ""])
    // RenChan's own folder is skipped.
    let own = root.appending(path: "Games/RenChanData")
    Fixture.game(at: own.appending(path: "Copy-1.0"), files: ["renpy/x": ""])

    let found = GameScanner.scan([apps, games, root.appending(path: "Missing")], excluding: [own])
    #expect(found.map(\.lastPathComponent) == ["Eternum.app", "Moonlit-1.0-pc", "Starlit-0.3-pc"])
    #expect(try GameLocator.locate(found[0]).kind == .app)
}
