import Foundation

/// One dated copy of a game's saves, kept by RenChan (S-012).
public struct SaveBackup: Identifiable, Hashable, Sendable {
    public enum Reason: String, Codable, Sendable {
        /// The person asked for it.
        case manual
        /// Made by RenChan just before a restore replaced these saves.
        case beforeRestore
    }

    /// The folder name, "2026-11-22 190412".
    public var id: String { folder.lastPathComponent }
    public var folder: URL
    public var date: Date
    public var reason: Reason
    public var saveCount: Int
    public var size: Int64

    var saves: URL { folder.appending(path: "saves", directoryHint: .isDirectory) }
}

/// Backs up, lists, restores and trashes save backups. `root` is one game's backup folder.
public enum SaveBackups {
    private struct Info: Codable {
        var date: Date
        var reason: SaveBackup.Reason
    }

    /// Copies the saves folder into a new dated backup (an APFS clone where it can).
    @discardableResult
    public static func backUp(saves: URL, into root: URL, reason: SaveBackup.Reason = .manual, at date: Date = .now) throws -> SaveBackup {
        guard FileManager.default.fileExists(atPath: saves.path) else { throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: saves.path]) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let name = formatter.string(from: date)
        var folder = root.appending(path: name, directoryHint: .isDirectory)
        var n = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = root.appending(path: "\(name) \(n)", directoryHint: .isDirectory)
            n += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: saves, to: folder.appending(path: "saves", directoryHint: .isDirectory))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(Info(date: date, reason: reason)).write(to: folder.appending(path: "backup.json"))
        return try read(folder)
    }

    /// Every backup, newest first.
    public static func list(_ root: URL) -> [SaveBackup] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { try? read($0) }.sorted { $0.date > $1.date }
    }

    /// Puts a backup's saves in place of the current ones, after backing those up (the returned backup).
    /// `workingSaves` is game/saves in the working copy: Ren'Py also keeps saves there and takes the newest,
    /// so it gets the same files.
    @discardableResult
    public static func restore(_ backup: SaveBackup, saves: URL, workingSaves: URL? = nil, root: URL, at date: Date = .now) throws -> SaveBackup? {
        var before: SaveBackup?
        if FileManager.default.fileExists(atPath: saves.path) {
            before = try backUp(saves: saves, into: root, reason: .beforeRestore, at: date)
        }
        for target in [saves] + [workingSaves].compactMap({ $0 }) {
            if target != saves && !FileManager.default.fileExists(atPath: target.path) { continue }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: backup.saves, to: target)
        }
        return before
    }

    /// Moves a backup to the Trash, where it can come back from.
    public static func trash(_ backup: SaveBackup) throws {
        try FileManager.default.trashItem(at: backup.folder, resultingItemURL: nil)
    }

    static func read(_ folder: URL) throws -> SaveBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let info = try decoder.decode(Info.self, from: Data(contentsOf: folder.appending(path: "backup.json")))
        let saves = folder.appending(path: "saves", directoryHint: .isDirectory)
        return SaveBackup(folder: folder, date: info.date, reason: info.reason,
                          saveCount: SaveFolder.count(saves), size: RuntimeStore.size(of: saves))
    }
}
