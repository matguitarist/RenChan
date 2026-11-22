import Foundation
import LogKit
import LogKitUI
import Observation

/// The app's state: the page shown, Settings, and the log.
@Observable
final class AppModel {
    let log: LogStore
    /// The Log page's viewer; kept here so its filters survive moving between pages.
    let logViewer: LogViewerModel

    var sidebar: SidebarItem? = .overview
    var settingsTab: SettingsTab = .general

    var language: AppLanguage = .current {
        didSet { language.apply() }
    }

    var checksForUpdates: Bool {
        get { Updater.shared.automaticallyChecks }
        set { Updater.shared.automaticallyChecks = newValue }
    }

    init(log: LogStore) {
        self.log = log
        logViewer = LogViewerModel(store: log)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        log.post(.info, "RenChan \(version) started", source: "App")
    }
}

/// The sidebar's pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview, log

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .log: String(localized: "Log")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "books.vertical"
        case .log: "list.bullet.rectangle"
        }
    }
}
