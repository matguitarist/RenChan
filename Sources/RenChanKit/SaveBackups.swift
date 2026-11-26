import FileKit
import Foundation

/// One dated copy of a game's saves, kept by RenChan (S-012).
public struct SaveBackup: Identifiable, Hashable, Sendable {
    public enum Reason: String, Codable, Sendable {
        /// The person asked for it.
        case manual
        /// Made by RenChan just before a restore replaced these saves.
        case beforeRestore
        /// Made by RenChan before a game's first launch with mods (S-020).
        case beforeMods
        /// Made by RenChan before it changed a save's variables (S-036).
        case beforeEdit
        /// Made by RenChan before a launch, when the saves changed since the last backup (S-038). Only the newest few are kept.
        case beforePlay
    }

    /// The folder name, "2026-11-22 190412".
    public var id: String { folder.lastPathComponent }
    public var folder: URL
    public var date: Date
    public var reason: Reason
    public var saveCount: Int
    public var size: Int64
    /// The saves made with mods on (Modded Saves), not the game's own: a restore puts them back there.
    public var modded = false

    var saves: URL { folder.appending(path: "saves", directoryHint: .isDirectory) }
}

/// Backs up, lists, restores and trashes save backups. `root` is one game's backup folder.
public enum SaveBackups {
    private struct Info: Codable {
        var date: Date
        var reason: SaveBackup.Reason
        /// Missing in backups made before 0.9.2, which all hold the game's own saves.
        var modded: Bool?
    }

    /// Copies the saves folder into a new dated backup (an APFS clone where it can).
    @discardableResult
    public static func backUp(saves: URL, into root: URL, reason: SaveBackup.Reason = .manual, modded: Bool = false, at date: Date = .now) throws -> SaveBackup {
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
        try encoder.encode(Info(date: date, reason: reason, modded: modded ? true : nil)).write(to: folder.appending(path: "backup.json"))
        return try read(folder)
    }

    /// Before a launch (S-038): backs up the saves when something in them is newer than the newest backup,
    /// then keeps only the newest `keep` backups made this way. Returns the backup, or nil when none was needed.
    /// Modded and plain saves are compared and kept apart: a backup of one says nothing about the other.
    @discardableResult
    public static func backUpBeforePlay(saves: URL, into root: URL, modded: Bool = false, keep: Int = 5, at date: Date = .now) throws -> SaveBackup? {
        let files = (try? FileManager.default.contentsOfDirectory(at: saves, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let changed = files.filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }.max()
        guard let changed else { return nil }
        let existing = list(root, measured: false).filter { $0.modded == modded }
        if let newest = existing.first, changed <= newest.date { return nil }
        let backup = try backUp(saves: saves, into: root, reason: .beforePlay, modded: modded, at: date)
        for old in list(root, measured: false).filter({ $0.reason == .beforePlay && $0.modded == modded }).dropFirst(max(keep, 1)) {
            try? FileManager.default.removeItem(at: old.folder)
        }
        return backup
    }

    /// Every backup, newest first. Not measured, saveCount and size are 0: a backup is only its date and
    /// reason then, one small file read instead of a walk through every save.
    public static func list(_ root: URL, measured: Bool = true) -> [SaveBackup] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { try? read($0, measured: measured) }.sorted { $0.date > $1.date }
    }

    /// Puts a backup's saves in place of the current ones, after backing those up (the returned backup).
    /// `saves` must be the folder the backup came from: the modded saves for a `modded` backup.
    /// `workingSaves` is game/saves in the working copy: Ren'Py also keeps saves there and takes the newest,
    /// so it gets the same files.
    @discardableResult
    public static func restore(_ backup: SaveBackup, saves: URL, workingSaves: URL? = nil, root: URL, at date: Date = .now) throws -> SaveBackup? {
        var before: SaveBackup?
        if FileManager.default.fileExists(atPath: saves.path) {
            before = try backUp(saves: saves, into: root, reason: .beforeRestore, modded: backup.modded, at: date)
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

    static func read(_ folder: URL, measured: Bool = true) throws -> SaveBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let info = try decoder.decode(Info.self, from: Data(contentsOf: folder.appending(path: "backup.json")))
        let saves = folder.appending(path: "saves", directoryHint: .isDirectory)
        return SaveBackup(folder: folder, date: info.date, reason: info.reason,
                          saveCount: measured ? SaveFolder.count(saves) : 0, size: measured ? ((try? FolderSize.summary(of: saves))?.allocated ?? 0) : 0,
                          modded: info.modded ?? false)
    }
}
