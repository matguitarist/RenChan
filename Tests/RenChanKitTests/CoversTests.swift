import AppKit
import Foundation
import PictureKit
import Testing
@testable import RenChanKit

private func jpeg(width: Int, height: Int) -> Data {
    let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
        NSGradient(colors: [.systemIndigo, .systemPink, .systemOrange])?.draw(in: rect, angle: 90)
        return true
    }
    return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .jpeg, properties: [.compressionFactor: 1.0])!
}

@Test func aCoverIsStoredAsASmallHEICAndReplacesTheOldOne() throws {
    let base = Fixture.folder().appending(path: "cover")
    try jpeg(width: 1500, height: 2250).write(to: base)
    #expect(Covers.find(base: base) == base)
    let saved = try #require(Covers.upgrade(base: base))
    let file = try #require(Covers.find(base: base))
    #expect(saved > 0 && file.lastPathComponent == "cover.heic" && !FileManager.default.fileExists(atPath: base.path))
    #expect(Pictures.info(at: file)?.longSide == 1200)
    #expect(Covers.upgrade(base: base) == nil)
    Covers.remove(base: base)
    #expect(Covers.find(base: base) == nil)
}

@Test func anErrorPageIsNotACoverAndKeepsTheOldOne() throws {
    let base = Fixture.folder().appending(path: "cover")
    try Covers.store(jpeg(width: 600, height: 900), at: base)
    #expect(throws: PictureError.unreadable) { try Covers.store(Data("<html>Not found</html>".utf8), at: base) }
    #expect(Covers.find(base: base)?.pathExtension == "heic")
}
