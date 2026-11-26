import Foundation

/// What a game's folder in RenChan holds that the person made and RenChan can't make again
/// (saves made with mods on, walkthroughs, mod state): Remove from Library keeps it aside before deleting the rest.
public enum RemovedGame {
    /// Moves every folder of `items` that holds a file into one new folder named for the game in `parent`,
    /// and returns that folder, or nil when there was nothing to keep.
    public static func keepAside(_ items: [URL], title: String, in parent: URL) throws -> URL? {
        let kept = items.filter(holdsAFile)
        guard !kept.isEmpty else { return nil }
        let name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var folder = parent.appending(path: name, directoryHint: .isDirectory)
        var n = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = parent.appending(path: "\(name) \(n)", directoryHint: .isDirectory)
            n += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in kept {
            try FileManager.default.moveItem(at: item, to: folder.appending(path: item.lastPathComponent, directoryHint: .isDirectory))
        }
        return folder
    }

    static func holdsAFile(_ folder: URL) -> Bool {
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return false }
        for case let url as URL in walk where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { return true }
        return false
    }
}
