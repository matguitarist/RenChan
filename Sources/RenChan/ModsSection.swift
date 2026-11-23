import RenChanKit
import SwiftUI
import UniformTypeIdentifiers

/// The inspector's Mods section (S-017 to S-021).
struct ModsSection: View {
    @Environment(AppModel.self) private var model
    let game: Game
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        Section("Mods") {
            if game.mods.isEmpty {
                Text("Drop a mod's zip, folder or .rpy file here, such as a walkthrough. Mods go in RenChan's copy, never in the game.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(game.mods) { use in
                if let mod = model.mod(use.mod) {
                    row(mod, use)
                }
            }
            .onMove { model.moveMods(in: game.id, from: $0, to: $1) }
            ForEach(model.modConflicts(game), id: \.self) { conflict in
                Label(conflict.message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if game.hasModsOn {
                Text(game.backedUpBeforeMods ? "Modded play keeps its own saves; yours were backed up before the first modded launch."
                                             : "Modded play keeps its own saves; yours are backed up before the first modded launch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Add Mod…") { model.addModWithPanel(to: game.id) }
                    .help("Add a mod or walkthrough to this game: a zip, a folder, or .rpy, .rpyc or .rpa files")
                Button("New Mod…") { newName = ""; naming = true }
                    .help("Make your own mod for this game from RenChan's template and open it in your editor")
                let others = model.otherMods(game)
                if !others.isEmpty {
                    Menu("Add from Library") {
                        ForEach(others) { mod in Button(mod.name) { model.attachMod(mod.id, to: game.id) } }
                    }
                    .fixedSize()
                    .help("Add a mod you already added to another game, such as Universal Ren'Py Mod")
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls { model.addMod(url, to: game.id) }
            return !urls.isEmpty
        }
        .alert("New Mod", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Create") { model.createMod(named: newName, for: game.id) }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RenChan makes a mod with a starter script that uses its mod API, turns it on for this game, and opens it in your editor. Changes go in at each launch.")
        }
    }

    private func details(_ mod: Mod) -> String {
        let count = ModLibrary.currentFiles(mod, root: Store.modsFolder).count
        let files = count == 1 ? String(localized: "1 file") : String(localized: "\(count) files")
        let manifest = ModLibrary.manifest(mod, root: Store.modsFolder)
        return [manifest?.version.map { "v\($0)" }, manifest?.author, files].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func row(_ mod: Mod, _ use: ModUse) -> some View {
        let index = game.mods.firstIndex(of: use) ?? 0
        return Toggle(isOn: Binding(get: { use.enabled }, set: { model.setMod(mod.id, enabled: $0, in: game.id) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: mod.name)
                Text(details(mod)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Move Up") { model.moveMod(mod.id, by: -1, in: game.id) }.disabled(index == 0)
            Button("Move Down") { model.moveMod(mod.id, by: 1, in: game.id) }.disabled(index == game.mods.count - 1)
            Button("Show in Finder") { model.showModInFinder(mod.id) }
            Divider()
            Button("Remove from This Game") { model.removeMod(mod.id, from: game.id) }
        }
    }
}
