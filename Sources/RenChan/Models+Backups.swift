import Foundation
import RenChanKit

/// Save backups (S-012): back up, list, restore, move to Trash.
extension AppModel {
    func backups(_ id: Game.ID) -> [SaveBackup] {
        memoized("backups-\(id)", key: backupRevision) { SaveBackups.list(Store.backupsFolder(id)) }
    }

    func canBackUp(_ game: Game) -> Bool {
        saveFolder(game).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    func backUpSaves(_ id: Game.ID) {
        guard let game = game(id), let saves = saveFolder(game) else { return }
        do {
            let backup = try SaveBackups.backUp(saves: saves, into: Store.backupsFolder(id))
            backupRevision += 1
            log.post(.info, "Backed up \(backup.contents) of \(game.title)", source: "Saves")
        } catch {
            log.post(.error, "Couldn't back up the saves of \(game.title): \(error.localizedDescription)", source: "Saves")
            notice = String(localized: "RenChan couldn't back up the saves: \(error.localizedDescription)")
        }
    }

    /// Restores after backing up the current saves. Refused while the game plays: Ren'Py would write over it.
    func restore(_ backup: SaveBackup, for id: Game.ID) {
        confirmRestore = nil
        guard let game = game(id), let saves = saveFolder(game), !playing.contains(id) else { return }
        do {
            try SaveBackups.restore(backup, saves: saves, workingSaves: Store.workingCopy(id).appending(path: "game/saves", directoryHint: .isDirectory),
                                    root: Store.backupsFolder(id))
            backupRevision += 1
            log.post(.info, "Restored the saves of \(game.title) from \(backup.id); the replaced saves were backed up", source: "Saves")
        } catch {
            log.post(.error, "Couldn't restore the saves of \(game.title): \(error.localizedDescription)", source: "Saves")
            notice = String(localized: "RenChan couldn't restore the saves: \(error.localizedDescription)")
        }
    }

    func trash(_ backup: SaveBackup) {
        do {
            try SaveBackups.trash(backup)
            backupRevision += 1
        } catch {
            notice = error.localizedDescription
        }
    }
}
