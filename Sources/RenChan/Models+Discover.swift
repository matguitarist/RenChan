import AppKit
import Foundation
import RenChanKit

/// The Discover page's search (S-028).
struct DiscoverState: Equatable {
    var query = ""
    var renpyOnly = true
    var results: [VNDBInfo] = []
    var selection: VNDBInfo.ID?
    var searching = false
    var searched = false
    var error: String?
}

/// Discover games on VNDB, open their download pages, and link the game when it's added (S-028, S-029).
extension AppModel {
    func runDiscover() {
        let query = discover.query.trimmingCharacters(in: .whitespaces)
        let renpyOnly = discover.renpyOnly
        discover.searching = true
        discover.error = nil
        Task {
            do {
                let found = try await VNDB.search(query, renpyOnly: renpyOnly)
                guard discover.query.trimmingCharacters(in: .whitespaces) == query, discover.renpyOnly == renpyOnly else { return }
                discover.results = found
                if !found.contains(where: { $0.id == discover.selection }) { discover.selection = found.first?.id }
            } catch {
                log.post(.warning, "VNDB search for “\(query)” failed: \(error.localizedDescription)", source: "VNDB")
                discover.error = String(localized: "VNDB can't be reached. Check your connection and try again.")
            }
            discover.searching = false
            discover.searched = true
        }
    }

    /// Fetches a game's releases once per session.
    func loadReleases(_ vnID: String) {
        guard releases[vnID] == nil, !releasesLoading.contains(vnID) else { return }
        releasesLoading.insert(vnID)
        Task {
            do {
                releases[vnID] = try await VNDB.releases(vnID)
            } catch {
                log.post(.warning, "Couldn't get the releases of \(vnID): \(error.localizedDescription)", source: "VNDB")
            }
            releasesLoading.remove(vnID)
        }
    }

    /// Store and download pages, official releases first, each address once.
    func downloadLinks(_ vnID: String) -> [VNDBRelease.Link] {
        var seen = Set<URL>()
        return (releases[vnID] ?? []).filter(\.official).flatMap(\.links).filter { seen.insert($0.url).inserted }
    }

    /// Opens a download page and remembers where the person came from, so the game they add next gets linked.
    func openDownloadPage(_ url: URL, for info: VNDBInfo) {
        cameFromDiscover = (info, .now)
        NSWorkspace.shared.open(url)
        log.post(.info, "Opened \(url.host() ?? url.absoluteString) for \(info.title)", source: "VNDB")
    }

    func libraryGame(vndb id: String) -> Game? {
        games.first { $0.vndb?.id == id }
    }

    func showInLibrary(_ id: Game.ID) {
        search = ""
        filter = LibraryFilter()
        sidebar = .library
        selection = id
    }

    /// A game added within a few hours of opening a download page from Discover, with a matching title, gets that VNDB entry.
    func linkIfCameFromDiscover(_ id: Game.ID) {
        guard let (info, opened) = cameFromDiscover, Date.now.timeIntervalSince(opened) < 6 * 3600,
              let game = game(id), game.vndb == nil, VNDB.plausible(game.title, matches: info) else { return }
        cameFromDiscover = nil
        link(id, to: info)
    }
}
