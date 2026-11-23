import Foundation

/// Finds Ren'Py games already on this Mac (S-030): Mac builds (Game.app with Contents/Resources/autorun/game)
/// and game folders (game/ beside renpy/ or lib/), a few levels down from each root. Reads only.
public enum GameScanner {
    /// The usual places: /Applications, ~/Applications, ~/Games, Downloads and the Desktop.
    public static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true)]
            + ["Applications", "Games", "Downloads", "Desktop"].map { home.appending(path: $0, directoryHint: .isDirectory) }
    }

    /// What `GameLocator.locate` should be given for each game found, A to Z, skipping `excluded` folders.
    public static func scan(_ roots: [URL], depth: Int = 2, excluding excluded: [URL] = []) -> [URL] {
        let skip = Set(excluded.map { $0.resolvingSymlinksInPath().path })
        var found: [URL] = []
        var seen = Set<String>()
        func visit(_ folder: URL, _ level: Int) {
            let resolved = folder.resolvingSymlinksInPath().path
            guard !skip.contains(where: { resolved == $0 || resolved.hasPrefix($0 + "/") }), seen.insert(resolved).inserted else { return }
            if isGame(folder) {
                found.append(folder)
                return
            }
            // Inside an .app that isn't a Ren'Py game there is nothing to find.
            guard level < depth, folder.pathExtension.lowercased() != "app" else { return }
            let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                                                          options: [.skipsHiddenFiles])) ?? []
            for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                visit(child, level + 1)
            }
        }
        for root in roots { visit(root, 0) }
        return found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// A Ren'Py Mac build, or a folder with game/ and Ren'Py's own renpy/ or lib/ beside it.
    static func isGame(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "app" {
            return GameLocator.isDirectory(url.appending(path: "Contents/Resources/autorun/game"))
        }
        guard GameLocator.isDirectory(url.appending(path: "game")) else { return false }
        return GameLocator.isDirectory(url.appending(path: "renpy")) || GameLocator.isDirectory(url.appending(path: "lib"))
    }
}
