import AppKit
import RenChanKit
import SwiftUI

/// Which saves a Saves window shows: the game's own, or the ones made with mods on (S-035).
struct SavesRef: Codable, Hashable {
    var game: Game.ID
    var modded = false
    /// Opens on the persistent data (S-040), for snapshots.
    var persistent: Bool?
}

/// Saves: browse a game's saves and change a save's variables (S-035, S-036).
extension AppModel {
    func savesFolder(_ game: Game, modded: Bool) -> URL? {
        guard let directory = game.saveDirectory else { return nil }
        let root = modded ? Store.moddedSaves(game.id) : Store.saveRoot
        return root.appending(path: directory, directoryHint: .isDirectory)
    }

    func hasModdedSaves(_ game: Game) -> Bool {
        savesFolder(game, modded: true).map { !SaveList.list(in: $0).isEmpty } ?? false
    }

    func showSaves(_ id: Game.ID) { savesToOpen = SavesRef(game: id) }

    func trashSave(_ save: SaveFile) {
        do {
            try FileManager.default.trashItem(at: save.url, resultingItemURL: nil)
            log.post(.info, "Moved the save \(save.slot) to the Trash", source: "Saves")
        } catch {
            notice = String(localized: "RenChan couldn't move the save to the Trash: \(error.localizedDescription)")
        }
    }

    /// Runs RenChan's save tool with the game's own Ren'Py, without a window.
    private func runSaveTool(_ game: Game, modded: Bool, _ arguments: (URL) -> [String]) async throws -> SaveTool.Report {
        guard !playing.contains(game.id) else { throw SaveToolError(String(localized: "Quit \(game.title) first: it would write over the save.")) }
        guard let runtime = installedRuntime(for: game) else {
            throw SaveToolError(String(localized: "Play \(game.title) once first, so RenChan has its Ren'Py \(runtimeVersion(for: game))."))
        }
        let copy = modded ? Store.moddedCopy(game.id) : Store.workingCopy(game.id)
        try WorkingCopy.prepare(base: game.baseURL, copy: copy, allowFullCopy: false)
        var environment = modded ? try prepareMods(game, copy: copy) : [:]
        try SaveTool.install(copy: copy)
        if Store.isOverridden { environment["HOME"] = Store.renpyHome.path }
        let report = Store.gameFolder(game.id).appending(path: "save-tool.json")
        try? FileManager.default.removeItem(at: report)
        let plan = LaunchPlan(runtime: runtime, copy: copy, outputFile: Store.gameFolder(game.id).appending(path: "save-tool.log"),
                              environment: environment, arguments: arguments(report))
        let process = try plan.makeProcess()
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in done.resume() }
            do { try process.run() } catch { process.terminationHandler = nil; done.resume(throwing: error) }
        }
        guard let result = try? SaveTool.readReport(report) else {
            let tail = LaunchResult.read(copy: copy, outputFile: plan.outputFile, exitCode: process.terminationStatus, started: .distantPast).outputTail
            log.post(.error, "The save tool failed for \(game.title): \(tail.suffix(400))", source: "Saves")
            throw SaveToolError(String(localized: "Ren'Py couldn't read this save. The Log has what it said."))
        }
        if let error = result.error { throw SaveToolError(error) }
        return result
    }

    func readVariables(_ save: SaveFile, of game: Game, modded: Bool) async throws -> [SaveVariable] {
        try await runSaveTool(game, modded: modded) { SaveTool.dumpArguments(slot: save.slot, output: $0) }.variables ?? []
    }

    /// Backs up the saves, then writes the changes. Returns what Ren'Py changed.
    func writeVariables(_ changes: [String: Any], in save: SaveFile, of game: Game, modded: Bool) async throws -> [String] {
        if let folder = savesFolder(game, modded: modded) {
            _ = try SaveBackups.backUp(saves: folder, into: Store.backupsFolder(game.id), reason: .beforeEdit)
            backupRevision += 1
        }
        let changesFile = Store.gameFolder(game.id).appending(path: "save-changes.json")
        try SaveTool.writeChanges(changes, to: changesFile)
        let report = try await runSaveTool(game, modded: modded) { SaveTool.setArguments(slot: save.slot, changes: changesFile, output: $0) }
        log.post(.info, "Changed \(report.changed?.joined(separator: ", ") ?? "nothing") in \(game.title)'s save \(save.slot)", source: "Saves")
        return report.changed ?? []
    }
}

/// Persistent data (S-040): the values every save shares, such as unlocked galleries and endings seen.
extension AppModel {
    func readPersistent(of game: Game, modded: Bool) async throws -> (variables: [SaveVariable], images: Int) {
        let report = try await runSaveTool(game, modded: modded) { SaveTool.persistentDumpArguments(output: $0) }
        return (report.variables ?? [], report.images ?? 0)
    }

    func writePersistent(_ changes: [String: Any], of game: Game, modded: Bool) async throws -> [String] {
        backUpBeforeEditing(game, modded: modded)
        let changesFile = Store.gameFolder(game.id).appending(path: "save-changes.json")
        try SaveTool.writeChanges(changes, to: changesFile)
        let report = try await runSaveTool(game, modded: modded) { SaveTool.persistentSetArguments(changes: changesFile, output: $0) }
        log.post(.info, "Changed \(report.changed?.joined(separator: ", ") ?? "nothing") in \(game.title)'s persistent data", source: "Saves")
        return report.changed ?? []
    }

    /// Marks every image the game defines as seen, which unlocks them in Ren'Py's gallery. Returns how many were new.
    func unlockImages(of game: Game, modded: Bool) async throws -> Int {
        backUpBeforeEditing(game, modded: modded)
        let report = try await runSaveTool(game, modded: modded) { SaveTool.unlockImagesArguments(output: $0) }
        log.post(.info, "Marked \(report.unlocked ?? 0) images of \(game.title) as seen", source: "Saves")
        return report.unlocked ?? 0
    }

    private func backUpBeforeEditing(_ game: Game, modded: Bool) {
        guard let folder = savesFolder(game, modded: modded), FileManager.default.fileExists(atPath: folder.path) else { return }
        _ = try? SaveBackups.backUp(saves: folder, into: Store.backupsFolder(game.id), reason: .beforeEdit)
        backupRevision += 1
    }
}

struct SaveToolError: LocalizedError {
    var message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct SavesWindow: View {
    @Environment(AppModel.self) private var model
    let ref: SavesRef
    @State private var modded = false
    @State private var saves: [SaveFile] = []
    /// A save's path, or persistentTag for the persistent data.
    @State private var selection: String?
    static let persistentTag = "persistent"
    @State private var confirmTrash: SaveFile?

    var body: some View {
        if let game = model.game(ref.game) {
            NavigationSplitView {
                List(selection: $selection) {
                    if game.saveDirectory != nil {
                        Section {
                            PersistentRow().tag(Self.persistentTag)
                        }
                    }
                    Section("Saves") {
                        if saves.isEmpty && game.saveDirectory != nil {
                            Text("Saves made in the game show up here.").foregroundStyle(.secondary)
                        }
                        ForEach(saves) { save in
                            SaveRow(save: save)
                                .tag(save.id)
                                .contextMenu {
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([save.url]) }
                                    Button("Move to Trash…") { confirmTrash = save }
                                }
                        }
                    }
                }
                .overlay {
                    if game.saveDirectory == nil {
                        ContentUnavailableView("No Saves", systemImage: "tray",
                                               description: Text("Play the game once so RenChan learns where it saves."))
                    }
                }
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
            } detail: {
                if let save = saves.first(where: { $0.id == selection }) {
                    SaveDetail(game: game, save: save, modded: modded) { reload(game) }
                        .id(save.id)
                } else if selection == Self.persistentTag {
                    SaveDetail(game: game, save: nil, modded: modded) { reload(game) }
                        .id("\(Self.persistentTag)-\(modded)")
                } else {
                    ContentUnavailableView("Choose a Save", systemImage: "square.stack")
                }
            }
            .navigationTitle(String(localized: "Saves of \(game.title)"))
            .toolbar {
                if model.hasModdedSaves(game) || modded {
                    Picker("Saves", selection: $modded) {
                        Text("Saves").tag(false)
                        Text("Modded Saves").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .help("The game's own saves, or the ones made with mods on")
                }
                Button("Reload", systemImage: "arrow.clockwise") { reload(game) }
                    .help("Read the saves folder again")
            }
            .onAppear {
                modded = ref.modded
                if ref.persistent == true { selection = Self.persistentTag }
                reload(game)
            }
            .onChange(of: modded) { reload(game) }
            .confirmationDialog(String(localized: "Move \(confirmTrash?.place ?? "") to the Trash?"), isPresented: Binding(get: { confirmTrash != nil }, set: { if !$0 { confirmTrash = nil } })) {
                Button("Move to Trash", role: .destructive) {
                    if let save = confirmTrash { model.trashSave(save); reload(game) }
                }
            } message: {
                Text("You can put it back from the Trash.")
            }
        } else {
            ContentUnavailableView("This game is no longer in the library", systemImage: "questionmark.square.dashed")
        }
    }

    private func reload(_ game: Game) {
        saves = model.savesFolder(game, modded: modded).map(SaveList.list) ?? []
        if selection == Self.persistentTag && game.saveDirectory != nil { return }
        if selection == nil || !saves.contains(where: { $0.id == selection }) { selection = saves.first?.id }
    }
}

/// The first row: the persistent data every save shares (S-040).
private struct PersistentRow: View {
    var body: some View {
        HStack(spacing: Space.md) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.title3)
                .foregroundStyle(Palette.accent)
                .frame(width: 64, height: 36)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Persistent Data").lineLimit(1)
                Text("Gallery, endings and more, shared by every save").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SaveRow: View {
    let save: SaveFile
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: Space.md) {
            Group {
                if let thumbnail { Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill) } else { Color.secondary.opacity(0.15) }
            }
            .frame(width: 64, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(save.name.isEmpty ? save.place : save.name).lineLimit(1)
                Text(save.name.isEmpty ? save.date.formatted(date: .abbreviated, time: .shortened)
                                       : "\(save.place) · \(save.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .task(id: save.id) {
            let url = save.url
            let data = await Task.detached(priority: .utility) { SaveList.read(url)?.screenshot() }.value
            thumbnail = data.flatMap(NSImage.init(data:))
        }
    }
}
