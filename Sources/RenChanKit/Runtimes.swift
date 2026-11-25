import Foundation
import ProcessKit

/// An official Ren'Py SDK, used to play games. Downloaded from renpy.org into the runtimes folder.
public struct Runtime: Identifiable, Hashable, Sendable {
    /// "8.6.1": the folder name on renpy.org/dl and in the runtimes folder.
    public let version: String
    public let folder: URL
    public var id: String { version }

    public init(version: String, folder: URL) {
        self.version = version
        self.folder = folder
    }

    /// The Mac Python that runs games, best first: universal (native), then Intel (Rosetta).
    public var python: URL? { RuntimeCatalog.python(in: folder) }
    /// False when only an Intel build is in it: it runs under Rosetta on Apple silicon.
    public var isUniversal: Bool { python?.deletingLastPathComponent().lastPathComponent.contains("universal") ?? false }
    public var renpyScript: URL { folder.appending(path: "renpy.py") }
}

/// Which runtime plays which game, and where to get it (docs/research/runtime.md).
public enum RuntimeCatalog {
    /// Every Python 2 game from 7.4 on plays on the last 7.x, native on Apple silicon.
    public static let python2 = "7.8.7"
    /// Every Python 3 game plays on the newest 8.x.
    public static let python3 = "8.6.1"

    /// The runtime version for a game: the override, the line's default, or the exact version for games before 7.4.
    public static func choose(version: RenPyVersion?, pythonLine: PythonLine?, override: String? = nil) -> String? {
        if let override { return override }
        let line = pythonLine ?? version?.pythonLine
        switch line {
        case .python3: return python3
        case .python2:
            guard let version, version < RenPyVersion("7.4")! else { return python2 }
            return downloadName(version)
        case nil: return nil
        }
    }

    /// "6.99.14.3" from "6.99.14.3.3347": renpy.org names folders without the build number.
    public static func downloadName(_ version: RenPyVersion) -> String {
        var parts = version.parts
        while parts.count > 3, let last = parts.last, last >= 1000 { parts.removeLast() }
        return parts.map(String.init).joined(separator: ".")
    }

    /// The exact version a game was made with, when it differs from the runtime chosen for it.
    public static func exactAlternative(version: RenPyVersion?, chosen: String) -> String? {
        guard let version else { return nil }
        let exact = downloadName(version)
        return exact == chosen ? nil : exact
    }

    public static func archiveURL(_ version: String) -> URL {
        URL(string: "https://www.renpy.org/dl/\(version)/renpy-\(version)-sdk.tar.bz2")!
    }

    public static func checksumsURL(_ version: String) -> URL {
        URL(string: "https://www.renpy.org/dl/\(version)/checksums.txt")!
    }

    /// The SHA-256 for `file` in a checksums.txt that mixes MD5, SHA-1 and SHA-256 lines.
    public static func sha256(for file: String, in checksums: String) -> String? {
        for line in checksums.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2, parts.last == Substring(file), parts[0].count == 64 else { continue }
            return parts[0].lowercased()
        }
        return nil
    }

    /// Mac lib folders, best first (docs/research/runtime.md, "Runtimes").
    static let macFolders = ["py3-mac-universal", "py2-mac-universal", "py3-mac-x86_64", "py2-mac-x86_64", "mac-x86_64", "darwin-x86_64", "darwin-i686"]

    static func python(in sdk: URL) -> URL? {
        let roots = [sdk.appending(path: "lib"), sdk.appending(path: "renpy.app/Contents/MacOS/lib")]
        for folder in macFolders {
            for root in roots {
                for name in ["python", "pythonw", "renpy"] {
                    let candidate = root.appending(path: folder).appending(path: name)
                    if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
                }
            }
        }
        return nil
    }
}

/// The runtimes folder: one SDK per version, each in its own folder.
public struct RuntimeStore: Sendable {
    public let folder: URL

    public enum Failure: Error, LocalizedError, Equatable, Sendable {
        /// The SDK archive unpacked, but none of its lib folders runs on a Mac.
        case noMacRuntime(version: String)

        public var errorDescription: String? {
            switch self {
            case .noMacRuntime(let version): "The Ren'Py \(version) download has no Mac runtime in it."
            }
        }
    }

    public init(folder: URL) {
        self.folder = folder
    }

    public func installed() -> [Runtime] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }
            .map { Runtime(version: $0, folder: folder.appending(path: $0, directoryHint: .isDirectory)) }
            .filter { $0.python != nil }
            .sorted { (RenPyVersion($0.version) ?? RenPyVersion("0.0")!) > (RenPyVersion($1.version) ?? RenPyVersion("0.0")!) }
    }

    public func runtime(_ version: String) -> Runtime? {
        installed().first { $0.version == version }
    }

    /// Unpacks a downloaded SDK archive into place. The archive holds one folder, renpy-<v>-sdk.
    public func install(archive: URL, version: String) throws {
        let staging = folder.appending(path: ".unpack-\(version)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try Shell.runSync("/usr/bin/tar", ["-xjf", archive.path, "-C", staging.path]).check()
        let inside = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            .first { !$0.lastPathComponent.hasPrefix(".") }
        guard let inside, RuntimeCatalog.python(in: inside) != nil else {
            throw Failure.noMacRuntime(version: version)
        }
        let target = folder.appending(path: version, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: inside, to: target)
    }

    public func remove(_ runtime: Runtime) throws {
        try FileManager.default.removeItem(at: runtime.folder)
    }

    /// Size on disk, for the Runtimes page.
    public static func size(of folder: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}
