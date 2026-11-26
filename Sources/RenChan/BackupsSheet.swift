import RenChanKit
import SwiftUI

/// Save Backups (S-012): each backup by date, Back Up Now, Restore…, Move to Trash.
struct SaveBackupsSheet: View {
    @Environment(AppModel.self) private var model
    let gameID: Game.ID
    @State private var selection: SaveBackup.ID?

    private var game: Game? { model.game(gameID) }
    private var backups: [SaveBackup] { model.backups(gameID) }
    private var selected: SaveBackup? { backups.first { $0.id == selection } }
    private var playing: Bool { model.playing.contains(gameID) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Save Backups").font(.title3.weight(.semibold))
                Text("Copies of \(game?.title ?? "")'s saves, kept by RenChan. A restore backs up the current saves first.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if backups.isEmpty {
                    ContentUnavailableView("No Backups Yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Back up the saves before a big choice, or before trying a mod."))
                } else {
                    Table(backups, selection: $selection) {
                        TableColumn("Date") { backup in Text(backup.date, format: .dateTime.day().month().year().hour().minute()) }
                            .width(min: 150, ideal: 180)
                        TableColumn("Kind") { backup in
                            HStack(spacing: Space.xs) {
                                Text(backup.reason.title)
                                    .foregroundStyle(backup.reason == .manual ? .primary : .secondary)
                                if backup.modded {
                                    // Restored into the modded saves, not the game's own.
                                    Image(systemName: "puzzlepiece.extension")
                                        .foregroundStyle(.secondary)
                                        .help("Saves made with mods on")
                                        .accessibilityLabel("Saves made with mods on")
                                }
                            }
                        }
                        .width(min: 120, ideal: 190)
                        TableColumn("Saves") { backup in
                            if backup.saveCount == 0 {
                                // Only the persistent data (gallery, endings), before the first save.
                                Text(verbatim: "—").foregroundStyle(.secondary).help("Persistent data only: no saves yet")
                            } else {
                                Text(backup.saveCount, format: .number).monospacedDigit()
                            }
                        }
                            .width(min: 50, ideal: 60)
                        TableColumn("Size") { backup in Text(backup.size.bytesText).monospacedDigit() }
                            .width(min: 60, ideal: 80)
                    }
                    .contextMenu(forSelectionType: SaveBackup.ID.self) { ids in
                        if let backup = backups.first(where: { ids.contains($0.id) }) {
                            Button("Restore…") { model.confirmRestore = backup }.disabled(playing)
                            Button("Move to Trash") { model.trash(backup) }
                        }
                    } primaryAction: { ids in
                        if !playing, let backup = backups.first(where: { ids.contains($0.id) }) { model.confirmRestore = backup }
                    }
                }
            }
            .frame(height: 240)
            HStack(spacing: Space.sm) {
                Button("Back Up Now") { model.backUpSaves(gameID) }
                    .disabled(game.map { !model.canBackUp($0) } ?? true)
                Spacer()
                if playing {
                    Text("Quit the game to restore").font(.callout).foregroundStyle(.secondary)
                }
                Button("Move to Trash") { if let selected { model.trash(selected) } }
                    .disabled(selected == nil)
                Button("Restore…") { model.confirmRestore = selected }
                    .disabled(selected == nil || playing)
                Button("Done") { model.showBackups = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 620)
        .noInitialFocus()
        .confirmationDialog(restoreTitle, isPresented: Binding(get: { model.confirmRestore != nil }, set: { if !$0 { model.confirmRestore = nil } })) {
            Button("Restore") { if let backup = model.confirmRestore { model.restore(backup, for: gameID) } }
        } message: {
            Text("RenChan backs up the current saves first, so you can go back.")
        }
    }

    private var restoreTitle: String {
        let date = model.confirmRestore?.date.formatted(.dateTime.day().month().year().hour().minute()) ?? ""
        return String(localized: "Restore the saves from \(date)?")
    }
}

/// The inspector's backup row: Back Up Saves, Backups…, and when the last one was made.
struct BackupRow: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        let last = model.lastManualBackup(game.id)
        LabeledContent("Backups") {
            Text(last.map { $0.formatted(.relative(presentation: .named)) } ?? String(localized: "None yet"))
        }
        HStack(spacing: Space.sm) {
            Button("Back Up Saves") { model.backUpSaves(game.id) }
                .disabled(!model.canBackUp(game))
                .help("Copy the saves into RenChan's backups (Option-Command-B)")
            Button("Backups…") { model.showBackups = game.id }
                .help("See, restore or remove backups of the saves")
        }
    }
}

extension SaveBackup {
    /// For the log: "3 saves", "1 save", or "the persistent data" when the game has no saves yet.
    var contents: String {
        switch saveCount {
        case 0: "the persistent data"
        case 1: "1 save"
        default: "\(saveCount) saves"
        }
    }
}

extension SaveBackup.Reason {
    var title: String {
        switch self {
        case .manual: String(localized: "Backup")
        case .beforeRestore: String(localized: "Before restore")
        case .beforeMods: String(localized: "Before mods")
        case .beforeEdit: String(localized: "Before editing a save")
        case .beforePlay: String(localized: "Before playing")
        }
    }
}
