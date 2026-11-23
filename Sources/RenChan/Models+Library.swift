import AppKit
import Foundation
import RenChanKit
import UniformTypeIdentifiers

/// Adding and removing games (S-001, S-002, S-007, S-008).
extension AppModel {
    /// Drop or File › Add Game…: folders and .app bundles are added at once, a zip asks first.
    func add(_ urls: [URL]) {
        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                do {
                    try ZipImport.check(url)
                } catch {
                    notice = error.message
                    log.post(.warning, "Refused \(url.path): not a zip (\(error))", source: "Library")
                    continue
                }
                confirmZip = ZipRequest(url: url, size: ZipImport.size(of: url))
            } else {
                addFolder(url)
            }
        }
    }

    @discardableResult
    func addFolder(_ url: URL, kind: SourceKind? = nil, id: UUID = UUID(), source: URL? = nil) -> Game? {
        let found: (base: URL, kind: SourceKind)
        do {
            found = try GameLocator.locate(url)
        } catch {
            notice = error.message
            log.post(.warning, "Refused \(url.path): \(error)", source: "Library")
            return nil
        }
        let source = source ?? url
        if let existing = games.first(where: { $0.sourcePath == source.path || $0.basePath == found.base.path }) {
            selection = existing.id
            return existing
        }
        let detected = VersionDetector.detect(base: found.base)
        let game = Game(id: id, title: GameLocator.title(base: found.base, source: source), sourcePath: source.path,
                        kind: kind ?? found.kind, basePath: found.base.path, version: detected.version,
                        pythonLine: detected.pythonLine, versionSource: detected.source,
                        saveDirectory: GameLocator.saveDirectory(base: found.base))
        games.append(game)
        saveLibrary()
        selection = game.id
        linkIfCameFromDiscover(game.id)
        let version = detected.version.map { "Ren'Py \($0)" } ?? "an unknown Ren'Py"
        log.post(.info, "Added \(game.title) (\(version), \(detected.pythonLine?.rawValue ?? "unknown Python"), from \(detected.source?.rawValue ?? "nothing"))", source: "Library")
        return game
    }

    /// Unpacks a zip into the game's own folder in RenChan's data, then adds it. The zip is left as it is.
    @discardableResult
    func addZip(_ zip: URL) -> Game? {
        confirmZip = nil
        if let existing = games.first(where: { $0.sourcePath == zip.path }) {
            selection = existing.id
            return existing
        }
        let id = UUID()
        let target = Store.gameFolder(id).appending(path: "source", directoryHint: .isDirectory)
        do {
            try ZipImport.unpack(zip, into: target)
        } catch {
            notice = error.message
            log.post(.warning, "Refused \(zip.path): \(error)", source: "Library")
            return nil
        }
        guard let game = addFolder(target, kind: .zip, id: id, source: zip) else {
            try? FileManager.default.removeItem(at: Store.gameFolder(id))
            return nil
        }
        return game
    }

    func addWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.folder, .applicationBundle, .zip]
        panel.message = String(localized: "Choose a game folder, a Mac .app, or a zip.")
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    /// Deletes RenChan's working copy (and the unpacked zip). The game that was added and its saves stay.
    func remove(_ id: Game.ID) {
        confirmRemove = nil
        guard let game = game(id) else { return }
        if playing.contains(id) { stop(id) }
        try? FileManager.default.removeItem(at: Store.gameFolder(id))
        games.removeAll { $0.id == id }
        if selection == id { selection = shownGames.first?.id }
        saveLibrary()
        log.post(.info, "Removed \(game.title) from the library; kept \(game.sourcePath) and its saves", source: "Library")
    }

    func showInFinder(_ id: Game.ID) {
        guard let game = game(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([game.sourceURL])
    }

    // MARK: Saves (S-007)

    func saveFolder(_ game: Game) -> URL? {
        game.saveDirectory.map { Store.saveRoot.appending(path: $0, directoryHint: .isDirectory) }
    }

    func saveCount(_ game: Game) -> Int? {
        guard let folder = saveFolder(game), FileManager.default.fileExists(atPath: folder.path) else { return nil }
        return SaveFolder.count(folder)
    }

    func openSaves(_ id: Game.ID) {
        guard let game = game(id), let folder = saveFolder(game) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
