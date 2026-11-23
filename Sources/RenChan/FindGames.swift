import AppKit
import RenChanKit
import SwiftUI

/// One game found on this Mac and not in the library yet (S-030).
struct FoundGame: Identifiable, Equatable {
    var id: URL { url }
    var url: URL
    var title: String
    var version: String?
}

struct FindGamesState: Equatable {
    var scanning = true
    var found: [FoundGame] = []
    var chosen: Set<URL> = []
    /// The folders that were looked in, for the sheet's words.
    var places: [String] = []
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
        for game in state.found where state.chosen.contains(game.url) { addFolder(game.url) }
    }
}

struct FindGamesSheet: View {
    @Environment(AppModel.self) private var model
    let initial: FindGamesState
    private var state: FindGamesState { model.findGames ?? initial }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Find Games on This Mac").font(.title3.weight(.semibold))
                Text("Looked in \(state.places.formatted(.list(type: .and))). Games already in your library aren't listed.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                Button("Look in Another Folder…") { model.findGamesInFolder() }
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
