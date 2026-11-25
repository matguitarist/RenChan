import Foundation
import ImageIO
import PictureKit

/// One picture of a game for RenChan's gallery (S-042): a loose file, or bytes inside a Ren'Py archive.
/// Ren'Py's save tool lists them; RenChan then reads the bytes itself, without starting Ren'Py again.
public struct GamePicture: Decodable, Sendable, Hashable, Identifiable {
    public struct Part: Decodable, Sendable, Hashable {
        public var offset: Int?
        public var length: Int?
        /// Leading bytes kept in the archive's index (RPA-3.0 "start"), base64.
        public var bytes: String?
        public init(offset: Int? = nil, length: Int? = nil, bytes: String? = nil) {
            (self.offset, self.length, self.bytes) = (offset, length, bytes)
        }
    }

    /// The path inside game/, such as "images/cg/beach.webp".
    public var path: String
    /// The loose file, when it isn't archived.
    public var file: String?
    /// The archive it sits in, and where.
    public var archive: String?
    public var parts: [Part]?
    public var id: String { path }

    public init(path: String, file: String? = nil, archive: String? = nil, parts: [Part]? = nil) {
        (self.path, self.file, self.archive, self.parts) = (path, file, archive, parts)
    }

    /// The folder it is grouped under: "images/cg" for "images/cg/beach.webp", "" at the top.
    public var folder: String {
        let parts = path.split(separator: "/").dropLast()
        return parts.joined(separator: "/")
    }

    public var name: String { String(path.split(separator: "/").last ?? Substring(path)) }

    /// Ren'Py's interface pictures (gui/, buttons, frames) are hidden by default; story pictures stay.
    public var isInterface: Bool {
        let lower = path.lowercased()
        return lower.hasPrefix("gui/") || lower.contains("/gui/") || lower.hasPrefix("renpy/") || lower.hasPrefix("_")
            || lower.contains("/ui/") || lower.hasPrefix("ui/") || lower.contains("/icons/") || lower.contains("/buttons/")
    }

    /// The picture's bytes, read from its file or archive. The game's files are only read.
    public func data() throws -> Data {
        if let file { return try Data(contentsOf: URL(fileURLWithPath: file), options: .mappedIfSafe) }
        guard let archive, let parts else { throw CocoaError(.fileReadNoSuchFile) }
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: archive))
        defer { try? handle.close() }
        var data = Data()
        for part in parts {
            if let bytes = part.bytes, let decoded = Data(base64Encoded: bytes) { data.append(decoded) }
            if let offset = part.offset, let length = part.length {
                try handle.seek(toOffset: UInt64(offset))
                data.append(try handle.read(upToCount: length) ?? Data())
            }
        }
        return data
    }

    /// A small picture for the grid, decoded at the size asked (longest side in pixels).
    public func thumbnail(maxPixels: Int) -> CGImage? {
        (try? data()).flatMap { Pictures.thumbnail(of: $0, maxPixels: maxPixels) }
    }
}

