import Foundation
import Testing
@testable import RenChanKit

let sampleAnswer = """
{"more":true,"results":[
 {"id":"v945","title":"Katawa Shoujo","alttitle":null,"released":"2009-04-29",
  "developers":[{"id":"p454","name":"Four Leaf Studios"}],
  "description":"Hisao finds a [i]letter[/i].\\n\\n[spoiler]He collapses.[/spoiler]\\n\\n[Edited from [url=https://example.org]the site[/url]]",
  "image":{"url":"https://t.vndb.org/cv/88/88188.jpg"}},
 {"id":"v1516","title":"pXt","released":"2009","developers":[],"description":null,"image":null}
]}
"""

@Test func aTitleSearchReturnsCandidates() throws {
    let body = try #require(JSONSerialization.jsonObject(with: VNDB.searchBody("Katawa Shoujo")) as? [String: Any])
    #expect(body["filters"] as? [String] == ["search", "=", "Katawa Shoujo"])
    #expect(body["sort"] as? String == "searchrank")
    let found = try VNDB.parse(Data(sampleAnswer.utf8))
    #expect(found.map(\.id) == ["v945", "v1516"])
    #expect(found[0].developer == "Four Leaf Studios")
    #expect(found[0].description == "Hisao finds a letter.\n\n[Edited from the site]")
    #expect(found[0].releaseDate != nil)
    #expect(found[1].developer == nil && found[1].releaseDate == nil && found[1].released == "2009")
    #expect(found[0].pageURL.absoluteString == "https://vndb.org/v945")
}

@Test func aReleaseDateShowsAsTheSameDay() throws {
    let date = try #require(VNDBInfo(id: "v1", title: "A", released: "2025-08-14").releaseDate)
    let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
    #expect(day.year == 2025 && day.month == 8 && day.day == 14)
}

@Test func aManualCoverIsKeptOnRefresh() throws {
    let info = try #require(try VNDB.parse(Data(sampleAnswer.utf8)).first)
    var game = Game(title: "KS", sourcePath: "/g", kind: .folder, basePath: "/g")
    #expect(VNDB.apply(info, to: &game))
    #expect(game.vndb?.id == "v945")
    game.customCover = true
    #expect(!VNDB.apply(info, to: &game))
    #expect(game.customCover)
}
