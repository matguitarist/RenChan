import Foundation

/// What a file opened from the Finder or dropped on the Dock icon is (S-037): a game to add, or a mod or
/// walkthrough for a game already in the library.
public enum OpenedFile: Equatable, Sendable {
    case game
    case mod
    case walkthrough

    /// Folders and .app bundles that hold a game, and zips with a whole game in them, are games. Ren'Py files,
    /// zips and folders with only scripts are mods. Anything else is handed to Add Game, which says what's missing.
    public static func kind(_ url: URL) -> OpenedFile {
        let ext = url.pathExtension.lowercased()
        if Walkthroughs.isWalkthrough(url) { return .walkthrough }
        if ModLibrary.scriptExtensions.contains(ext) { return .mod }
        if GameLocator.isDirectory(url) {
            if ext == "app" || GameScanner.isGame(url) { return .game }
            if (try? GameLocator.locate(url)).map({ GameScanner.isGame($0.base) }) == true { return .game }
            if FileManager.default.fileExists(atPath: url.appending(path: ModManifest.fileName).path) || ModLibrary.hasScripts(url) { return .mod }
            return .game
        }
        if ext == "zip", let names = try? ZipImport.entries(of: url) {
            if zipHoldsGame(names) { return .game }
            if names.contains(where: { ModLibrary.scriptExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) { return .mod }
        }
        return .game
    }

    /// A zip holds a whole game when game/ sits beside renpy/ or lib/ (at most two folders down), or inside a Mac build.
    public static func zipHoldsGame(_ names: [String]) -> Bool {
        var folders: [String: Set<String>] = [:]
        for name in names {
            if name.contains(".app/Contents/Resources/autorun/game/") { return true }
            let parts = name.split(separator: "/").map(String.init)
            for index in parts.indices.dropLast() where index <= 2 {
                let parent = parts[..<index].joined(separator: "/")
                folders[parent, default: []].insert(parts[index].lowercased())
            }
        }
        return folders.values.contains { $0.contains("game") && ($0.contains("renpy") || $0.contains("lib")) }
    }
}
