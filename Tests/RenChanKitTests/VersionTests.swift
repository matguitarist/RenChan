import DownloadKit
import Foundation
import Testing
@testable import RenChanKit

/// One fixture per version line (docs/STORIES.md S-002), each read from the file real games of that era ship.
@Test(arguments: [
    (["renpy/vc_version.py": "branch = 'fix'\nversion = '8.6.1.26111705'\n"], "8.6.1", PythonLine.python3, VersionSource.vcVersion),
    (["renpy/vc_version.py": "vc_version = 2266\n", "renpy/__init__.py": "version_tuple = (7, 4, 11, vc_version)\n"], "7.4.11", .python2, .initFile),
    (["game/script_version.txt": "(7, 8, 7)"], "7.8.7", .python2, .scriptVersion),
    (["game/script_version.txt": "8.0.3"], "8.0.3", .python3, .scriptVersion),
    (["log.txt": "2024-01-01\nmacOS-14\nRen'Py 8.3.7.25031702\n"], "8.3.7", .python3, .logFile),
    (["renpy/__init__.py": "version_tuple = (6, 99, 14, vc_version)\n"], "6.99.14", .python2, .initFile),
])
func detectsEachVersionLine(files: [String: String], version: String, python: PythonLine, source: VersionSource) {
    let base = Fixture.game(at: Fixture.folder(), files: files)
    let found = VersionDetector.detect(base: base)
    #expect(found.version?.description == version)
    #expect(found.pythonLine == python)
    #expect(found.source == source)
}

@Test func libFoldersGiveThePythonLine() {
    let py3 = Fixture.game(at: Fixture.folder(), files: ["lib/py3-windows-x86_64/readme": ""])
    #expect(VersionDetector.detect(base: py3) == .init(version: nil, pythonLine: .python3, source: .libFolders))
    let old = Fixture.game(at: Fixture.folder(), files: ["lib/windows-i686/readme": ""])
    #expect(VersionDetector.detect(base: old).pythonLine == .python2)
    #expect(VersionDetector.detect(base: Fixture.game(at: Fixture.folder())).source == nil)
}

@Test func choosesTheRuntimeForEachGame() {
    #expect(RuntimeCatalog.choose(version: RenPyVersion("8.0.3"), pythonLine: .python3) == RuntimeCatalog.python3)
    #expect(RuntimeCatalog.choose(version: RenPyVersion("7.4.11"), pythonLine: .python2) == "7.8.7")
    #expect(RuntimeCatalog.choose(version: RenPyVersion("6.99.14.3.3347"), pythonLine: .python2) == "6.99.14.3")
    #expect(RuntimeCatalog.choose(version: nil, pythonLine: .python2) == "7.8.7")
    #expect(RuntimeCatalog.choose(version: nil, pythonLine: nil) == nil)
    #expect(RuntimeCatalog.choose(version: RenPyVersion("8.0.3"), pythonLine: .python3, override: "8.0.3") == "8.0.3")
    #expect(RuntimeCatalog.exactAlternative(version: RenPyVersion("7.4.11.2266"), chosen: "7.8.7") == "7.4.11")
    #expect(RuntimeCatalog.exactAlternative(version: RenPyVersion("7.8.7"), chosen: "7.8.7") == nil)
}

@Test func readsTheSHA256FromChecksums() throws {
    let sums = """
    e41451f891686aa3917f7ec237e68288 renpy-8.6.1-sdk.tar.bz2
    f546f949b275b7b153345bee8fb8add059f42e5c renpy-8.6.1-sdk.tar.bz2
    4d76d88f690ff7d600218dad3941dfddb88e2104e107367a0600a17364335509 renpy-8.6.1-sdk.tar.bz2
    """
    #expect(SHA256Hex.find(for: "renpy-8.6.1-sdk.tar.bz2", in: sums) == "4d76d88f690ff7d600218dad3941dfddb88e2104e107367a0600a17364335509")
    #expect(SHA256Hex.find(for: "renpy-8.6.1-sdk.zip", in: sums) == nil)
}

/// The Runtimes page words a missing version and a bad download from these.
@Test func downloadFailuresKeepRenChansOwnWords() {
    let url = RuntimeCatalog.archiveURL("9.9.9")
    #expect(RuntimeDownload.failure(.http(status: 404, url: url)) as? RuntimeDownload.Failure == .http(404))
    #expect(RuntimeDownload.failure(.checksumMismatch(expected: "aa", actual: "bb")) as? RuntimeDownload.Failure
            == .checksumMismatch(expected: "aa", actual: "bb"))
}
