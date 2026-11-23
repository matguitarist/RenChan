import Foundation

/// One time a game was played from RenChan (S-027).
public struct RunRecord: Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        /// Quit normally.
        case worked
        /// Ren'Py showed an error or exited with one.
        case failed
    }
    public var date: Date
    public var runtime: String
    public var outcome: Outcome
    public var exitCode: Int32
    public var seconds: TimeInterval
    public var modded: Bool
    public var filter: String?
    /// Ren'Py's error, first line, when it failed.
    public var error: String?

    public init(date: Date, runtime: String, outcome: Outcome, exitCode: Int32, seconds: TimeInterval,
                modded: Bool = false, filter: String? = nil, error: String? = nil) {
        self.date = date
        self.runtime = runtime
        self.outcome = outcome
        self.exitCode = exitCode
        self.seconds = seconds
        self.modded = modded
        self.filter = filter
        self.error = error
    }
}

extension Game {
    /// Keeps the newest 20 runs.
    public mutating func record(_ run: RunRecord) {
        runs.insert(run, at: 0)
        if runs.count > 20 { runs.removeLast(runs.count - 20) }
    }
}

/// The report people attach to a bug report: each game, its Ren'Py, and how it last ran (S-027).
public enum CompatibilityReport {
    public static func markdown(_ games: [Game], app: String, system: String, chip: String, date: Date = .now) -> String {
        let day = ISO8601DateFormatter.string(from: date, timeZone: .current, formatOptions: [.withFullDate])
        var lines = [
            "# RenChan compatibility report",
            "",
            "\(app) · \(system) · \(chip) · \(day)",
            "",
            "| Game | Ren'Py | Python | Last run | Runtime | Result | Runs (worked/total) |",
            "| --- | --- | --- | --- | --- | --- | --- |",
        ]
        for game in games.sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) {
            let last = game.runs.first
            let worked = game.runs.filter { $0.outcome == .worked }.count
            let result: String
            switch last?.outcome {
            case .worked?: result = "worked" + (last?.modded == true ? " (mods)" : "")
            case .failed?: result = "failed (exit \(last?.exitCode ?? 0))" + (last?.error.map { ": " + $0.replacingOccurrences(of: "|", with: "/") } ?? "")
            case nil: result = "not played"
            }
            let lastDay = last.map { ISO8601DateFormatter.string(from: $0.date, timeZone: .current, formatOptions: [.withFullDate]) } ?? "—"
            lines.append("| \(game.title.replacingOccurrences(of: "|", with: "/")) | \(game.version?.description ?? "unknown") | \(game.pythonLine.map { $0 == .python2 ? "2" : "3" } ?? "?") | \(lastDay) | \(last?.runtime ?? "—") | \(result) | \(worked)/\(game.runs.count) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func json(_ games: [Game]) throws -> Data {
        struct Entry: Encodable { var title: String; var version: String?; var runs: [RunRecord] }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(games.map { Entry(title: $0.title, version: $0.version?.description, runs: $0.runs) })
    }
}
