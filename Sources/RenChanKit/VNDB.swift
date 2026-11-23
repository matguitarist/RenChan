import Foundation

/// What VNDB says about a game: the Visual Novel Database's id, title, developer, release date, description and cover (S-010).
public struct VNDBInfo: Codable, Hashable, Identifiable, Sendable {
    /// "v945".
    public var id: String
    public var title: String
    /// The original title, often in Japanese.
    public var originalTitle: String?
    public var developer: String?
    /// "2009-04-29", "2009" or "TBA", as VNDB writes it.
    public var released: String?
    /// Plain text, spoilers removed.
    public var description: String?
    public var imageURL: String?

    public init(id: String, title: String, originalTitle: String? = nil, developer: String? = nil, released: String? = nil,
                description: String? = nil, imageURL: String? = nil) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.developer = developer
        self.released = released
        self.description = description
        self.imageURL = imageURL
    }

    public var pageURL: URL { URL(string: "https://vndb.org/\(id)")! }

    /// The release date when VNDB knows the day.
    public var releaseDate: Date? {
        guard let released, released.count == 10 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // A calendar day, read in the Mac's own time zone so it shows as the same day.
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: released)
    }
}

/// One release of a game on VNDB, with the links to where it is sold or downloaded (S-028).
public struct VNDBRelease: Hashable, Identifiable, Sendable {
    public struct Link: Hashable, Sendable {
        public var label: String
        public var url: URL
        public init(label: String, url: URL) { self.label = label; self.url = url }
    }

    /// "r82104".
    public var id: String
    /// Often holds the version: "Eternum [v0.9.5]".
    public var title: String
    public var released: String?
    /// "win", "mac", "lin", "and"…
    public var platforms: [String]
    public var freeware: Bool
    /// False for fan translations and unofficial ports.
    public var official: Bool
    public var engine: String?
    public var links: [Link]

    public init(id: String, title: String, released: String? = nil, platforms: [String] = [], freeware: Bool = false,
                official: Bool = true, engine: String? = nil, links: [Link] = []) {
        self.id = id
        self.title = title
        self.released = released
        self.platforms = platforms
        self.freeware = freeware
        self.official = official
        self.engine = engine
        self.links = links
    }
}

/// VNDB's public API (api.vndb.org/kana). No account, no key.
public enum VNDB {
    public static let endpoint = URL(string: "https://api.vndb.org/kana/vn")!
    static let fields = "title,alttitle,developers.name,released,description,image.url"

    public enum Failure: Error, Equatable, Sendable {
        case http(Int)
    }

    /// The request body for a title search, best matches first. `renpyOnly` keeps games with a Ren'Py release;
    /// an empty title lists the most popular ones.
    public static func searchBody(_ title: String, renpyOnly: Bool = false, results: Int = 10) -> Data {
        let renpy: [Any] = ["release", "=", ["engine", "=", "Ren'Py"]]
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let search: [Any] = ["search", "=", query]
        let filter: [Any]
        switch (query.isEmpty, renpyOnly) {
        case (false, false): filter = search
        case (false, true): filter = ["and", search, renpy]
        case (true, _): filter = renpy
        }
        return body(filter, results: results, sort: query.isEmpty ? "popularity" : "searchrank", reverse: query.isEmpty)
    }

    public static func idBody(_ id: String) -> Data {
        body(["id", "=", id], results: 1, sort: "id")
    }

    private static func body(_ filter: [Any], results: Int, sort: String, reverse: Bool = false, fields: String = fields) -> Data {
        var object: [String: Any] = ["filters": filter, "fields": fields, "results": results, "sort": sort]
        if reverse { object["reverse"] = true }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    /// The request body for a game's releases, newest first.
    public static func releasesBody(_ vnID: String) -> Data {
        body(["vn", "=", ["id", "=", vnID]], results: 40, sort: "released", reverse: true,
             fields: "title,released,platforms,freeware,official,engine,extlinks.url,extlinks.label")
    }

    /// Reads VNDB's releases: official ones first, then the newest.
    public static func parseReleases(_ data: Data) throws -> [VNDBRelease] {
        struct Response: Decodable {
            struct Release: Decodable {
                struct Link: Decodable { var url: String; var label: String }
                var id: String
                var title: String
                var released: String?
                var platforms: [String]?
                var freeware: Bool?
                var official: Bool?
                var engine: String?
                var extlinks: [Link]?
            }
            var results: [Release]
        }
        let releases = try JSONDecoder().decode(Response.self, from: data).results.map { r in
            VNDBRelease(id: r.id, title: r.title, released: r.released, platforms: r.platforms ?? [], freeware: r.freeware ?? false,
                        official: r.official ?? true, engine: r.engine,
                        links: (r.extlinks ?? []).compactMap { link in URL(string: link.url).map { VNDBRelease.Link(label: link.label, url: $0) } })
        }
        return releases.enumerated().sorted { a, b in
            a.element.official != b.element.official ? a.element.official : a.offset < b.offset
        }.map(\.element)
    }

    public static func search(_ title: String, renpyOnly: Bool) async throws -> [VNDBInfo] {
        try parse(await post(searchBody(title, renpyOnly: renpyOnly, results: 30)))
    }

    public static func releases(_ vnID: String) async throws -> [VNDBRelease] {
        try parseReleases(await post(releasesBody(vnID), to: releaseEndpoint))
    }

    public static let releaseEndpoint = URL(string: "https://api.vndb.org/kana/release")!

    /// True when a game added from a folder or zip is plausibly the VNDB entry it came from:
    /// one title, letters and digits only and version numbers dropped, contains the other.
    public static func plausible(_ gameTitle: String, matches info: VNDBInfo) -> Bool {
        func words(_ text: String) -> String {
            text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .filter { word in !word.allSatisfy(\.isNumber) && !(word.first == "v" && word.dropFirst().allSatisfy(\.isNumber) && word.count > 1) }
                .joined()
        }
        let game = words(gameTitle)
        let candidates = [info.title, info.originalTitle].compactMap { $0 }.map(words).filter { !$0.isEmpty }
        guard !game.isEmpty else { return false }
        return candidates.contains { game.contains($0) || $0.contains(game) }
    }

    /// Reads VNDB's answer.
    public static func parse(_ data: Data) throws -> [VNDBInfo] {
        struct Response: Decodable {
            struct VN: Decodable {
                struct Developer: Decodable { var name: String }
                struct Image: Decodable { var url: String? }
                var id: String
                var title: String
                var alttitle: String?
                var developers: [Developer]?
                var released: String?
                var description: String?
                var image: Image?
            }
            var results: [VN]
        }
        return try JSONDecoder().decode(Response.self, from: data).results.map { vn in
            VNDBInfo(id: vn.id, title: vn.title, originalTitle: vn.alttitle,
                     developer: vn.developers.map { $0.map(\.name).joined(separator: ", ") }.flatMap { $0.isEmpty ? nil : $0 },
                     released: vn.released, description: vn.description.map(plainText), imageURL: vn.image?.url)
        }
    }

    public static func search(_ title: String) async throws -> [VNDBInfo] {
        try parse(await post(searchBody(title)))
    }

    public static func details(_ id: String) async throws -> VNDBInfo? {
        try parse(await post(idBody(id))).first
    }

    private static func post(_ body: Data, to url: URL = endpoint) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Failure.http(http.statusCode) }
        return data
    }

    /// Downloads a cover image to `file`, replacing what was there.
    public static func downloadCover(_ url: URL, to file: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Failure.http(http.statusCode) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    /// Links a game to VNDB, or refreshes it. True when RenChan should download VNDB's cover:
    /// a cover the person chose stays.
    public static func apply(_ info: VNDBInfo, to game: inout Game) -> Bool {
        game.vndb = info
        return !game.customCover && info.imageURL != nil
    }

    /// VNDB's BBCode as plain text: links keep their words, spoilers go.
    public static func plainText(_ text: String) -> String {
        var out = text
        out = out.replacingOccurrences(of: #"\[spoiler\][\s\S]*?\[/spoiler\]"#, with: "", options: [.regularExpression, .caseInsensitive])
        out = out.replacingOccurrences(of: #"\[url=[^\]]*\]([\s\S]*?)\[/url\]"#, with: "$1", options: [.regularExpression, .caseInsensitive])
        out = out.replacingOccurrences(of: #"\[/?(b|i|u|s|raw|code|quote)\]"#, with: "", options: [.regularExpression, .caseInsensitive])
        out = out.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
