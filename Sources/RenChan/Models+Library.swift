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
                let request = ZipRequest(url: url, size: ZipImport.size(of: url))
                // Several zips: each is asked about in turn.
                if confirmZip == nil { confirmZip = request } else if confirmZip != request, !zipQueue.contains(request) { zipQueue.append(request) }
            } else {
                addFolder(url)
            }
        }
    }

    /// What adding a game reads from disk, done in one go so it can run off the main thread.
    struct InspectedGame: Sendable {
        var url: URL, source: URL, base: URL, kind: SourceKind, title: String
        var detected: VersionDetector.Result, saveDirectory: String?, gameVersion: String?
    }

    nonisolated static func inspect(_ url: URL, source: URL? = nil) throws(LocateError) -> InspectedGame {
        let found = try GameLocator.locate(url)
        let source = source ?? url
        return InspectedGame(url: url, source: source, base: found.base, kind: found.kind,
                             title: GameLocator.title(base: found.base, source: source), detected: VersionDetector.detect(base: found.base),
                             saveDirectory: GameLocator.saveDirectory(base: found.base), gameVersion: GameVersion.detect(base: found.base, source: source))
    }

    /// Adds one game, reading it on this thread: for a drop or a test. Many games go through `addInspected`.
    @discardableResult
    func addFolder(_ url: URL, kind: SourceKind? = nil, id: UUID = UUID(), source: URL? = nil) -> Game? {
        do {
            return addInspected(try Self.inspect(url, source: source), kind: kind, id: id)
        } catch {
            notice = error.message
            log.post(.warning, "Refused \(url.path): \(error)", source: "Library")
            return nil
        }
    }

    @discardableResult
    func addInspected(_ found: InspectedGame, kind: SourceKind? = nil, id: UUID = UUID()) -> Game {
        let source = found.source, detected = found.detected
        if let existing = games.first(where: { $0.sourcePath == source.path || $0.basePath == found.base.path }) {
            selection = existing.id
            return existing
        }
        var game = Game(id: id, title: found.title, sourcePath: source.path,
                        kind: kind ?? found.kind, basePath: found.base.path, version: detected.version,
                        pythonLine: detected.pythonLine, versionSource: detected.source,
                        saveDirectory: found.saveDirectory)
        game.gameVersion = found.gameVersion
        games.append(game)
        saveLibrary()
        selection = game.id
        linkIfCameFromDiscover(game.id)
        let version = detected.version.map { "Ren'Py \($0)" } ?? "an unknown Ren'Py"
        log.post(.info, "Added \(game.title) (\(version), \(detected.pythonLine?.rawValue ?? "unknown Python"), from \(detected.source?.rawValue ?? "nothing"))", source: "Library")
        return game
    }

    /// Unpacks a zip into the game's own folder in RenChan's data, then adds it. The zip is left as it is.
    /// The zip question was answered (Unpack or Cancel): the next dropped zip, if any, is asked about.
    func zipAnswered() {
        confirmZip = nil
        guard !zipQueue.isEmpty else { return }
        let next = zipQueue.removeFirst()
        // A new question once the last one has gone away.
        Task { confirmZip = next }
    }

    /// Unpacks a zip; `request` is what the question showed, so its size is still known after the question closes.
    @discardableResult
    func addZip(_ zip: URL, request: ZipRequest? = nil) async -> Game? {
        let request = request ?? ZipRequest(url: zip, size: ZipImport.size(of: zip))
        if let existing = games.first(where: { $0.sourcePath == zip.path }) {
            selection = existing.id
            return existing
        }
        let id = UUID()
        let target = Store.gameFolder(id).appending(path: "source", directoryHint: .isDirectory)
        unpacking = request
        defer { unpacking = nil }
        do {
            try await ZipImport.unpack(zip, into: target)
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

    /// Deletes RenChan's working copies (and the unpacked zip). The game that was added and its saves stay;
    /// what only RenChan's folder holds (saves made with mods on, walkthroughs, mod state) goes to the Trash.
    func remove(_ id: Game.ID) {
        confirmRemove = nil
        guard let game = game(id) else { return }
        if playing.contains(id) || copying[id] != nil { stop(id) }
        let folder = Store.gameFolder(id)
        do {
            if let kept = try RemovedGame.keepAside([Store.moddedSaves(id), Store.walkthroughsFolder(id), Store.modState(id),
                                                     ModAPI.stateFolder(Store.moddedCopy(id))],
                                                    title: game.title, in: folder) {
                try Store.trash(kept)
                log.post(.info, "Moved the modded saves, walkthroughs and mod state of \(game.title) to the Trash", source: "Library")
            }
        } catch {
            // Nothing is deleted when the person's files couldn't be put somewhere safe.
            log.post(.error, "Couldn't move the modded saves of \(game.title) to the Trash: \(error.localizedDescription)", source: "Library")
            notice = String(localized: "RenChan couldn't move the modded saves of \(game.title) to the Trash, so it kept the game: \(error.localizedDescription)")
            return
        }
        try? FileManager.default.removeItem(at: folder)
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

    /// Read again when a backup or restore happens, or the game starts or stops.
    func saveCount(_ game: Game) -> Int? {
        var key = Hasher()
        key.combine(backupRevision); key.combine(playing.contains(game.id)); key.combine(game.saveDirectory); key.combine(game.lastPlayed)
        return memoized("saves-\(game.id)", key: key.finalize()) {
            guard let folder = saveFolder(game), FileManager.default.fileExists(atPath: folder.path) else { return nil }
            return SaveFolder.count(folder)
        }
    }

    func openSaves(_ id: Game.ID) {
        guard let game = game(id), let folder = saveFolder(game) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
