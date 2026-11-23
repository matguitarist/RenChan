import Foundation

/// What the person added to the library.
public enum SourceKind: String, Codable, Sendable {
    /// A folder with game/ in it, or one level down.
    case folder
    /// A Mac build: Game.app with Contents/Resources/autorun/game.
    case app
    /// A zip RenChan unpacked into its own folder.
    case zip
}

/// One game in the library. Paths are plain strings so library.json reads well.
public struct Game: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    /// The folder, .app or zip the person added. Never written to.
    public var sourcePath: String
    public var kind: SourceKind
    /// The folder that holds game/: inside the source, or the unpacked zip.
    public var basePath: String
    public var version: RenPyVersion?
    public var pythonLine: PythonLine?
    public var versionSource: VersionSource?
    /// config.save_directory, the folder under ~/Library/RenPy.
    public var saveDirectory: String?
    public var added: Date
    public var lastPlayed: Date?
    /// A runtime picked by hand after a failure ("7.4.11"); nil uses RuntimeCatalog's choice.
    public var runtimeOverride: String?
    /// Seconds the game has run from RenChan, summed over every session (S-009).
    public var playtime: TimeInterval = 0
    /// The VNDB entry this game is linked to (S-010).
    public var vndb: VNDBInfo?
    /// The person chose the cover; refreshing from VNDB keeps it.
    public var customCover = false
    /// The person's own: status, 1 to 5 stars, labels, notes (S-011).
    public var status: PlayStatus = .notStarted
    public var rating: Int?
    public var labels: [String] = []
    public var notes = ""
    /// The screen filter it plays with (S-014).
    public var filter: FilterSetting?
    /// Its mods, in load order (S-017, S-018).
    public var mods: [ModUse] = []
    /// Saves were backed up before the first modded launch (S-020).
    public var backedUpBeforeMods = false
    /// PDF or text walkthroughs kept with the game (S-032).
    public var walkthroughs: [Walkthrough] = []
    /// Ren'Py's console and fast skip (S-022).
    public var devTools = DevTools()
    /// What happened the last times it was played, newest first (S-027).
    public var runs: [RunRecord] = []
    /// The game's own version, such as "0.9" (S-033).
    public var gameVersion: String?
    /// The itch.io page or F95zone thread watched for new versions (S-033).
    public var watch: UpdateWatch?
    /// A newer version on the watched page, if any.
    public var newVersion: String? { watch?.news(installed: gameVersion) }
    public var hasModsOn: Bool { mods.contains(where: \.enabled) }

    public init(id: UUID = UUID(), title: String, sourcePath: String, kind: SourceKind, basePath: String,
                version: RenPyVersion? = nil, pythonLine: PythonLine? = nil, versionSource: VersionSource? = nil,
                saveDirectory: String? = nil, added: Date = .now, lastPlayed: Date? = nil, runtimeOverride: String? = nil) {
        self.id = id
        self.title = title
        self.sourcePath = sourcePath
        self.kind = kind
        self.basePath = basePath
        self.version = version
        self.pythonLine = pythonLine
        self.versionSource = versionSource
        self.saveDirectory = saveDirectory
        self.added = added
        self.lastPlayed = lastPlayed
        self.runtimeOverride = runtimeOverride
    }

    public init(from decoder: any Decoder) throws {
        // Fields added after 0.1.0 have defaults, so an older library.json still opens.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        sourcePath = try c.decode(String.self, forKey: .sourcePath)
        kind = try c.decode(SourceKind.self, forKey: .kind)
        basePath = try c.decode(String.self, forKey: .basePath)
        version = try c.decodeIfPresent(RenPyVersion.self, forKey: .version)
        pythonLine = try c.decodeIfPresent(PythonLine.self, forKey: .pythonLine)
        versionSource = try c.decodeIfPresent(VersionSource.self, forKey: .versionSource)
        saveDirectory = try c.decodeIfPresent(String.self, forKey: .saveDirectory)
        added = try c.decode(Date.self, forKey: .added)
        lastPlayed = try c.decodeIfPresent(Date.self, forKey: .lastPlayed)
        runtimeOverride = try c.decodeIfPresent(String.self, forKey: .runtimeOverride)
        playtime = try c.decodeIfPresent(TimeInterval.self, forKey: .playtime) ?? 0
        vndb = try c.decodeIfPresent(VNDBInfo.self, forKey: .vndb)
        customCover = try c.decodeIfPresent(Bool.self, forKey: .customCover) ?? false
        // A game played before statuses existed is being played.
        status = try c.decodeIfPresent(PlayStatus.self, forKey: .status) ?? (lastPlayed == nil ? .notStarted : .playing)
        rating = try c.decodeIfPresent(Int.self, forKey: .rating)
        labels = try c.decodeIfPresent([String].self, forKey: .labels) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        filter = try c.decodeIfPresent(FilterSetting.self, forKey: .filter)
        mods = try c.decodeIfPresent([ModUse].self, forKey: .mods) ?? []
        backedUpBeforeMods = try c.decodeIfPresent(Bool.self, forKey: .backedUpBeforeMods) ?? false
        walkthroughs = try c.decodeIfPresent([Walkthrough].self, forKey: .walkthroughs) ?? []
        devTools = try c.decodeIfPresent(DevTools.self, forKey: .devTools) ?? DevTools()
        runs = try c.decodeIfPresent([RunRecord].self, forKey: .runs) ?? []
        gameVersion = try c.decodeIfPresent(String.self, forKey: .gameVersion)
        watch = try c.decodeIfPresent(UpdateWatch.self, forKey: .watch)
    }

    public var baseURL: URL { URL(fileURLWithPath: basePath, isDirectory: true) }
    public var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
}

/// library.json: every game, in the order they were added.
public enum LibraryFile {
    public static func load(_ url: URL) throws -> [Game] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Game].self, from: Data(contentsOf: url))
    }

    public static func save(_ games: [Game], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(games).write(to: url, options: .atomic)
    }
}
