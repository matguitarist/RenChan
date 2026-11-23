import Foundation

/// Where the person is with a game (S-011). Playing a game moves it from notStarted to playing.
public enum PlayStatus: String, Codable, CaseIterable, Sendable {
    case notStarted, playing, finished
}

/// The library filter: status, a lowest rating, and labels a game must all have (S-011).
public struct LibraryFilter: Equatable, Sendable {
    public var status: PlayStatus?
    /// 1 to 5: games rated this or more.
    public var minimumRating: Int?
    public var labels: Set<String> = []

    public init(status: PlayStatus? = nil, minimumRating: Int? = nil, labels: Set<String> = []) {
        self.status = status
        self.minimumRating = minimumRating
        self.labels = labels
    }

    public var isActive: Bool { status != nil || minimumRating != nil || !labels.isEmpty }

    public func matches(_ game: Game) -> Bool {
        if let status, game.status != status { return false }
        if let minimumRating, (game.rating ?? 0) < minimumRating { return false }
        let has = Set(game.labels.map { $0.lowercased() })
        return labels.allSatisfy { has.contains($0.lowercased()) }
    }
}

public enum Labels {
    /// Adds a label: trimmed, once whatever its case, in A to Z order.
    public static func add(_ label: String, to labels: [String]) -> [String] {
        let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !labels.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) else { return labels }
        return (labels + [clean]).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Every label in the library, A to Z, once.
    public static func all(in games: [Game]) -> [String] {
        games.flatMap(\.labels).reduce(into: [String]()) { result, label in result = add(label, to: result) }
    }
}

extension Game {
    /// A run started: record it, and a game not started is now being played.
    public mutating func markPlayed(at date: Date) {
        lastPlayed = date
        if status == .notStarted { status = .playing }
    }
}
