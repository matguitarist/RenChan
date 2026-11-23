import Foundation

/// A game moved to a new version's folder, .app or zip (S-013).
public enum GameUpdate {
    /// Points `game` at the new version. Its id stays, so everything keyed by it stays too: playtime,
    /// status, rating, labels, notes, VNDB details, cover and save backups (and later filters and mods).
    public static func apply(to game: inout Game, title: String, sourcePath: String, kind: SourceKind, basePath: String,
                             detected: VersionDetector.Result, saveDirectory: String?) {
        game.title = title
        game.sourcePath = sourcePath
        game.kind = kind
        game.basePath = basePath
        game.version = detected.version
        game.pythonLine = detected.pythonLine
        game.versionSource = detected.source
        // A new version may name its saves folder; else Ren'Py keeps using the one it had.
        game.saveDirectory = saveDirectory ?? game.saveDirectory
        // A runtime picked for the old version may be wrong for the new one.
        game.runtimeOverride = nil
    }
}
