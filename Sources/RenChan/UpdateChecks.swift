import AppKit
import RenChanKit
import SwiftUI
import UserNotifications

/// Watching a game's itch.io page or F95zone thread for new versions (S-033).
extension AppModel {
    static let watchChecksKey = "watchChecks"
    var watchChecksOn: Bool { UserDefaults.standard.object(forKey: Self.watchChecksKey) as? Bool ?? true }

    /// Returns false, with a notice, when the text isn't an itch.io page or F95zone thread.
    @discardableResult
    func setWatch(_ text: String, for id: Game.ID) -> Bool {
        guard let url = UpdateWatch.validate(text) else {
            notice = String(localized: "RenChan watches itch.io game pages and F95zone threads, such as https://studio.itch.io/game or https://f95zone.to/threads/game.12345/.")
            return false
        }
        update(id) { $0.watch = UpdateWatch(page: url.absoluteString) }
        log.post(.info, "Watching \(url.absoluteString) for new versions of \(game(id)?.title ?? "")", source: "Updates")
        checkNewVersion(id)
        return true
    }

    func stopWatching(_ id: Game.ID) {
        update(id) { $0.watch = nil }
    }

    func dismissNewVersion(_ id: Game.ID) {
        update(id) { game in
            let latest = game.watch?.latest
            game.watch?.dismissed = latest
        }
    }

    func openWatchPage(_ id: Game.ID) {
        guard let url = game(id)?.watch?.url else { return }
        NSWorkspace.shared.open(url)
    }

    func checkNewVersion(_ id: Game.ID) {
        Task { await check(id) }
    }

    /// Checks every watched game that is due (or all of them), one page at a time, a few seconds apart.
    func checkForNewVersions(force: Bool = false) {
        guard watchTask == nil else { return }
        let due = games.filter { $0.watch != nil && (force || $0.watch!.isDue()) }.map(\.id)
        guard !due.isEmpty else { return }
        watchTask = Task {
            for (index, id) in due.enumerated() {
                if index > 0 { try? await Task.sleep(for: .seconds(3)) }
                if Task.isCancelled { break }
                await check(id)
            }
            watchTask = nil
        }
    }

    /// Daily checks: a while after launch, then every few hours while RenChan stays open.
    func startWatchChecks() {
        guard !Store.isOverridden else { return }
        Task {
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                if watchChecksOn { checkForNewVersions() }
                try? await Task.sleep(for: .seconds(4 * 3600))
            }
        }
    }

    private func check(_ id: Game.ID) async {
        guard let watch = game(id)?.watch, let url = watch.url, !checkingVersions.contains(id) else { return }
        checkingVersions.insert(id)
        defer { checkingVersions.remove(id) }
        let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        do {
            let version = try await PageVersion.fetch(url, userAgent: "RenChan/\(app) (macOS; +https://github.com/matguitarist/RenChan)")
            update(id) { $0.watch?.record(version: version, error: nil) }
        } catch {
            let text = Self.watchMessage(error)
            update(id) { $0.watch?.record(version: nil, error: text) }
            log.post(.warning, "Couldn't check \(url.absoluteString): \(error)", source: "Updates")
            return
        }
        guard let game = game(id), let news = game.newVersion else { return }
        log.post(.info, "\(game.title) \(news) is out on \(url.host() ?? "its page")", source: "Updates")
        guard game.watch?.notified != news else { return }
        update(id) { $0.watch?.notified = news }
        notify(title: game.title, version: news)
    }

    static func watchMessage(_ error: any Error) -> String {
        switch error {
        case PageVersion.Failure.status(404): String(localized: "The page is gone.")
        case PageVersion.Failure.status(let code): String(localized: "The site answered \(code).")
        case PageVersion.Failure.loginWall: String(localized: "The page needs a login.")
        case PageVersion.Failure.noVersion: String(localized: "No version found on the page.")
        default: error.localizedDescription
        }
    }

    private func notify(title: String, version: String) {
        guard !Store.isOverridden else { return }
        let center = UNUserNotificationCenter.current()
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "New version of \(title)")
            content.body = String(localized: "Version \(version) is out. Download it, then use Update to New Version… in RenChan.")
            try? await center.add(UNNotificationRequest(identifier: "\(title)-\(version)", content: content, trigger: nil))
        }
    }
}

/// Inspector › Files: the game's own version and the page watched for new ones (S-033).
struct WatchRows: View {
    @Environment(AppModel.self) private var model
    let game: Game
    @State private var asking = false
    @State private var page = ""

    var body: some View {
        LabeledContent("Game Version", value: game.gameVersion ?? String(localized: "Unknown"))
        LabeledContent("Watch") {
            if let watch = game.watch {
                HStack(spacing: Space.sm) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: watch.url?.host() ?? watch.page).lineLimit(1).truncationMode(.middle)
                        Text(status(watch)).font(.caption)
                            .foregroundStyle(game.newVersion != nil ? Palette.accent : (watch.error != nil ? Color.orange : Color.secondary))
                    }
                    Menu {
                        Button("Open Page") { model.openWatchPage(game.id) }
                        Button("Check Now") { model.checkNewVersion(game.id) }
                        if game.newVersion != nil { Button("Dismiss This Version") { model.dismissNewVersion(game.id) } }
                        Divider()
                        Button("Change Page…") { page = watch.page; asking = true }
                        Button("Stop Watching") { model.stopWatching(game.id) }
                    } label: {
                        if model.checkingVersions.contains(game.id) { ProgressView().controlSize(.small) } else { Image(systemName: "ellipsis.circle") }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Open, check or stop watching this page")
                }
            } else {
                Button("Watch Page…") { page = ""; asking = true }
                    .help("Get told when a new version is out on this game's itch.io page or F95zone thread")
            }
        }
        .alert("Watch for New Versions", isPresented: $asking) {
            TextField("https://studio.itch.io/game", text: $page)
            Button("Watch") { model.setWatch(page, for: game.id) }
                .disabled(page.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste the game's itch.io page or F95zone thread. RenChan reads its version once a day and tells you when a newer one is out.")
        }
    }

    private func status(_ watch: UpdateWatch) -> String {
        if let news = game.newVersion { return String(localized: "Version \(news) is out") }
        if let error = watch.error { return String(localized: "Couldn't check: \(error)") }
        if let latest = watch.latest { return String(localized: "Page shows \(latest)") }
        return model.checkingVersions.contains(game.id) ? String(localized: "Checking…") : String(localized: "Not checked yet")
    }
}

/// The badge on a game's card when a new version is out.
struct NewVersionBadge: View {
    let version: String

    var body: some View {
        Label(String(localized: "New \(version)"), systemImage: "arrow.down.circle.fill")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .background(Palette.accent, in: Capsule())
            .padding(Space.sm)
            .help(String(localized: "Version \(version) is out on the game's page"))
    }
}
