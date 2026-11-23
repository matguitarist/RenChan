import Foundation
import Testing
@testable import RenChanKit

@Test func searchesOnlyRenPyGamesAndListsPopularOnesWhenEmpty() throws {
    let body = try #require(JSONSerialization.jsonObject(with: VNDB.searchBody("Eternum", renpyOnly: true)) as? [String: Any])
    let filters = try #require(body["filters"] as? [Any])
    #expect(filters.first as? String == "and")
    #expect((filters.last as? [Any])?.first as? String == "release")
    let empty = try #require(JSONSerialization.jsonObject(with: VNDB.searchBody("  ", renpyOnly: true)) as? [String: Any])
    #expect(empty["sort"] as? String == "popularity" && empty["reverse"] as? Bool == true)
    let plain = try #require(JSONSerialization.jsonObject(with: VNDB.searchBody("Eternum")) as? [String: Any])
    #expect(plain["filters"] as? [String] == ["search", "=", "Eternum"])
}

@Test func officialReleasesComeFirstWithTheirLinks() throws {
    let json = """
    {"results":[
     {"id":"r1","title":"Eternum [0.9.5] Spanish","released":"2026-07-24","official":false,"freeware":true,"platforms":["win"],
      "extlinks":[{"label":"Itch.io","url":"https://example.itch.io/es"}]},
     {"id":"r2","title":"Eternum [v0.9.5]","released":"2026-01-21","official":true,"freeware":true,"platforms":["win","mac"],"engine":"Ren'Py",
      "extlinks":[{"label":"Itch.io","url":"https://caribdis.itch.io/eternum"},{"label":"Patreon","url":"https://www.patreon.com/x"}]}
    ]}
    """
    let releases = try VNDB.parseReleases(Data(json.utf8))
    #expect(releases.map(\.id) == ["r2", "r1"])
    #expect(releases[0].links.map(\.label) == ["Itch.io", "Patreon"])
    #expect(releases[0].platforms.contains("mac") && releases[1].official == false)
}

@Test func aGameAddedAfterDiscoverIsMatchedByTitle() {
    let eternum = VNDBInfo(id: "v31929", title: "Eternum")
    #expect(VNDB.plausible("Eternum 0.9.5", matches: eternum))
    #expect(VNDB.plausible("Eternum-v0.10-pc", matches: eternum))
    #expect(!VNDB.plausible("Harbor Lights", matches: eternum))
    #expect(VNDB.plausible("Doki Doki Literature Club", matches: VNDBInfo(id: "v21905", title: "Doki Doki Literature Club!")))
    #expect(!VNDB.plausible("1.0", matches: eternum))
}
