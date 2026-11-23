import Foundation

/// One run of a game, written to session.json while it plays so the time survives RenChan quitting (S-009).
public struct PlaySession: Codable, Equatable, Sendable {
    public var started: Date

    public init(started: Date) { self.started = started }

    /// Records the start of a run in `file`.
    public static func begin(at started: Date, file: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(PlaySession(started: started)).write(to: file, options: .atomic)
    }

    /// Ends the run: the seconds it lasted, and the file is gone. Any exit code counts, a crash too.
    public static func end(at ended: Date, file: URL) -> TimeInterval {
        defer { try? FileManager.default.removeItem(at: file) }
        guard let session = read(file) else { return 0 }
        return Playtime.seconds(from: session.started, to: ended)
    }

    /// A run RenChan never saw end (it quit while the game played): counts up to the last thing the game wrote.
    /// Nil when there is no leftover session.
    public static func recover(file: URL, lastActivity: URL) -> TimeInterval? {
        guard let session = read(file) else { return nil }
        let modified = (try? lastActivity.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        try? FileManager.default.removeItem(at: file)
        return Playtime.seconds(from: session.started, to: modified ?? session.started)
    }

    static func read(_ file: URL) -> PlaySession? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? Data(contentsOf: file)).flatMap { try? decoder.decode(PlaySession.self, from: $0) }
    }
}

public enum Playtime {
    /// Seconds between two dates, never negative (a clock change can put the end first).
    public static func seconds(from start: Date, to end: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}
