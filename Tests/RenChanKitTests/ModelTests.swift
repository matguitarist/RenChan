import Testing
@testable import RenChanKit

@Test func readsVersionsAndPythonLines() throws {
    let modern = try #require(RenPyVersion("Ren'Py 8.6.1.26111705"))
    #expect(modern.description == "8.6.1")
    #expect(modern.pythonLine == .python3)
    let old = try #require(RenPyVersion("7.4.11.2266"))
    #expect(old.pythonLine == .python2)
    #expect(old < modern)
    #expect(RenPyVersion("6.99") ?? modern < old)
    #expect(RenPyVersion("not a version") == nil)
}
