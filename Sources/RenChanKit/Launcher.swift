import Darwin
import FileKit
import Foundation
import ProcessKit

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

    /// Makes `copy` from `base` unless it exists. A clone needs one volume; `allowFullCopy` permits a real copy.
    @discardableResult
    public static func prepare(base: URL, copy: URL, allowFullCopy: Bool) throws -> Outcome {
        if FileManager.default.fileExists(atPath: copy.appending(path: "game").path) { return .reused }
        // A copy without game/ is what's left of a stopped one: it goes, and a new one is made.
        try? FileManager.default.removeItem(at: copy)
        do {
            switch try FileClone.clone(base, to: copy, fallback: allowFullCopy ? .copy : .none) {
            case .cloned: return .cloned
            case .copied: return .copied
            }
        } catch let failure as FileClone.Failure {
            throw Failure.cannotClone(path: base.path, reason: failure.reason)
        } catch let error as POSIXError {
            throw Failure.cannotClone(path: base.path, reason: String(cString: strerror(error.code.rawValue)))
        }
    }
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

    /// Starts `lib/<folder>/python -EO renpy.py <copy>`, as renutil does, in its own process group, so `stop()`
    /// reaches what Ren'Py started. Its output and errors go to outputFile. `onEnd` gets the output when it quits.
    public func start(onEnd: (@Sendable (Shell.Output) -> Void)? = nil) throws -> Shell.RunningCommand {
        guard let python = runtime.python else {
            throw Failure.noMacRuntime(version: runtime.version)
        }
        let options = Shell.Options(directory: copy, environment: ["RENPY_LOG_TO_STDOUT": "1"].merging(environment) { $1 },
                                    stdout: .file(outputFile), stderr: .merged)
        return try Shell.start(python.path, ["-EO", runtime.renpyScript.path, copy.path] + arguments, options: options, onEnd: onEnd)
    }

    /// The exit code the compatibility report records: the code Ren'Py exited with, or the signal that ended it
    /// (15 for a stop), as Process's terminationStatus gave it.
    public static func exitCode(of output: Shell.Output) -> Int32 {
        output.signal ?? output.status
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
