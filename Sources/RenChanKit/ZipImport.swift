import Foundation

/// Unpacks a game's zip into a folder RenChan owns, refusing entries that escape it (Zip Slip).
public enum ZipImport {
    /// Total uncompressed size, to show before unpacking.
    public static func size(of zip: URL) -> Int64? {
        guard let out = try? run("/usr/bin/zipinfo", ["-t", zip.path]) else { return nil }
        // "123 files, 4567890 bytes uncompressed, ..."
        let words = out.split(separator: " ")
        guard let index = words.firstIndex(where: { $0.hasPrefix("bytes") }), index > 0 else { return nil }
        return Int64(words[index - 1])
    }

    /// The names inside the zip.
    public static func entries(of zip: URL) throws(LocateError) -> [String] {
        do {
            return try run("/usr/bin/zipinfo", ["-1", zip.path]).split(separator: "\n").map(String.init)
        } catch {
            throw .unzipFailed(error.localizedDescription)
        }
    }

    /// The first entry that would land outside the target folder, or nil when every entry is safe.
    public static func unsafeEntry(_ names: [String]) -> String? {
        for name in names {
            if name.hasPrefix("/") || name.hasPrefix("\\") || name.contains(":") { return name }
            let parts = name.split(whereSeparator: { $0 == "/" || $0 == "\\" })
            var depth = 0
            for part in parts {
                if part == ".." { depth -= 1 } else if part != "." { depth += 1 }
                if depth < 0 { return name }
            }
        }
        return nil
    }

    /// Unpacks `zip` into `folder` (created, must not exist yet).
    public static func unpack(_ zip: URL, into folder: URL) throws(LocateError) {
        let names = try entries(of: zip)
        if let bad = unsafeEntry(names) { throw .unsafeZip(bad) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            _ = try run("/usr/bin/ditto", ["-x", "-k", "--noqtn", zip.path, folder.path])
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw .unzipFailed(error.localizedDescription)
        }
    }
}

struct CommandError: LocalizedError {
    let output: String
    var errorDescription: String? { output.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Runs a command and returns its output; throws with the output when it fails.
@discardableResult
func run(_ tool: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else { throw CommandError(output: text.isEmpty ? "\(tool) exited \(process.terminationStatus)" : text) }
    return text
}
