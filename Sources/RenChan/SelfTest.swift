import AppKit
import RenChanKit

/// Self-test for agents: drives the app model on a library in /tmp,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/RenChan-self.json ~/Applications/RenChan.app/Contents/MacOS/RenChan --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp so the test never touches the real library")
            finish(code: 1)
            return
        }
        Task {
            check("the library folder is the test one", Store.url.path.hasPrefix("/tmp") || Store.url.path.hasPrefix("/private/tmp"))
            check("the app wrote its start line to the log", model.log.entries.contains { $0.message.hasPrefix("RenChan ") && $0.message.hasSuffix(" started") })
            model.log.post(.info, "Self-test line", source: "SelfTest")
            model.log.flushFile()
            let written = (try? String(contentsOf: Store.logURL, encoding: .utf8)) ?? ""
            check("log lines reach the log file next to the store", written.contains("Self-test line"))

            for tab in SettingsTab.allCases {
                model.settingsTab = tab
                try? await Task.sleep(for: .milliseconds(100))
                check("Settings opens on \(tab.rawValue)", model.settingsTab == tab)
            }
            for page in SidebarItem.allCases {
                model.sidebar = page
                try? await Task.sleep(for: .milliseconds(100))
                check("the sidebar shows \(page.rawValue)", model.sidebar == page)
            }

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
