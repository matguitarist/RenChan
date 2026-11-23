import AppKit
import RenChanKit
import SwiftUI

/// One game found on this Mac and not in the library yet (S-030).
struct FoundGame: Identifiable, Equatable {
    var id: URL { url }
    var url: URL
    var title: String
    var version: String?
    /// From F95Checker (S-034): the thread to watch and the game's own version.
    var watch: String? = nil
    var gameVersion: String? = nil
}

struct FindGamesState: Equatable {
    var scanning = true
    var found: [FoundGame] = []
    var chosen: Set<URL> = []
    /// The folders that were looked in, for the sheet's words.
    var places: [String] = []
    /// Set when the list comes from F95Checker (S-034): how many of its games aren't on this Mac.
    var notOnThisMac: Int?
}

/// Find Games on This Mac (S-030).
extension AppModel {
    func findGames(in roots: [URL] = GameScanner.defaultRoots()) {
        findGames = FindGamesState(places: roots.map { $0.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~") })
        let excluded = [Store.dataFolder]
        let known = Set(games.flatMap { [$0.sourcePath, $0.basePath] }.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
        Task {
            let found = await Task.detached(priority: .userInitiated) { () -> [FoundGame] in
                GameScanner.scan(roots, excluding: excluded).compactMap { url -> FoundGame? in
                    guard let located = try? GameLocator.locate(url) else { return nil }
                    let paths = [url, located.base].map { $0.resolvingSymlinksInPath().path }
                    guard !paths.contains(where: known.contains) else { return nil }
                    return FoundGame(url: url, title: GameLocator.title(base: located.base, source: url),
                                     version: VersionDetector.detect(base: located.base).version?.description)
                }
            }.value
            guard findGames != nil else { return }
            findGames?.found = found
            findGames?.chosen = Set(found.map(\.url))
            findGames?.scanning = false
            log.post(.info, "Found \(found.count) Ren'Py games not in the library", source: "Library")
        }
    }

    func findGamesInFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = String(localized: "Choose a folder to look for Ren'Py games in.")
        panel.prompt = String(localized: "Look Here")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        findGames(in: [url])
    }

    func addFoundGames() {
        guard let state = findGames else { return }
        findGames = nil
        for found in state.found where state.chosen.contains(found.url) {
            guard let game = addFolder(found.url) else { continue }
            if found.watch != nil || found.gameVersion != nil {
                update(game.id) {
                    if let page = found.watch, $0.watch == nil { $0.watch = UpdateWatch(page: page) }
                    if $0.gameVersion == nil { $0.gameVersion = found.gameVersion }
                }
            }
        }
        if state.notOnThisMac != nil { checkForNewVersions() }
    }

    /// File › Import from F95Checker… (S-034): its games that are on this Mac, each watching its thread.
    func importF95Checker(database: URL? = nil) {
        var file = database ?? F95Checker.defaultDatabases().first
        if file == nil {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.message = String(localized: "Choose F95Checker's db.sqlite3. RenChan only reads it.")
            panel.prompt = String(localized: "Import")
            guard panel.runModal() == .OK else { return }
            file = panel.url
        }
        guard let file else { return }
        let entries: [F95Checker.Entry]
        do {
            entries = try F95Checker.read(file)
        } catch {
            notice = String(localized: "RenChan couldn't read F95Checker's library at \(file.path). Choose the db.sqlite3 in F95Checker's folder.")
            log.post(.warning, "Couldn't read \(file.path): \(error)", source: "Library")
            return
        }
        let known = Set(games.flatMap { [$0.sourcePath, $0.basePath] }.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
        var found: [FoundGame] = []
        var missing = 0
        var linked = 0
        for entry in entries {
            let located = entry.executables.lazy.map(F95Checker.gameLocation).compactMap { url in (try? GameLocator.locate(url)).map { (url, $0.base) } }.first
            guard let (url, base) = located else { missing += 1; continue }
            let paths = [url, base].map { $0.resolvingSymlinksInPath().path }
            if let existing = games.first(where: { paths.contains(URL(fileURLWithPath: $0.sourcePath).resolvingSymlinksInPath().path) || paths.contains(URL(fileURLWithPath: $0.basePath).resolvingSymlinksInPath().path) }) {
                // Already in the library: it starts watching its thread, nothing else changes.
                if existing.watch == nil { update(existing.id) { $0.watch = UpdateWatch(page: entry.thread.absoluteString) }; linked += 1 }
                continue
            }
            guard !paths.contains(where: known.contains), !found.contains(where: { $0.url == url }) else { continue }
            found.append(FoundGame(url: url, title: entry.name, version: VersionDetector.detect(base: base).version?.description,
                                   watch: entry.thread.absoluteString, gameVersion: GameVersion.detect(base: base, source: url) ?? entry.version))
        }
        log.post(.info, "F95Checker: \(entries.count) games, \(found.count) to add, \(linked) already here now watch their thread, \(missing) not on this Mac", source: "Library")
        findGames = FindGamesState(scanning: false, found: found, chosen: Set(found.map(\.url)), places: [], notOnThisMac: missing)
    }
}

struct FindGamesSheet: View {
    @Environment(AppModel.self) private var model
    let initial: FindGamesState
    private var state: FindGamesState { model.findGames ?? initial }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                if let missing = state.notOnThisMac {
                    Text("Import from F95Checker").font(.title3.weight(.semibold))
                    Text(missing == 0 ? String(localized: "F95Checker's games that are on this Mac. Each one watches its F95zone thread for new versions.")
                                      : String(localized: "F95Checker's games that are on this Mac. Each one watches its F95zone thread for new versions. \(missing) aren't on this Mac and aren't listed."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Find Games on This Mac").font(.title3.weight(.semibold))
                    Text("Looked in \(state.places.formatted(.list(type: .and))). Games already in your library aren't listed.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Group {
                if state.scanning {
                    VStack(spacing: Space.sm) {
                        ProgressView()
                        Text("Looking for Ren'Py games…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if state.found.isEmpty {
                    ContentUnavailableView("No New Games Found", systemImage: "magnifyingglass",
                                           description: Text("Drop a game on the window, or look in another folder."))
                } else {
                    List(state.found) { game in
                        Toggle(isOn: Binding(get: { state.chosen.contains(game.url) },
                                             set: { on in if on { model.findGames?.chosen.insert(game.url) } else { model.findGames?.chosen.remove(game.url) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: game.title).font(.headline)
                                Text(verbatim: [game.version.map { "Ren'Py \($0)" }, game.url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.vertical, 2)
                    }
                    .listStyle(.bordered)
                    .alternatingRowBackgrounds()
                }
            }
            .frame(height: 280)
            HStack(spacing: Space.sm) {
                if state.notOnThisMac == nil {
                    Button("Look in Another Folder…") { model.findGamesInFolder() }
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.findGames = nil }
                    .keyboardShortcut(.cancelAction)
                Button(state.chosen.count == 1 ? String(localized: "Add 1 Game") : String(localized: "Add \(state.chosen.count) Games")) { model.addFoundGames() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.scanning || state.chosen.isEmpty)
            }
        }
        .padding(Space.xl)
        .frame(width: 600)
        .noInitialFocus()
    }
}
