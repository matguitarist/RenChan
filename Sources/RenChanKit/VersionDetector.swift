import Foundation

/// Which file told RenChan a game's Ren'Py version.
public enum VersionSource: String, Codable, Sendable {
    case vcVersion = "renpy/vc_version.py"
    case initFile = "renpy/__init__.py"
    case scriptVersion = "game/script_version.txt"
    case logFile = "log.txt"
    case libFolders = "lib/"
}

/// Reads a game's Ren'Py version from its files, trying the surest first.
public enum VersionDetector {
    public struct Result: Equatable, Sendable {
        public var version: RenPyVersion?
        public var pythonLine: PythonLine?
        public var source: VersionSource?
    }

    public static func detect(base: URL) -> Result {
        let renpy = base.appending(path: "renpy", directoryHint: .isDirectory)
        // 8.x and late 7.x: version = '8.6.1.26111705'
        if let text = read(renpy.appending(path: "vc_version.py")),
           let version = quoted(after: "version", in: text).flatMap(RenPyVersion.init) {
            return Result(version: version, pythonLine: version.pythonLine, source: .vcVersion)
        }
        // Up to 8.1: version_tuple = (7, 4, 11, vc_version)
        if let text = read(renpy.appending(path: "__init__.py")), let version = tuple(after: "version_tuple", in: text) {
            return Result(version: version, pythonLine: version.pythonLine, source: .initFile)
        }
        // Written by Ren'Py's build: "(7, 4, 11)" or "7.4.11"
        if let text = read(base.appending(path: "game/script_version.txt")),
           let version = tuple(after: "", in: text) ?? RenPyVersion(text) {
            return Result(version: version, pythonLine: version.pythonLine, source: .scriptVersion)
        }
        // A developer's leftover log: "Ren'Py 7.4.11.2266" on one of the first lines.
        if let text = read(base.appending(path: "log.txt")),
           let line = text.split(whereSeparator: \.isNewline).prefix(10).first(where: { $0.hasPrefix("Ren'Py ") }),
           let version = RenPyVersion(line) {
            return Result(version: version, pythonLine: version.pythonLine, source: .logFile)
        }
        // No version, but lib/ tells the Python line: py3-* is 8.x, py2-* or older names are 7.x and before.
        let lib = (try? FileManager.default.contentsOfDirectory(atPath: base.appending(path: "lib").path)) ?? []
        if lib.contains(where: { $0.hasPrefix("py3-") || $0.hasPrefix("python3") }) {
            return Result(version: nil, pythonLine: .python3, source: .libFolders)
        }
        if lib.contains(where: { $0.hasPrefix("py2-") || $0.hasPrefix("python2") || $0.hasPrefix("windows-") || $0.hasPrefix("linux-") || $0.hasPrefix("darwin-") || $0.hasPrefix("mac-") }) {
            return Result(version: nil, pythonLine: .python2, source: .libFolders)
        }
        return Result(version: nil, pythonLine: nil, source: nil)
    }

    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), data.count < 2_000_000 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// The quoted value in a line like `version = '8.6.1.26111705'`.
    static func quoted(after name: String, in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == name else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard let first = value.first, first == "'" || first == "\"" else { continue }
            return String(value.dropFirst().prefix { $0 != first })
        }
        return nil
    }

    /// The numbers in `version_tuple = (7, 4, 11, vc_version)`; an empty name reads the first tuple.
    static func tuple(after name: String, in text: String) -> RenPyVersion? {
        for line in text.split(whereSeparator: \.isNewline) {
            if !name.isEmpty {
                let parts = line.split(separator: "=", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == name else { continue }
            }
            guard let open = line.firstIndex(of: "("), let close = line[open...].firstIndex(of: ")") else { continue }
            let numbers = line[line.index(after: open)..<close].split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard numbers.count >= 2 else { continue }
            return RenPyVersion(numbers.map(String.init).joined(separator: "."))
        }
        return nil
    }
}
