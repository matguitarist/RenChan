import CryptoKit
import Foundation

/// Downloads a runtime from renpy.org with progress, checks its SHA-256 and installs it.
public enum RuntimeDownload {
    public enum Failure: Error, Equatable, Sendable {
        case noChecksum
        case checksumMismatch(expected: String, actual: String)
        case http(Int)
    }

    /// Downloads into `store`. `progress` gets (bytes so far, total bytes or nil).
    public static func install(_ version: String, into store: RuntimeStore,
                               progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws {
        let (sums, sumsResponse) = try await URLSession.shared.data(from: RuntimeCatalog.checksumsURL(version))
        try check(sumsResponse)
        let name = RuntimeCatalog.archiveURL(version).lastPathComponent
        guard let expected = RuntimeCatalog.sha256(for: name, in: String(decoding: sums, as: UTF8.self)) else { throw Failure.noChecksum }

        try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
        let archive = store.folder.appending(path: ".\(name).part")
        try? FileManager.default.removeItem(at: archive)
        defer { try? FileManager.default.removeItem(at: archive) }

        let (bytes, response) = try await URLSession.shared.bytes(from: RuntimeCatalog.archiveURL(version))
        try check(response)
        let total = response.expectedContentLength > 0 ? response.expectedContentLength : nil
        FileManager.default.createFile(atPath: archive.path, contents: nil)
        let handle = try FileHandle(forWritingTo: archive)
        var hasher = SHA256()
        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var received: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try Task.checkCancellation()
                hasher.update(data: buffer)
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(received, total)
            }
        }
        hasher.update(data: buffer)
        try handle.write(contentsOf: buffer)
        received += Int64(buffer.count)
        try handle.close()
        progress(received, total)

        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        try verify(actual: actual, expected: expected)
        try store.install(archive: archive, version: version)
    }

    /// Throws when the hashes differ; the caller has already deleted nothing yet, `install` deletes the part file.
    public static func verify(actual: String, expected: String) throws {
        guard actual.lowercased() == expected.lowercased() else { throw Failure.checksumMismatch(expected: expected, actual: actual) }
    }

    private static func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Failure.http(http.statusCode) }
    }
}
