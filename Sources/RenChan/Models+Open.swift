import AppKit
import RenChanKit
import SwiftUI

/// Files opened before the model exists, when RenChan is started by opening one.
@MainActor
enum OpenQueue {
    static var pending: [URL] = []
}

/// Mods or walkthroughs opened from the Finder, waiting for the person to pick their game (S-037).
struct ModTarget: Identifiable, Equatable {
    let id = UUID()
    var files: [URL]
    var game: Game.ID?
}

/// S-037: files opened from the Finder (Open With › RenChan, a double-click on a .rpa) or dropped on the Dock icon.
extension AppModel {
    /// Games are added as if dropped on the window; mods and walkthroughs ask which game they are for.
    func open(_ urls: [URL]) {
        sidebar = .library
        var found: [URL] = []
        var extras: [URL] = []
        for url in urls {
            if OpenedFile.kind(url) == .game { found.append(url) } else { extras.append(url) }
        }
        if !found.isEmpty { add(found) }
        guard !extras.isEmpty else { return }
        guard !games.isEmpty else {
            notice = String(localized: "Add the game first, then open \(extras[0].lastPathComponent) again to add it to that game.")
            return
        }
        addModsTo = ModTarget(files: extras, game: selection ?? shownGames.first?.id)
        log.post(.info, "Opened \(extras.map(\.lastPathComponent).joined(separator: ", ")); asking which game it's for", source: "Mods")
    }

    func addOpenedMods() async {
        guard let target = addModsTo, let id = target.game else { return }
        addModsTo = nil
        for url in target.files { await addMod(url, to: id) }
        selection = id
    }
}

/// "Add “0x52_URM.rpa” to Which Game?": a game picker, the selected game first.
struct AddModSheet: View {
    @Environment(AppModel.self) private var model
    let target: ModTarget

    private var games: [Game] { model.games.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending } }

    private var title: String {
        target.files.count == 1 ? String(localized: "Add “\(target.files[0].lastPathComponent)” to Which Game?")
                                : String(localized: "Add \(target.files.count) Files to Which Game?")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(title).font(.title3.weight(.semibold))
            Text("RenChan keeps its own copy and turns it on for that game. The game’s own files are never changed.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Game", selection: Binding(get: { model.addModsTo?.game }, set: { model.addModsTo?.game = $0 })) {
                ForEach(games) { game in Text(verbatim: game.title).tag(Game.ID?.some(game.id)) }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.addModsTo = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { Task { await model.addOpenedMods() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.addModsTo?.game == nil)
            }
        }
        .padding(Space.xl)
        .frame(width: 440)
        .noInitialFocus()
    }
}
