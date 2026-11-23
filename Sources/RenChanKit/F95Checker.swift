import Foundation
import SQLite3

/// A library kept in F95Checker, read from its db.sqlite3 (S-034). Read only.
public enum F95Checker {
    public struct Entry: Hashable, Sendable {
        public var threadID: Int
        public var name: String
        public var version: String?
        /// Paths F95Checker launches the game with: an .exe, .sh, .app or .py, or its folder.
        public var executables: [String]
        public var thread: URL { URL(string: "https://f95zone.to/threads/\(threadID)/")! }
    }

    public enum Failure: Error, Equatable { case cantOpen, notF95Checker }

    /// Where F95Checker keeps its database on a Mac.
    public static func defaultDatabases(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        ["Library/Application Support/f95checker/db.sqlite3", ".config/f95checker/db.sqlite3", "Library/Application Support/F95Checker/db.sqlite3"]
            .map { home.appending(path: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func read(_ database: URL) throws -> [Entry] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            throw Failure.cantOpen
        }
        defer { sqlite3_close(db) }
        let columns = Set(rows(db, "PRAGMA table_info(games)").compactMap { $0["name"] ?? nil })
        guard columns.contains("id"), columns.contains("name") else { throw Failure.notF95Checker }
        let exeDir = columns.isEmpty ? nil : (rows(db, "SELECT default_exe_dir FROM settings").first?["default_exe_dir"] ?? nil)
        let wanted = ["id", "name", "version", "executables"].filter(columns.contains)
        return rows(db, "SELECT \(wanted.joined(separator: ", ")) FROM games").compactMap { row in
            guard let id = (row["id"] ?? nil).flatMap({ Int($0) }), let name = row["name"] ?? nil else { return nil }
            let raw = (row["executables"] ?? nil).flatMap { $0.data(using: .utf8) }
            let list = raw.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
            let paths = list.map { path -> String in
                guard !path.hasPrefix("/"), let exeDir, !exeDir.isEmpty else { return path }
                return URL(fileURLWithPath: exeDir).appending(path: path).path
            }
            let version = (row["version"] ?? nil).map { $0.hasPrefix("v") ? String($0.dropFirst()) : $0 }
            return Entry(threadID: id, name: name, version: version?.isEmpty == true ? nil : version, executables: paths)
        }
    }

    /// The folder or .app to add for an executable path.
    public static func gameLocation(_ executable: String) -> URL {
        let url = URL(fileURLWithPath: executable)
        let comps = url.pathComponents
        if let app = comps.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) {
            return URL(fileURLWithPath: NSString.path(withComponents: Array(comps[...app])))
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return url }
        return url.deletingLastPathComponent()
    }

    static func rows(_ db: OpaquePointer, _ sql: String) -> [[String: String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [[String: String?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String?] = [:]
            for i in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, i))
                row[name] = sqlite3_column_text(statement, i).map { String(cString: $0) }
            }
            result.append(row)
        }
        return result
    }
}
