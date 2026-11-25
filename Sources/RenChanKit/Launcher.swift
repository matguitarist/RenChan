import Darwin
import Foundation

/// The copy of a game RenChan plays: an APFS clone of the game's base folder, so the original is never written to.
public enum WorkingCopy {
    public enum Outcome: Equatable, Sendable {
        case reused, cloned, copied
    }

    public enum Failure: Error, LocalizedError, Equatable, Sendable {
        /// The base folder can't be cloned there, and a full copy wasn't allowed or can't help.
        case cannotClone(path: String, reason: String)

        public var errorDescription: String? {
            switch self {
            case .cannotClone(let path, let reason): "Couldn't clone \(path): \(reason)"
            }
        }
    }

    /// True when both folders are on one volume, where a clone costs no space.
    public static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        func volume(_ url: URL) -> NSObject? {
            var probe = url
            while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
            return (try? probe.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        }
        guard let left = volume(a), let right = volume(b) else { return false }
        return left.isEqual(right)
    }

    /// Makes `copy` from `base` unless it exists. A clone needs one volume; `allowFullCopy` permits a real copy.
    @discardableResult
    public static func prepare(base: URL, copy: URL, allowFullCopy: Bool) throws -> Outcome {
        if FileManager.default.fileExists(atPath: copy.appending(path: "game").path) { return .reused }
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: copy)
        if clonefile(base.path, copy.path, 0) == 0 { return .cloned }
        let reason = errno
        guard allowFullCopy, reason == EXDEV || reason == ENOTSUP else {
            throw Failure.cannotClone(path: base.path, reason: String(cString: strerror(reason)))
        }
        try FileManager.default.copyItem(at: base, to: copy)
        return .copied
    }

    /// The folder's size, to ask before a full copy.
    public static func size(of folder: URL) -> Int64 { RuntimeStore.size(of: folder) }
}

/// One run of a game on a runtime: the process, its output file, and what it left when it quit.
public struct LaunchPlan: Sendable {
    public enum Failure: Error, LocalizedError, Equatable, Sendable {
        /// The runtime has no Python this Mac runs.
        case noMacRuntime(version: String)

        public var errorDescription: String? {
            switch self {
            case .noMacRuntime(let version): "Ren'Py \(version) has no Mac runtime."
            }
        }
    }

    public let runtime: Runtime
    public let copy: URL
    public let outputFile: URL
    /// Extra environment, such as HOME in tests.
    public var environment: [String: String] = [:]
    /// A Ren'Py command and its arguments after the game folder, such as RenChan's save tool (S-036).
    public var arguments: [String] = []

    public init(runtime: Runtime, copy: URL, outputFile: URL, environment: [String: String] = [:], arguments: [String] = []) {
        self.runtime = runtime
        self.copy = copy
        self.outputFile = outputFile
        self.environment = environment
        self.arguments = arguments
    }

    /// `lib/<folder>/python -EO renpy.py <copy>`, as renutil does. Its output goes to outputFile.
    public func makeProcess() throws -> Process {
        guard let python = runtime.python else {
            throw Failure.noMacRuntime(version: runtime.version)
        }
        let process = Process()
        process.executableURL = python
        process.arguments = ["-EO", runtime.renpyScript.path, copy.path] + arguments
        process.currentDirectoryURL = copy
        var env = ProcessInfo.processInfo.environment
        env["RENPY_LOG_TO_STDOUT"] = "1"
        for (key, value) in environment { env[key] = value }
        process.environment = env
        FileManager.default.createFile(atPath: outputFile.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputFile)
        process.standardOutput = handle
        process.standardError = handle
        return process
    }
}

/// What a finished run left behind.
public struct LaunchResult: Sendable, Equatable {
    public var exitCode: Int32
    /// traceback.txt or errors.txt, when the game wrote one during this run.
    public var traceback: String?
    /// The end of the run's output.
    public var outputTail: String

    public var failed: Bool { exitCode != 0 || traceback != nil }

    /// Reads what a run left in the working copy after `started`.
    public static func read(copy: URL, outputFile: URL, exitCode: Int32, started: Date) -> LaunchResult {
        var traceback: String?
        for name in ["traceback.txt", "errors.txt"] {
            let file = copy.appending(path: name)
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified >= started.addingTimeInterval(-1), let text = try? String(contentsOf: file, encoding: .utf8) {
                traceback = text
                break
            }
        }
        let output = (try? String(contentsOf: outputFile, encoding: .utf8)) ?? ""
        let tail = output.split(separator: "\n", omittingEmptySubsequences: false).suffix(40).joined(separator: "\n")
        return LaunchResult(exitCode: exitCode, traceback: traceback, outputTail: tail)
    }
}

/// Where Ren'Py keeps saves on a Mac: ~/Library/RenPy/<config.save_directory>.
public enum SaveFolder {
    public static func root(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/RenPy", directoryHint: .isDirectory)
    }

    /// The saves in a folder (*.save).
    public static func count(_ folder: URL) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".save") }.count
    }

    /// Folders under the root changed since `date`, newest first; the game's own folder after its first run.
    public static func changed(since date: Date, root: URL) -> [String] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return folders
            .filter { !["backups", "tokens"].contains($0.lastPathComponent) && !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { url -> (String, Date)? in
                guard let modified = newest(in: url), modified >= date else { return nil }
                return (url.lastPathComponent, modified)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private static func newest(in folder: URL) -> Date? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return ([folder] + files).compactMap { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }.max()
    }
}
