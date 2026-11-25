import ArchiveKit
import Foundation

/// Unpacks a game's or a mod's zip into a folder RenChan owns, through ArchiveKit: every entry is checked first
/// (Zip Slip: "..", absolute paths, links pointing out), and it is unpacked beside the folder, moved in only when whole.
/// Its failures are worded as LocateError, which the app turns into sentences.
public enum ZipImport {
    /// Total uncompressed size, to show before unpacking.
    public static func size(of zip: URL) -> Int64? {
        (try? Zip.uncompressedSize(zip)).map { Int64(clamping: $0) }
    }

    /// Throws notAZip when the file doesn't start with a zip's signature (PK).
    public static func check(_ zip: URL) throws(LocateError) {
        guard Zip.isZip(zip) else {
            let size = (try? zip.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            throw .notAZip(size: Int64(size))
        }
    }

    /// The names inside the zip.
    public static func entries(of zip: URL) throws(LocateError) -> [String] {
        do {
            return try Zip.names(zip)
        } catch {
            throw locateError(error)
        }
    }

    /// Unpacks `zip` into `folder` (must not exist yet), off the caller's thread: a game's zip of several GB takes
    /// minutes. The downloaded-file mark is left off, so the game's own programs run.
    public static func unpack(_ zip: URL, into folder: URL) async throws(LocateError) {
        do {
            try await Zip.unpack(zip, into: folder, dropsQuarantine: true)
        } catch let error as ArchiveError {
            throw locateError(error)
        } catch {
            throw .unzipFailed(error.localizedDescription)
        }
    }

    static func locateError(_ error: ArchiveError) -> LocateError {
        switch error {
        case .notAZip(let size): .notAZip(size: size)
        case .unsafeEntry(let name): .unsafeZip(name)
        case .damaged(let reason), .toolFailed(let reason): .unzipFailed(reason)
        default: .unzipFailed(error.localizedDescription)
        }
    }
}
