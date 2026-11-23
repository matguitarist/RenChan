import Foundation
import Testing
@testable import RenChanKit

@Test func anUpdateKeepsWhatThePersonAdded() throws {
    var game = Game(title: "Eternum 0.9.5", sourcePath: "/Games/Eternum-0.9.5-pc", kind: .folder, basePath: "/Games/Eternum-0.9.5-pc",
                    version: RenPyVersion("8.3.2"), pythonLine: .python3, versionSource: .vcVersion,
                    saveDirectory: "Eternum-1234", lastPlayed: .now, runtimeOverride: "8.3.2")
    game.playtime = 7200
    game.status = .playing
    game.rating = 5
    game.labels = ["Romance"]
    game.notes = "Chapter 5"
    game.vndb = VNDBInfo(id: "v26236", title: "Eternum")
    game.customCover = true
    let id = game.id

    GameUpdate.apply(to: &game, title: "Eternum 0.10", sourcePath: "/Downloads/Eternum-0.10-pc.zip", kind: .zip,
                     basePath: "/RenChan/Games/x/source/Eternum-0.10-pc",
                     detected: VersionDetector.Result(version: RenPyVersion("8.3.7"), pythonLine: .python3, source: .vcVersion),
                     saveDirectory: nil)

    #expect(game.id == id && game.title == "Eternum 0.10" && game.kind == .zip)
    #expect(game.version?.description == "8.3.7" && game.runtimeOverride == nil)
    #expect(game.saveDirectory == "Eternum-1234")
    #expect(game.playtime == 7200 && game.status == .playing && game.rating == 5 && game.labels == ["Romance"])
    #expect(game.notes == "Chapter 5" && game.vndb?.id == "v26236" && game.customCover && game.lastPlayed != nil)
}
