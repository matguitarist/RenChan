import Foundation

/// Tiny Ren'Py games made on the fly in a temp folder, one per layout a real game can have.
enum Fixture {
    static func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "RenChanTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A game base folder with game/script.rpy and the given extra files.
    @discardableResult
    static func game(at base: URL, files: [String: String] = [:]) -> URL {
        var all = ["game/script.rpy": "label start:\n    \"Hello.\"\n    return\n"]
        for (path, text) in files { all[path] = text }
        for (path, text) in all {
            let file = base.appending(path: path)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
        return base
    }
}
