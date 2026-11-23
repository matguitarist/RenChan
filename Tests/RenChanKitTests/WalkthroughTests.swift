import Foundation
import Testing
@testable import RenChanKit

@Test func aWalkthroughPDFIsCopiedInAndAFakeOneRefused() throws {
    let root = Fixture.folder()
    let pdf = root.appending(path: "Eternum_Walkthrough_0.8.pdf")
    try Data("%PDF-1.7\n%fake but has the header\n".utf8).write(to: pdf)
    let folder = root.appending(path: "Walkthroughs")
    let walkthrough = try Walkthroughs.add(pdf, into: folder)
    #expect(walkthrough.name == "Eternum Walkthrough 0.8" && walkthrough.kind == .pdf && walkthrough.page == 0)
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: walkthrough.file).path))
    // An itch.io link that expired saves an XML error page under the PDF's name.
    let expired = root.appending(path: "expired.pdf")
    try "<?xml version=\"1.0\"?><Error><Code>ExpiredRequest</Code></Error>".write(to: expired, atomically: true, encoding: .utf8)
    #expect(throws: WalkthroughError.notAPDF) { try Walkthroughs.add(expired, into: folder) }
    let text = root.appending(path: "choices.txt")
    try "Day 1: take the bus".write(to: text, atomically: true, encoding: .utf8)
    #expect(try Walkthroughs.add(text, into: folder).kind == .text)
    let zip = root.appending(path: "mod.zip")
    try "PK".write(to: zip, atomically: true, encoding: .utf8)
    #expect(throws: WalkthroughError.notSupported) { try Walkthroughs.add(zip, into: folder) }
    #expect(Walkthroughs.isWalkthrough(pdf) && !Walkthroughs.isWalkthrough(zip))
}
