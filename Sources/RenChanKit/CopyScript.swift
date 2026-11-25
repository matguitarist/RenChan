import Foundation

/// RenChan's own .rpy files in its copy of a game: the filter loader, the mod API, the save tool, the
/// language and developer-tools files. Never the original game.
public enum CopyScript {
    /// The file in the copy's game folder.
    public static func url(_ name: String, in copy: URL) -> URL { copy.appending(path: "game/\(name)") }

    /// Writes the script, only when its text changed: an unchanged file keeps the .rpyc Ren'Py compiled from it.
    public static func place(_ text: String, named name: String, in copy: URL) throws {
        let file = url(name, in: copy)
        if (try? String(contentsOf: file, encoding: .utf8)) != text { try text.write(to: file, atomically: true, encoding: .utf8) }
    }

    /// Takes the script out, with the .rpyc compiled from it.
    public static func remove(named name: String, from copy: URL) {
        let file = url(name, in: copy)
        for url in [file, file.deletingPathExtension().appendingPathExtension("rpyc")] { try? FileManager.default.removeItem(at: url) }
    }
}
