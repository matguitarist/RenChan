import Foundation

/// Versions as people write them ("0.9", "v1.2.3a", "Ch. 4"), compared part by part (S-033).
public enum VersionOrder {
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            guard i < x.count else { return .orderedAscending }
            guard i < y.count else { return .orderedDescending }
            switch (Int(x[i]), Int(y[i])) {
            case let (p?, q?) where p != q: return p < q ? .orderedAscending : .orderedDescending
            case (_?, nil): return .orderedDescending
            case (nil, _?): return .orderedAscending
            case (nil, nil) where x[i] != y[i]: return x[i] < y[i] ? .orderedAscending : .orderedDescending
            default: continue
            }
        }
        return .orderedSame
    }

    static func parts(_ s: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"\d+|[a-z]+"#)
        var lower = s.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.hasPrefix("v"), lower.dropFirst().first?.isNumber == true { lower.removeFirst() }
        return regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)).map { String(lower[Range($0.range, in: lower)!]) }
    }

    /// The version in a text: "[v0.9]" first, then a dotted number such as "1.2.3".
    public static func find(in text: String, anyBracket: Bool = false) -> String? {
        let patterns = [#"\[\s*[vV]?\s*(\d[^\]]*?)\s*\]"#, #"(?:^|[^\w.])[vV]?(\d+(?:\.\d+)+[a-z]?)(?![\w.])"#] + (anyBracket ? [#"\[\s*([^\]]+?)\s*\]"#] : [])
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern)
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        }
        return nil
    }
}

/// The game's own version (not its Ren'Py's): config.version, else the version in its folder or file name.
public enum GameVersion {
    private static let configVersion = try! NSRegularExpression(pattern: #"^\s*(?:define\s+)?config\.version\s*=\s*u?["']([^"']+)["']"#, options: .anchorsMatchLines)

    public static func detect(base: URL, source: URL) -> String? {
        let game = base.appending(path: "game")
        let files = (try? FileManager.default.contentsOfDirectory(at: game, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let regex = configVersion
        for file in files.filter({ $0.pathExtension == "rpy" }).sorted(by: { $0.lastPathComponent == "options.rpy" && $1.lastPathComponent != "options.rpy" }).prefix(60) {
            guard ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) < 2_000_000,
                  let text = try? String(contentsOf: file, encoding: .utf8),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let version = String(text[range]).trimmingCharacters(in: .whitespaces)
            if !version.isEmpty { return version.hasPrefix("v") ? String(version.dropFirst()) : version }
        }
        for name in [source.deletingPathExtension().lastPathComponent, base.lastPathComponent] {
            if let found = VersionOrder.find(in: name.replacingOccurrences(of: "_", with: " ")) { return found }
        }
        return nil
    }
}

/// A page RenChan watches for a game's new versions: its itch.io page or F95zone thread (S-033).
public struct UpdateWatch: Codable, Hashable, Sendable {
    public enum Site: String, Codable, Sendable { case itch, f95zone, other }

    public var page: String
    /// The newest version the page showed at the last check.
    public var latest: String?
    /// The first version seen, for games whose own version RenChan can't read.
    public var firstSeen: String?
    public var checked: Date?
    /// The version the person said they don't want (Dismiss).
    public var dismissed: String?
    /// The version a notification was already posted for.
    public var notified: String?
    public var error: String?

    public init(page: String) { self.page = page }

    public var url: URL? { URL(string: page) }
    public var site: Site { Self.site(of: url) }

    public static func site(of url: URL?) -> Site {
        guard let host = url?.host()?.lowercased() else { return .other }
        if host == "itch.io" || host.hasSuffix(".itch.io") { return .itch }
        if host == "f95zone.to" || host.hasSuffix(".f95zone.to") { return .f95zone }
        return .other
    }

    /// An itch.io game page or an F95zone thread, cleaned up; nil for anything else.
    public static func validate(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard var parts = URLComponents(string: trimmed), parts.scheme == "https" || parts.scheme == "http" else { return nil }
        parts.scheme = "https"
        parts.query = nil
        parts.fragment = nil
        guard let url = parts.url else { return nil }
        switch site(of: url) {
        case .itch: return url.pathComponents.count >= 2 ? url : nil
        case .f95zone:
            // A post link (.../threads/name.123/post-456) watches its thread.
            let comps = url.pathComponents
            guard let i = comps.firstIndex(of: "threads"), i + 1 < comps.count else { return nil }
            return URL(string: "https://f95zone.to/threads/\(comps[i + 1])/")
        case .other: return nil
        }
    }

    /// The F95zone thread id in a thread link ("eternum.12345" → 12345).
    public static func threadID(_ url: URL) -> Int? {
        url.pathComponents.last(where: { $0 != "/" }).flatMap { $0.split(separator: ".").last }.flatMap { Int($0) }
    }

    /// A newer version than the one installed, or than the one first seen when the installed one isn't known.
    public func news(installed: String?) -> String? {
        guard let latest, latest != dismissed else { return nil }
        if let installed { return VersionOrder.compare(latest, installed) == .orderedDescending ? latest : nil }
        guard let firstSeen else { return nil }
        return VersionOrder.compare(latest, firstSeen) == .orderedDescending ? latest : nil
    }

    /// Records a check's result.
    public mutating func record(version: String?, error: String?, at date: Date = .now) {
        checked = date
        self.error = error
        guard let version else { return }
        latest = version
        if firstSeen == nil { firstSeen = version }
    }

    public func isDue(now: Date = .now, every: TimeInterval = 20 * 3600) -> Bool {
        guard let checked else { return true }
        return now.timeIntervalSince(checked) >= every
    }
}

/// Reads a page's newest version (S-033).
public enum PageVersion {
    /// itch.io: the highest version among its download names. F95zone and others: the version in the title.
    public static func parse(_ html: String) -> String? {
        // <div class="upload_name"><strong class="name" title="…">GAME - [0.9] - PC</strong>; attribute order varies.
        let uploads = matches(#"class="upload_name"[^>]*>\s*<strong[^>]*>([^<]+)<"#, in: html).compactMap { VersionOrder.find(in: unescape($0)) }
        if let best = uploads.max(by: { VersionOrder.compare($0, $1) == .orderedAscending }) { return best }
        if let title = matches(#"<title[^>]*>([^<]+)</title>"#, in: html).first {
            // "Name [v0.9] [Developer] | F95zone"
            let name = unescape(title).components(separatedBy: " | ").first ?? ""
            return VersionOrder.find(in: name, anyBracket: true)
        }
        return nil
    }

    public enum Failure: Error, Equatable { case status(Int), noVersion, loginWall }

    public static func fetch(_ url: URL, session: URLSession = .shared, userAgent: String) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Failure.status(http.statusCode) }
        let html = String(decoding: data, as: UTF8.self)
        if html.range(of: #"<title[^>]*>\s*Log in"#, options: [.regularExpression, .caseInsensitive]) != nil {
            throw Failure.loginWall
        }
        if let version = parse(html) { return version }
        throw Failure.noVersion
    }

    static func matches(_ pattern: String, in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'").replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
