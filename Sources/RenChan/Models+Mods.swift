import AppKit
import RenChanKit

/// Mods (S-017 to S-021): the library, each game's list, and the modded copy at launch.
extension AppModel {
    func mod(_ id: UUID) -> Mod? { mods.first { $0.id == id } }

    /// The game's mods that are on, in load order.
    func enabledMods(_ game: Game) -> [Mod] { game.mods.filter(\.enabled).compactMap { mod($0.mod) } }

    func modConflicts(_ game: Game) -> [ModConflict] {
        var key = Hasher()
        key.combine(modsRevision); key.combine(game.mods); key.combine(playing.contains(game.id))
        return memoized("conflicts-\(game.id)", key: key.finalize()) { ModConflicts.find(enabledMods(game), root: Store.modsFolder) }
    }

    /// "v1.2 · Ana · 3 files", read from the mod's folder.
    func modDetails(_ mod: Mod) -> String {
        var key = Hasher()
        key.combine(modsRevision); key.combine(playing.count)
        return memoized("mod-\(mod.id)", key: key.finalize()) {
            let count = ModLibrary.currentFiles(mod, root: Store.modsFolder).count
            let files = count == 1 ? String(localized: "1 file") : String(localized: "\(count) files")
            let manifest = ModLibrary.manifest(mod, root: Store.modsFolder)
            return [manifest?.version.map { "v\($0)" }, manifest?.author, files].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// Library mods this game doesn't use yet, to add with one click (S-021).
    func otherMods(_ game: Game) -> [Mod] {
        mods.filter { mod in !game.mods.contains { $0.mod == mod.id } }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func addModWithPanel(to id: Game.ID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Choose a mod: a zip, a folder, or .rpy, .rpyc or .rpa files. RenChan keeps its own copy.")
        panel.prompt = String(localized: "Add Mod")
        guard panel.runModal() == .OK else { return }
        Task { for url in panel.urls { await addMod(url, to: id) } }
    }

    /// Copies a mod into the library and turns it on for the game, last in the load order.
    func addMod(_ url: URL, to id: Game.ID) async {
        guard let game = game(id) else { return }
        // A walkthrough PDF dropped on Mods is a walkthrough, not a mod.
        if Walkthroughs.isWalkthrough(url) {
            addWalkthrough(url, to: id)
            return
        }
        do {
            let mod = try await ModLibrary.importMod(url, into: Store.modsFolder)
            mods.append(mod)
            modsRevision += 1
            try ModLibrary.save(mods, to: Store.modsFolder)
            update(id) { $0.mods.append(ModUse(mod: mod.id)) }
            log.post(.info, "Added the mod \(mod.name) (\(mod.files.count) files) to \(game.title)", source: "Mods")
        } catch let error as ModError {
            notice = error.message(url.lastPathComponent)
        } catch {
            notice = String(localized: "RenChan couldn't add \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// S-024: a new mod from the template, on for this game, opened in the person's editor.
    func createMod(named name: String, for id: Game.ID) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let game = game(id) else { return }
        do {
            let mod = try ModTemplate.create(trimmed, author: NSFullUserName(), into: Store.modsFolder)
            mods.append(mod)
            modsRevision += 1
            try ModLibrary.save(mods, to: Store.modsFolder)
            update(id) { $0.mods.append(ModUse(mod: mod.id)) }
            log.post(.info, "Made the mod \(mod.name) for \(game.title) from the template", source: "Mods")
            if !Store.isOverridden, let script = mod.files.first {
                NSWorkspace.shared.open(ModLibrary.folder(mod, root: Store.modsFolder).appending(path: script))
            }
        } catch {
            notice = String(localized: "RenChan couldn't make the mod: \(error.localizedDescription)")
        }
    }

    func showModInFinder(_ modID: UUID) {
        guard let mod = mod(modID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([ModLibrary.folder(mod, root: Store.modsFolder)])
    }

    func attachMod(_ modID: UUID, to id: Game.ID) {
        update(id) { game in if !game.mods.contains(where: { $0.mod == modID }) { game.mods.append(ModUse(mod: modID)) } }
    }

    func setMod(_ modID: UUID, enabled: Bool, in id: Game.ID) {
        update(id) { game in
            if let index = game.mods.firstIndex(where: { $0.mod == modID }) { game.mods[index].enabled = enabled }
        }
    }

    func moveMods(in id: Game.ID, from offsets: IndexSet, to destination: Int) {
        update(id) { $0.mods.move(fromOffsets: offsets, toOffset: destination) }
    }

    func moveMod(_ modID: UUID, by step: Int, in id: Game.ID) {
        update(id) { game in
            guard let index = game.mods.firstIndex(where: { $0.mod == modID }) else { return }
            let target = index + step
            guard game.mods.indices.contains(target) else { return }
            game.mods.swapAt(index, target)
        }
    }

    /// Takes the mod off this game. A mod no game uses any more leaves the library too, to the Trash.
    func removeMod(_ modID: UUID, from id: Game.ID) {
        update(id) { $0.mods.removeAll { $0.mod == modID } }
        guard !games.contains(where: { $0.mods.contains { $0.mod == modID } }), let mod = mod(modID) else { return }
        _ = try? Store.trash(ModLibrary.folder(mod, root: Store.modsFolder))
        mods.removeAll { $0.id == modID }
        modsRevision += 1
        try? ModLibrary.save(mods, to: Store.modsFolder)
        log.post(.info, "Moved the mod \(mod.name) to the Trash: no game uses it", source: "Mods")
    }

    /// Before a launch: the modded copy gets exactly the enabled mods, and the saves are backed up once
    /// before the first modded launch. Returns the environment for Ren'Py.
    func prepareMods(_ game: Game, copy: URL) throws -> [String: String] {
        guard game.hasModsOn else { return [:] }
        let enabled = enabledMods(game)
        try ModInstaller.apply(enabled, root: Store.modsFolder, base: game.baseURL, copy: copy)
        // S-023: the renchan module mods call.
        try ModAPI.install(copy: copy, state: Store.modState(game.id))
        if !game.backedUpBeforeMods {
            if let saves = saveFolder(game), FileManager.default.fileExists(atPath: saves.path) {
                _ = try? SaveBackups.backUp(saves: saves, into: Store.backupsFolder(game.id), reason: .beforeMods)
                backupRevision += 1
            }
            update(game.id) { $0.backedUpBeforeMods = true }
        }
        for conflict in modConflicts(game) {
            log.post(.warning, "\(game.title): \(conflict.message)", source: "Mods")
        }
        log.post(.info, "\(game.title): playing with \(enabled.map(\.name).joined(separator: ", ")); saves kept apart", source: "Mods")
        return ModInstaller.environment(modded: true, saves: Store.moddedSaves(game.id))
    }
}

extension ModError {
    func message(_ file: String) -> String {
        switch self {
        case .notAMod: String(localized: "\(file) isn't a mod RenChan can add. Choose a zip, a folder, or .rpy, .rpyc or .rpa files.")
        case .noScripts: String(localized: "\(file) has no Ren'Py files (.rpy, .rpyc or .rpa), so it can't change the game.")
        case .unsafeZip(let entry): String(localized: "\(file) was refused: it would write outside its folder (\(entry)).")
        case .failed(let reason): String(localized: "RenChan couldn't add \(file): \(reason)")
        }
    }
}

extension ModConflict {
    var message: String {
        switch kind {
        case .file(let path):
            String(localized: "\(mods.dropLast().joined(separator: ", ")) and \(mods.last ?? "") both have \(path); \(mods.last ?? "")'s is used.")
        case .screen(let name):
            String(localized: "\(mods.formatted(.list(type: .and))) all change the screen “\(name)”; Ren'Py uses the one it loads last.")
        }
    }
}
