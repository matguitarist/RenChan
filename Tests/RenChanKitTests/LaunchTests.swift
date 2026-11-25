import Foundation
import ProcessKit
import Testing
@testable import RenChanKit

/// A pretend SDK whose "python" is a shell script: it writes a compiled file into the game it was given,
/// and fails with a traceback when the game's script says so.
func fakeRuntime(in root: URL, version: String = "8.6.1", folder: String = "py3-mac-universal") -> Runtime {
    let sdk = root.appending(path: "runtimes/\(version)")
    let python = sdk.appending(path: "lib/\(folder)/python")
    try? FileManager.default.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
    let script = """
    #!/bin/sh
    # args: -EO renpy.py <base>
    base="$3"
    touch "$base/game/script.rpyc"
    if grep -q crash "$base/game/script.rpy"; then
      printf 'Traceback:\\n  File "game/script.rpy", line 2\\nException: crash\\n' > "$base/traceback.txt"
      exit 1
    fi
    if grep -q hang "$base/game/script.rpy"; then
      sleep 30
    fi
    echo "Ren'Py ran $base"
    """
    try? script.write(to: python, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
    try? "".write(to: sdk.appending(path: "renpy.py"), atomically: true, encoding: .utf8)
    return Runtime(version: version, folder: sdk)
}

func digest(_ folder: URL) -> [String: Date] {
    var all: [String: Date] = [:]
    let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
    while let file = walker?.nextObject() as? URL {
        all[file.path] = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
    return all
}

@Test func playsFromACloneAndLeavesTheOriginalAlone() throws {
    let root = Fixture.folder()
    let original = Fixture.game(at: root.appending(path: "Original"))
    let before = digest(original)
    let copy = root.appending(path: "Games/one/play")
    #expect(try WorkingCopy.prepare(base: original, copy: copy, allowFullCopy: false) == .cloned)
    #expect(try WorkingCopy.prepare(base: original, copy: copy, allowFullCopy: false) == .reused)

    let runtime = fakeRuntime(in: root)
    #expect(runtime.isUniversal)
    let plan = LaunchPlan(runtime: runtime, copy: copy, outputFile: root.appending(path: "run.log"))
    let started = Date()
    let output = try plan.start().waitSync()
    let result = LaunchResult.read(copy: copy, outputFile: plan.outputFile, exitCode: LaunchPlan.exitCode(of: output), started: started)
    #expect(!result.failed)
    #expect(result.outputTail.contains("Ren'Py ran"))
    #expect(FileManager.default.fileExists(atPath: copy.appending(path: "game/script.rpyc").path))
    #expect(!FileManager.default.fileExists(atPath: original.appending(path: "game/script.rpyc").path))
    #expect(digest(original) == before)
}

@Test func aCrashBringsBackTheTraceback() throws {
    let root = Fixture.folder()
    let original = Fixture.game(at: root.appending(path: "Broken"), files: ["game/script.rpy": "label start:\n    $ crash()\n"])
    let copy = root.appending(path: "play")
    try WorkingCopy.prepare(base: original, copy: copy, allowFullCopy: false)
    let plan = LaunchPlan(runtime: fakeRuntime(in: root), copy: copy, outputFile: root.appending(path: "run.log"))
    let started = Date()
    let output = try plan.start().waitSync()
    let result = LaunchResult.read(copy: copy, outputFile: plan.outputFile, exitCode: LaunchPlan.exitCode(of: output), started: started)
    #expect(result.failed)
    #expect(result.exitCode == 1)
    #expect(result.traceback?.contains("game/script.rpy\", line 2") == true)
}

@Test func aStoppedGameRecordsTheSignalAsBefore() throws {
    // Process gave 15 for a game ended by SIGTERM; the compatibility report keeps that code.
    let root = Fixture.folder()
    let original = Fixture.game(at: root.appending(path: "Slow"), files: ["game/script.rpy": "label start:\n    $ hang()\n"])
    let copy = root.appending(path: "play")
    try WorkingCopy.prepare(base: original, copy: copy, allowFullCopy: false)
    let plan = LaunchPlan(runtime: fakeRuntime(in: root), copy: copy, outputFile: root.appending(path: "run.log"))
    let game = try plan.start()
    Thread.sleep(forTimeInterval: 0.3)
    #expect(game.isRunning)
    game.stop()
    let output = game.waitSync()
    #expect(LaunchPlan.exitCode(of: output) == SIGTERM)
}

@Test func runtimesAreListedWithTheirPython() {
    let root = Fixture.folder()
    _ = fakeRuntime(in: root, version: "8.6.1")
    let intel = fakeRuntime(in: root, version: "7.4.11", folder: "mac-x86_64")
    let store = RuntimeStore(folder: root.appending(path: "runtimes"))
    #expect(store.installed().map(\.version) == ["8.6.1", "7.4.11"])
    #expect(!intel.isUniversal)
}

@Test func saveFoldersChangedByARunAreFound() throws {
    let home = Fixture.folder()
    let root = SaveFolder.root(home: home)
    let old = root.appending(path: "Older-1")
    try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: old.path)
    let started = Date()
    let mine = root.appending(path: "MyGame-123")
    try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
    try Data().write(to: mine.appending(path: "1-1-LT1.save"))
    #expect(SaveFolder.changed(since: started.addingTimeInterval(-1), root: root) == ["MyGame-123"])
    #expect(SaveFolder.count(mine) == 1)
}
