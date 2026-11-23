import Foundation

/// Why a dropped item is not a Ren'Py game. The app words it (LocateError.message).
public enum LocateError: Error, Equatable, Sendable {
    case noGameFolder
    case noScripts
    case unsafeZip(String)
    case unzipFailed(String)
    /// The file has a .zip name but isn't one, such as an error page saved by an expired download link.
    case notAZip(size: Int64)

}

/// Finds a Ren'Py game in a folder or a Mac .app, and reads its name, saves folder and cover.
public enum GameLocator {
    /// The folder that holds game/, and what kind of thing was dropped.
    public static func locate(_ url: URL) throws(LocateError) -> (base: URL, kind: SourceKind) {
        let url = url.standardizedFileURL
        if url.pathExtension.lowercased() == "app" {
            let autorun = url.appending(path: "Contents/Resources/autorun", directoryHint: .isDirectory)
            guard isDirectory(autorun.appending(path: "game")) else { throw .noGameFolder }
            try checkScripts(autorun)
            return (autorun, .app)
        }
        guard isDirectory(url) else { throw .noGameFolder }
        if isDirectory(url.appending(path: "game")) {
            try checkScripts(url)
            return (url, .folder)
        }
        // A zip usually unpacks to one folder ("Game-1.0-pc/game"), and a Mac build to Game.app.
        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where !child.lastPathComponent.hasPrefix(".") && child.lastPathComponent != "__MACOSX" {
            if child.pathExtension.lowercased() == "app", let found = try? locate(child) {
                return (found.base, .app)
            }
            if isDirectory(child.appending(path: "game")) {
                try checkScripts(child)
                return (child, .folder)
            }
        }
        throw .noGameFolder
    }

    /// A Ren'Py game has .rpy, .rpyc or .rpa files somewhere in game/.
    static func checkScripts(_ base: URL) throws(LocateError) {
        let game = base.appending(path: "game", directoryHint: .isDirectory)
        guard let walker = FileManager.default.enumerator(at: game, includingPropertiesForKeys: nil) else { throw .noScripts }
        var seen = 0
        for case let file as URL in walker {
            if ["rpy", "rpyc", "rpa", "rpymc"].contains(file.pathExtension.lowercased()) { return }
            seen += 1
            if seen > 20_000 { break }
        }
        throw .noScripts
    }

    /// config.name from options.rpy, else the folder's name without "-pc", "-mac" and the like.
    public static func title(base: URL, source: URL) -> String {
        if let options = optionsText(base), let name = define("config.name", in: options) { return name }
        // "Game-1.2-pc" has no extension to drop; only .app and .zip do.
        let named = ["app", "zip"].contains(source.pathExtension.lowercased()) ? source.deletingPathExtension() : source
        var name = named.lastPathComponent
        if base.lastPathComponent != "autorun", base.standardizedFileURL != source.standardizedFileURL, source.pathExtension.lowercased() != "zip" {
            name = base.lastPathComponent
        }
        for suffix in ["-pc", "-mac", "-win", "-linux", "-market", "-all", "-universal"] where name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        return name.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
    }

    /// config.save_directory from options.rpy, when the game ships its scripts.
    public static func saveDirectory(base: URL) -> String? {
        optionsText(base).flatMap { define("config.save_directory", in: $0) }
    }

    /// The game's main menu background, else its window icon, for the library grid.
    public static func cover(base: URL) -> URL? {
        let gui = base.appending(path: "game/gui", directoryHint: .isDirectory)
        for name in ["main_menu.png", "main_menu.jpg", "main_menu.webp", "window_icon.png"] {
            let file = gui.appending(path: name)
            if FileManager.default.fileExists(atPath: file.path) { return file }
        }
        return nil
    }

    static func optionsText(_ base: URL) -> String? {
        try? String(contentsOf: base.appending(path: "game/options.rpy"), encoding: .utf8)
    }

    /// The string in `define config.name = _("Title")` or `define config.name = "Title"`.
    static func define(_ name: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("define \(name)") || trimmed.hasPrefix("$ \(name)") || trimmed.hasPrefix(name) else { continue }
            guard let equals = trimmed.firstIndex(of: "=") else { continue }
            let value = trimmed[trimmed.index(after: equals)...]
            guard let open = value.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { continue }
            let quote = value[open]
            let rest = value[value.index(after: open)...]
            guard let close = rest.firstIndex(of: quote) else { continue }
            let found = String(rest[..<close]).trimmingCharacters(in: .whitespaces)
            if !found.isEmpty { return found }
        }
        return nil
    }

    static func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) && dir.boolValue
    }
}
