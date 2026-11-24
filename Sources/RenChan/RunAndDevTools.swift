import AppKit
import RenChanKit
import SwiftUI
import UniformTypeIdentifiers

/// In the inspector's Ren'Py section: how the game last ran (S-027) and Ren'Py's developer tools (S-022).
struct RunAndDevToolsRows: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        LabeledContent("Last Run") {
            if let run = game.runs.first {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(run.outcome == .worked ? String(localized: "Worked on Ren'Py \(run.runtime)") : String(localized: "Failed on Ren'Py \(run.runtime)"))
                        .foregroundStyle(run.outcome == .worked ? Color.primary : Color.orange)
                    Text(run.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Not played yet").foregroundStyle(.secondary)
            }
        }
        let languages = model.languages(game)
        if !languages.isEmpty || game.language != nil {
            Picker(selection: Binding(get: { game.language }, set: { language in model.update(game.id) { $0.language = language } })) {
                Text("Game’s Choice").tag(String?.none)
                Text("Original Language").tag(String?.some(LanguageLoader.original))
                Divider()
                ForEach(languages, id: \.self) { language in
                    Text(verbatim: GameLanguages.title(language, locale: .app)).tag(String?.some(language))
                }
                if let chosen = game.language, chosen != LanguageLoader.original, !languages.contains(chosen) {
                    Text("\(GameLanguages.title(chosen, locale: .app)) (missing)").tag(String?.some(chosen))
                }
            } label: {
                Text("Language")
            }
            .help("The language the game starts in, from its next launch. Game’s Choice starts in the one last used in the game.")
            .id("language")
        }
        Toggle(isOn: Binding(get: { game.devTools.console }, set: { on in model.update(game.id) { $0.devTools.console = on } })) {
            Text("Console (Shift+O)")
        }
        .help("Turn on Ren'Py's developer console for this game, from its next launch")
        Toggle(isOn: Binding(get: { game.devTools.fastSkip }, set: { on in model.update(game.id) { $0.devTools.fastSkip = on } })) {
            Text("Fast Skip (>)")
        }
        .help("Let the > key skip ahead to the next choice, from the next launch")
    }
}

/// S-039: the translations a game ships, with those its mods that are on add.
extension AppModel {
    func languages(_ game: Game) -> [String] {
        var key = Hasher()
        key.combine(modsRevision); key.combine(game.basePath); key.combine(game.mods)
        return memoized("languages-\(game.id)", key: key.finalize()) {
            let modPaths = enabledMods(game).flatMap { ModLibrary.currentFiles($0, root: Store.modsFolder) }
            return GameLanguages.find(base: game.baseURL, extraPaths: modPaths)
        }
    }
}

/// File › Export Compatibility Report… (S-027).
extension AppModel {
    func compatibilityReport() -> String {
        let info = ProcessInfo.processInfo
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var chip = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &chip, &size, nil, 0)
        return CompatibilityReport.markdown(games, app: "RenChan \(version)", system: "macOS \(info.operatingSystemVersionString)",
                                            chip: String(decoding: chip.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
    }

    func exportCompatibilityReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "RenChan compatibility report.md"
        panel.message = String(localized: "Each game, its Ren'Py version, and how it last ran. Attach it to a bug report.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try compatibilityReport().write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            notice = String(localized: "RenChan couldn't save the report: \(error.localizedDescription)")
        }
    }

    func copyCompatibilityReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(compatibilityReport(), forType: .string)
    }
}

extension Locale {
    /// The language RenChan shows itself in (Settings > General), which can differ from the Mac's region.
    static var app: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }
}
