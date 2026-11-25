import Foundation
import PictureKit

/// The cover RenChan keeps for a game (VNDB's or one the person chose), in the game's own folder in RenChan's data:
/// cover.heic, or cover.png or .jpg when HEIC wouldn't be smaller, at most 1200 px. Before 0.9 it was a file named
/// "cover" with no extension, as downloaded.
public enum Covers {
    /// The cover file, whatever its format.
    public static func find(base: URL) -> URL? {
        PictureFile.find(base: base) ?? (FileManager.default.fileExists(atPath: base.path) ? base : nil)
    }

    /// Stores a picture as the cover, in place of any earlier one. Throws when the data isn't a picture, such as an
    /// error page: the earlier cover stays then.
    @discardableResult
    public static func store(_ data: Data, at base: URL) throws -> URL {
        let file = try PictureFile.store(data, at: base, style: .cover, replaced: .delete)
        try? FileManager.default.removeItem(at: base)
        return file
    }

    public static func remove(base: URL) {
        for file in PictureFile.existing(base: base) + [base] { try? FileManager.default.removeItem(at: file) }
    }

    /// Rewrites a cover from before 0.9 in the cover style. Returns the bytes saved, or nil when there was none.
    public static func upgrade(base: URL) -> Int64? {
        guard FileManager.default.fileExists(atPath: base.path), let data = try? Data(contentsOf: base),
              let file = try? store(data, at: base) else { return nil }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? data.count
        return Int64(data.count - size)
    }
}
