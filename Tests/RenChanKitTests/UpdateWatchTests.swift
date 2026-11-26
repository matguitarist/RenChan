import Foundation
import ProcessKit
import Testing
@testable import RenChanKit

@Test func versionsCompareLikePeopleWriteThem() {
    #expect(VersionOrder.compare("0.10", "0.9") == .orderedDescending)
    #expect(VersionOrder.compare("v1.2", "1.2") == .orderedSame)
    #expect(VersionOrder.compare("0.9a", "0.9") == .orderedDescending)
    #expect(VersionOrder.compare("Ch. 3", "Ch. 4") == .orderedAscending)
    #expect(VersionOrder.find(in: "Eternum [v0.9] [Caribdis]") == "0.9")
    #expect(VersionOrder.find(in: "Starlit Harbor-1.2.3-pc") == "1.2.3")
    #expect(VersionOrder.find(in: "Harbor Lights") == nil)
}

@Test func aPageShowsItsNewestVersion() {
    let itch = """
    <div class="upload_name"><strong class="name" title="💻 ETERNUM - [0.9] - PC (MEDIAFIRE)">💻 ETERNUM - [0.9] - PC (MEDIAFIRE)</strong></div>
    <div class="upload_name"><strong class="name" title="ETERNUM - [0.8] - UPDATE PATCH">ETERNUM - [0.8] - UPDATE PATCH</strong></div>
    <div class="upload_name"><strong title="🍏 ETERNUM - [0.10] - MAC" class="name">🍏 ETERNUM - [0.10] - MAC</strong></div>
    """
    #expect(PageVersion.parse(itch) == "0.10")
    #expect(PageVersion.parse("<title>Eternum [v0.9] [Caribdis] | F95zone</title>") == "0.9")
    #expect(PageVersion.parse("<title>Long Game [Ch. 4 Part 2] [Studio] | F95zone</title>") == "Ch. 4 Part 2")
    #expect(PageVersion.parse("<title>Login | F95zone</title>") == nil)
    #expect(PageVersion.parse("<title>VN - Others - Completed - The logic of the miniature garden [Final] [Cabbit] | F95zone | Adult Games</title>") == "Final")
    #expect(PageVersion.parse("<title>VN - Ren&#039;Py - Long Road [v0.12.1] [Studio 9] | F95zone</title>") == "0.12.1")
}

@Test func onlyItchAndF95zonePagesAreWatched() {
    #expect(UpdateWatch.validate("caribdis.itch.io/eternum?ref=x")?.absoluteString == "https://caribdis.itch.io/eternum")
    #expect(UpdateWatch.validate("https://f95zone.to/threads/eternum-v0-9-caribdis.12345/post-999")?.absoluteString == "https://f95zone.to/threads/eternum-v0-9-caribdis.12345/")
    #expect(UpdateWatch.threadID(URL(string: "https://f95zone.to/threads/eternum-v0-9-caribdis.12345/")!) == 12345)
    #expect(UpdateWatch.validate("https://example.com/game") == nil)
    #expect(UpdateWatch.validate("https://caribdis.itch.io") == nil)
}

@Test func newsIsANewerVersionNotYetDismissed() {
    var watch = UpdateWatch(page: "https://caribdis.itch.io/eternum")
    watch.record(version: "0.9", error: nil)
    #expect(watch.news(installed: "0.8") == "0.9")
    #expect(watch.news(installed: "0.9") == nil)
    #expect(watch.news(installed: nil) == nil)   // first seen: nothing to compare yet
    watch.record(version: "0.10", error: nil)
    #expect(watch.news(installed: nil) == "0.10")
    watch.dismissed = "0.10"
    #expect(watch.news(installed: "0.8") == nil)
    #expect(!watch.isDue() && watch.isDue(now: .now.addingTimeInterval(21 * 3600)))
}

@Test func theGamesOwnVersionComesFromConfigOrItsName() {
    let root = Fixture.folder()
    let a = Fixture.game(at: root.appending(path: "Eternum-0.8-pc"), files: ["game/options.rpy": "define config.name = _(\"Eternum\")\ndefine config.version = \"0.8.1\"\n"])
    #expect(GameVersion.detect(base: a, source: a) == "0.8.1")
    let b = Fixture.game(at: root.appending(path: "Starlit_Harbor-1.2-pc"))
    #expect(GameVersion.detect(base: b, source: b) == "1.2")
    let c = Fixture.game(at: root.appending(path: "Harbor Lights"))
    #expect(GameVersion.detect(base: c, source: c) == nil)
}

@Test func anF95CheckerLibraryIsReadWithoutChangingIt() throws {
    let root = Fixture.folder()
    let db = root.appending(path: "db.sqlite3")
    let sql = """
    CREATE TABLE settings (default_exe_dir TEXT);
    INSERT INTO settings VALUES ('\(root.path)/Games');
    CREATE TABLE games (id INTEGER PRIMARY KEY, name TEXT, version TEXT, executables TEXT, rating INTEGER);
    INSERT INTO games VALUES (12345, 'Eternum', 'v0.9', '["Eternum-0.9-pc/Eternum.exe"]', 5);
    INSERT INTO games VALUES (777, 'Starlit Harbor', '1.2', '["/Applications/Starlit Harbor.app/Contents/MacOS/Starlit Harbor"]', 0);
    INSERT INTO games VALUES (9, 'Not Here', '', '[]', 0);
    """
    try Shell.runSync("/usr/bin/sqlite3", [db.path, sql]).check()
    let before = try Data(contentsOf: db)
    let entries = try F95Checker.read(db).sorted { $0.threadID < $1.threadID }
    #expect(entries.map(\.name) == ["Not Here", "Starlit Harbor", "Eternum"])
    #expect(entries[2].version == "0.9" && entries[2].executables == ["\(root.path)/Games/Eternum-0.9-pc/Eternum.exe"])
    #expect(entries[0].version == nil && entries[2].thread.absoluteString == "https://f95zone.to/threads/12345/")
    #expect(F95Checker.gameLocation(entries[1].executables[0]).path == "/Applications/Starlit Harbor.app")
    #expect(F95Checker.gameLocation(entries[2].executables[0]).lastPathComponent == "Eternum-0.9-pc")
    #expect(try Data(contentsOf: db) == before)
    #expect(throws: F95Checker.Failure.self) { try F95Checker.read(root.appending(path: "missing.sqlite3")) }
}

@Test func theSameVersionWrittenTwoWaysIsNotNews() {
    #expect(VersionOrder.compare("1.0", "1.0.0") == .orderedSame)
    #expect(VersionOrder.compare("v0.9 Final", "0.9") == .orderedSame)
    #expect(VersionOrder.compare("0.9 Public", "0.9") == .orderedSame)
    #expect(VersionOrder.compare("1.0.1", "1.0") == .orderedDescending)
    #expect(VersionOrder.compare("0.9a", "0.9") == .orderedDescending)
    var watch = UpdateWatch(page: "https://dev.itch.io/game")
    watch.record(version: "1.0.0", error: nil)
    #expect(watch.news(installed: "1.0") == nil)
}

@Test func versionsInDownloadFileNamesAreRead() {
    #expect(VersionOrder.find(in: "Game_v0.9_pc.zip") == "0.9")
    #expect(VersionOrder.find(in: "Game-0.9.zip") == "0.9")
    #expect(VersionOrder.find(in: "Game-1.2.3-mac.tar.bz2") == "1.2.3")
    let html = #"<div class="upload_name"><strong class="name" title="x">Game_v0.10_pc.zip</strong></div><div class="upload_name"><strong class="name">Game-0.9.zip</strong></div>"#
    #expect(PageVersion.parse(html) == "0.10")
}
