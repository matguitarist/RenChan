import DownloadKit
import Foundation

/// Downloads a runtime from renpy.org through DownloadKit: progress, retries that pick up where a dropped
/// connection stopped, and the SHA-256 from renpy.org's checksums.txt checked before the archive is installed.
public enum RuntimeDownload {
    public enum Failure: Error, Equatable, Sendable {
        case noChecksum
        case checksumMismatch(expected: String, actual: String)
        case http(Int)
    }

    /// Downloads into `store`. `progress` gets (bytes so far, total bytes or nil).
    public static func install(_ version: String, into store: RuntimeStore,
                               progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws {
        do {
            let sums = try await Download.data(from: RuntimeCatalog.checksumsURL(version), options: options)
            let name = RuntimeCatalog.archiveURL(version).lastPathComponent
            guard let expected = SHA256Hex.find(for: name, in: String(decoding: sums, as: UTF8.self)) else { throw Failure.noChecksum }
            // Hidden, like the part file beside it, so a stopped install never looks like a runtime; gone once installed.
            let archive = store.folder.appending(path: ".\(name)")
            defer { try? FileManager.default.removeItem(at: archive) }
            try await Download.file(RuntimeCatalog.archiveURL(version), to: archive, sha256: expected, options: options) { progress($0.received, $0.total) }
            try store.install(archive: archive, version: version)
        } catch let error as DownloadError {
            throw failure(error)
        }
    }

    /// renpy.org has always seen the system's User-Agent from RenChan.
    static var options: DownloadOptions { DownloadOptions(usesSystemUserAgent: true) }

    /// DownloadKit's errors as RenChan's own, so the Runtimes page words them as before.
    static func failure(_ error: DownloadError) -> any Error {
        switch error {
        case .http(let status, _): Failure.http(status)
        case .rateLimited(_, let status): Failure.http(status)
        case .checksumMismatch(let expected, let actual): Failure.checksumMismatch(expected: expected, actual: actual)
        default: error
        }
    }
}
