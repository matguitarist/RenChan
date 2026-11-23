import AppKit
import Foundation
import RenChanKit
import UniformTypeIdentifiers

/// The Find on VNDB sheet's state (S-010).
struct VNDBSearch: Identifiable, Equatable {
    var id: Game.ID { game }
    var game: Game.ID
    var query: String
    var results: [VNDBInfo] = []
    var selection: VNDBInfo.ID?
    var searching = false
    /// Set after a search, so "no results" shows only once one ran.
    var searched = false
    var error: String?
}

/// Details and covers from VNDB, and covers the person chooses (S-010).
extension AppModel {
    func findOnVNDB(_ id: Game.ID) {
        guard let game = game(id) else { return }
        vndbSearch = VNDBSearch(game: id, query: game.vndb?.title ?? game.title)
        runVNDBSearch()
    }

    func runVNDBSearch() {
        guard let query = vndbSearch?.query.trimmingCharacters(in: .whitespaces), !query.isEmpty else { return }
        vndbSearch?.searching = true
        vndbSearch?.error = nil
        Task {
            do {
                let found = try await VNDB.search(query)
                guard vndbSearch?.query.trimmingCharacters(in: .whitespaces) == query else { return }
                vndbSearch?.results = found
                vndbSearch?.selection = found.first?.id
            } catch {
                log.post(.warning, "VNDB search for “\(query)” failed: \(error.localizedDescription)", source: "VNDB")
                vndbSearch?.results = []
                vndbSearch?.error = String(localized: "VNDB can't be reached. Check your connection and try again.")
            }
            vndbSearch?.searching = false
            vndbSearch?.searched = true
        }
    }

    /// "Use This Game": links the game and fetches the cover unless the person chose one.
    func useVNDB(_ info: VNDBInfo) {
        guard let search = vndbSearch else { return }
        vndbSearch = nil
        link(search.game, to: info)
    }

    func refreshFromVNDB(_ id: Game.ID) {
        guard let vndbID = game(id)?.vndb?.id else { return }
        Task {
            do {
                guard let info = try await VNDB.details(vndbID) else { return }
                link(id, to: info)
            } catch {
                log.post(.warning, "Couldn't refresh from VNDB: \(error.localizedDescription)", source: "VNDB")
                notice = String(localized: "VNDB can't be reached. Check your connection and try again.")
            }
        }
    }

    func link(_ id: Game.ID, to info: VNDBInfo) {
        var wantsCover = false
        update(id) { wantsCover = VNDB.apply(info, to: &$0) }
        log.post(.info, "Linked \(game(id)?.title ?? "") to VNDB \(info.id) (\(info.title))", source: "VNDB")
        guard wantsCover, let url = info.imageURL.flatMap(URL.init(string:)) else { return }
        Task {
            do {
                try await VNDB.downloadCover(url, to: Store.coverFile(id))
                coverChanged(id)
            } catch {
                log.post(.warning, "Couldn't download the cover for \(info.title): \(error.localizedDescription)", source: "VNDB")
            }
        }
    }

    func unlinkVNDB(_ id: Game.ID) {
        let custom = game(id)?.customCover ?? false
        update(id) { $0.vndb = nil }
        if !custom { try? FileManager.default.removeItem(at: Store.coverFile(id)) }
        coverChanged(id)
    }

    func chooseCover(_ id: Game.ID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = String(localized: "Choose a picture for the game's cover.")
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setCover(id, from: url)
    }

    func setCover(_ id: Game.ID, from url: URL) {
        do {
            let file = Store.coverFile(id)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: file)
            try FileManager.default.copyItem(at: url, to: file)
            update(id) { $0.customCover = true }
            coverChanged(id)
        } catch {
            notice = String(localized: "RenChan couldn't use this picture: \(error.localizedDescription)")
        }
    }

    /// Back to the game's own art, or VNDB's cover when it is linked.
    func resetCover(_ id: Game.ID) {
        try? FileManager.default.removeItem(at: Store.coverFile(id))
        update(id) { $0.customCover = false }
        coverChanged(id)
        if let info = game(id)?.vndb { link(id, to: info) }
    }

    private func coverChanged(_ id: Game.ID) {
        CoverCache.shared.forget(id)
        coverRevision += 1
    }
}
