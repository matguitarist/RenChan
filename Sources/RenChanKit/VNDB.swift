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
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: released)
    }
}

/// VNDB's public API (api.vndb.org/kana). No account, no key.
public enum VNDB {
    public static let endpoint = URL(string: "https://api.vndb.org/kana/vn")!
    static let fields = "title,alttitle,developers.name,released,description,image.url"

    public enum Failure: Error, Equatable, Sendable {
        case http(Int)
    }

    /// The request body for a title search, best matches first.
    public static func searchBody(_ title: String, results: Int = 10) -> Data {
        body(["search", "=", title], results: results)
    }

    public static func idBody(_ id: String) -> Data {
        body(["id", "=", id], results: 1)
    }

    private static func body(_ filter: [String], results: Int) -> Data {
        let object: [String: Any] = ["filters": filter, "fields": fields, "results": results,
                                     "sort": filter.first == "search" ? "searchrank" : "id"]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
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

    private static func post(_ body: Data) async throws -> Data {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
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
