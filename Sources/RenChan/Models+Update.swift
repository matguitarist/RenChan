import AppKit
import Foundation
import RenChanKit

/// A new version picked for a game, waiting for the person to confirm (S-013).
struct UpdateRequest: Identifiable, Equatable {
    var id: Game.ID { game }
    var game: Game.ID
    var url: URL
    var isZip: Bool
    /// The zip's unpacked size.
    var size: Int64?
}

/// Updating a game to a new version: same game, new files (S-013).
extension AppModel {
    func chooseUpdate(_ id: Game.ID) {
        guard let game = game(id) else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.folder, .applicationBundle, .zip]
        panel.directoryURL = game.sourceURL.deletingLastPathComponent()
        panel.message = String(localized: "Choose the new version of \(game.title): a folder, a Mac .app, or a zip.")
        panel.prompt = String(localized: "Update")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prepareUpdate(id, from: url)
    }

    /// Checks the new version, then asks before changing anything.
    func prepareUpdate(_ id: Game.ID, from url: URL) {
        guard let game = game(id) else { return }
        guard !playing.contains(id) else {
            notice = String(localized: "Quit \(game.title) before updating it.")
            return
        }
        if let other = games.first(where: { $0.sourcePath == url.path }) {
            notice = other.id == id ? String(localized: "\(game.title) already plays this version.")
                                    : String(localized: "This version is already in the library as \(other.title).")
            return
        }
        let isZip = url.pathExtension.lowercased() == "zip"
        do {
            if isZip { try ZipImport.check(url) } else { _ = try GameLocator.locate(url) }
        } catch {
            notice = error.message
            log.post(.warning, "Refused \(url.path) as a new version of \(game.title): \(error)", source: "Library")
            return
        }
        confirmUpdate = UpdateRequest(game: id, url: url, isZip: isZip, size: isZip ? ZipImport.size(of: url) : nil)
    }

    /// Points the game at the new version and drops the old working copy; the next Play makes a fresh one.
    @discardableResult
    func applyUpdate(_ request: UpdateRequest) async -> Bool {
        confirmUpdate = nil
        guard let old = game(request.game) else { return false }
        let folder = Store.gameFolder(old.id)
        var unpacked: URL?
        let found: (base: URL, kind: SourceKind)
        do {
            if request.isZip {
                let target = folder.appending(path: "source-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
                unpacking = ZipRequest(url: request.url, size: request.size)
                defer { unpacking = nil }
                try await ZipImport.unpackInBackground(request.url, into: target)
                unpacked = target
                found = (try GameLocator.locate(target).base, .zip)
            } else {
                found = try GameLocator.locate(request.url)
            }
        } catch {
            if let unpacked { try? FileManager.default.removeItem(at: unpacked) }
            notice = error.message
            log.post(.warning, "Couldn't update \(old.title) from \(request.url.path): \(error)", source: "Library")
            return false
        }
        let detected = VersionDetector.detect(base: found.base)
        update(old.id) {
            GameUpdate.apply(to: &$0, title: GameLocator.title(base: found.base, source: request.url), sourcePath: request.url.path,
                             kind: found.kind, basePath: found.base.path, detected: detected,
                             saveDirectory: GameLocator.saveDirectory(base: found.base))
            // S-033: the new version's own number; the badge goes once it's the one on the page.
            $0.gameVersion = GameVersion.detect(base: found.base, source: request.url) ?? $0.gameVersion
        }
        // The working copy is a clone of the old files; an unpacked old zip is RenChan's own and goes too.
        try? FileManager.default.removeItem(at: Store.workingCopy(old.id))
        try? FileManager.default.removeItem(at: Store.moddedCopy(old.id))
        if old.kind == .zip, let oldFolder = Self.topFolder(of: old.basePath, in: folder), oldFolder != unpacked?.lastPathComponent {
            try? FileManager.default.removeItem(at: folder.appending(path: oldFolder, directoryHint: .isDirectory))
        }
        CoverCache.shared.forget(old.id)
        coverRevision += 1
        let version = detected.version.map { "Ren'Py \($0)" } ?? "an unknown Ren'Py"
        log.post(.info, "Updated \(old.title) to \(request.url.lastPathComponent) (\(version)); kept its playtime, labels, notes and backups", source: "Library")
        return true
    }

    /// "source" for …/Games/<id>/source/Game-1.0/: the folder right under the game's own folder.
    /// Links are resolved first: /tmp and /private/tmp are one folder.
    private static func topFolder(of path: String, in folder: URL) -> String? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let root = folder.resolvingSymlinksInPath().path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard resolved.hasPrefix(prefix) else { return nil }
        return resolved.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
    }
}
