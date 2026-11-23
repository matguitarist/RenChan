import Foundation

/// A walkthrough the person keeps with a game (S-032): a PDF, like the ones Eternum's developer posts on itch.io,
/// or a text file. RenChan keeps its own copy and remembers the page.
public struct Walkthrough: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: Sendable { case pdf, text }

    public var id: UUID
    public var name: String
    /// The file name in the game's Walkthroughs folder.
    public var file: String
    /// The page last read, from 0 (PDF only).
    public var page: Int = 0
    public var added: Date

    public var kind: Kind { (file as NSString).pathExtension.lowercased() == "pdf" ? .pdf : .text }

    public init(id: UUID = UUID(), name: String, file: String, page: Int = 0, added: Date = .now) {
        self.id = id
        self.name = name
        self.file = file
        self.page = page
        self.added = added
    }
}

public enum WalkthroughError: Error, Equatable {
    /// Not a .pdf, .txt or .md file.
    case notSupported
    /// Named .pdf but isn't one, such as an expired download link's error page.
    case notAPDF
    case failed(String)
}

public enum Walkthroughs {
    public static let extensions: Set<String> = ["pdf", "txt", "md"]

    public static func isWalkthrough(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    /// Copies the file into `folder` under a new name.
    public static func add(_ url: URL, into folder: URL) throws(WalkthroughError) -> Walkthrough {
        let ext = url.pathExtension.lowercased()
        guard extensions.contains(ext) else { throw .notSupported }
        if ext == "pdf" {
            let head = (try? FileHandle(forReadingFrom: url)).flatMap { handle in
                defer { try? handle.close() }
                return try? handle.read(upToCount: 1024)
            } ?? Data()
            guard head.range(of: Data("%PDF".utf8)) != nil else { throw .notAPDF }
        }
        let walkthrough = Walkthrough(name: ModLibrary.displayName(url), file: "\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: folder.appending(path: walkthrough.file))
        } catch {
            throw .failed(error.localizedDescription)
        }
        return walkthrough
    }
}
