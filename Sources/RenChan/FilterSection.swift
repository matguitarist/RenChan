import AppKit
import RenChanKit
import SwiftUI

extension ScreenFilter {
    var title: String {
        switch self {
        case .sharpen: String(localized: "Sharpen")
        case .fsrSharpen: String(localized: "FSR Sharpen")
        case .fsrUpscale: String(localized: "FSR Upscale")
        case .crt: String(localized: "CRT")
        case .nightWarmth: String(localized: "Night Warmth")
        case .grayscale: String(localized: "Grayscale")
        case .protanopia: String(localized: "Protanopia (red)")
        case .deuteranopia: String(localized: "Deuteranopia (green)")
        case .tritanopia: String(localized: "Tritanopia (blue)")
        }
    }
}

/// The inspector's Screen Filter section (S-014): a filter and its strength, used from the next launch.
struct FilterSection: View {
    @Environment(AppModel.self) private var model
    let game: Game

    private var tier: FilterTier { FilterTier.forRuntime(model.runtimeVersion(for: game)) }

    var body: some View {
        Section("Screen Filter") {
            Picker("Filter", selection: Binding(get: { FilterChoice(game.filter) }, set: { new in
                model.update(game.id) { $0.filter = new.setting(strength: game.filter?.strength ?? 1) }
                model.applyFilterLive(game.id)
            })) {
                Text("None").tag(FilterChoice.none)
                Divider()
                ForEach([ScreenFilter.fsrUpscale, .fsrSharpen, .sharpen, .crt, .nightWarmth, .grayscale], id: \.self) { Text($0.title).tag(FilterChoice.builtIn($0)) }
                Section("Color Blindness") {
                    ForEach([ScreenFilter.protanopia, .deuteranopia, .tritanopia], id: \.self) { Text($0.title).tag(FilterChoice.builtIn($0)) }
                }
                if !model.customFilters.isEmpty || game.filter?.custom != nil {
                    Section("Your Filters") {
                        ForEach(model.customFilters) { Text(verbatim: $0.name).tag(FilterChoice.custom($0.file)) }
                        if let file = game.filter?.custom, !model.customFilters.contains(where: { $0.file == file }) {
                            Text("\(file) (missing)").tag(FilterChoice.custom(file))
                        }
                    }
                }
            }
            .disabled(tier == .unsupported)
            if tier == .unsupported {
                Text("Filters need Ren'Py 7.4.6 or later. This game plays on Ren'Py \(model.runtimeVersion(for: game)).")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let setting = game.filter {
                LabeledContent("Strength") {
                    Slider(value: Binding(get: { setting.strength }, set: { value in
                        model.update(game.id) { $0.filter?.strength = value }
                        model.applyFilterLive(game.id)
                    }), in: 0...1)
                    .frame(maxWidth: 180)
                }
                if setting.custom == nil && setting.filter == .fsrUpscale {
                    Text("Upscales the game's pictures from its own size to your screen with AMD FSR 1; text and menus stay as sharp as without it. Best for games made for 720p or 1080p.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let file = setting.custom, !model.customFilters.contains(where: { $0.file == file }) {
                    Text("This filter's file is gone from RenChan's Filters folder, so the game plays without it.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text(model.playing.contains(game.id) ? "Changes show in the game within a second, including edits saved to your own filter's file."
                                                     : "Applies when you play, and can be changed while the game runs. The game itself isn't changed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.playing.contains(game.id), let error = model.filterErrors[game.id] {
                Label("The game kept the last filter: this one didn't compile. \(error)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
            if tier != .unsupported {
                HStack {
                    Button("Add Filter…") { model.addCustomFilter(for: game.id) }
                        .help("Add a .glsl fragment shader of your own as a filter")
                    if !model.customFilters.isEmpty {
                        Button("Show Filters Folder") { NSWorkspace.shared.open(Store.filtersFolder) }
                    }
                }
            }
        }
    }
}

/// What the Filter picker holds.
enum FilterChoice: Hashable {
    case none, builtIn(ScreenFilter), custom(String)

    init(_ setting: FilterSetting?) {
        guard let setting else { self = .none; return }
        self = setting.custom.map(FilterChoice.custom) ?? .builtIn(setting.filter)
    }

    func setting(strength: Double) -> FilterSetting? {
        switch self {
        case .none: nil
        case .builtIn(let filter): FilterSetting(filter: filter, strength: strength)
        case .custom(let file): FilterSetting(custom: file, strength: strength)
        }
    }
}

extension AppModel {
    /// S-015: while the game runs, its filter follows the inspector within a second: another filter, None, the strength.
    func applyFilterLive(_ id: Game.ID) {
        guard playing.contains(id), let game = game(id) else { return }
        FilterLoader.update(game.filter, custom: customFilters, copy: runningCopies[id] ?? Store.workingCopy(id))
    }

    /// While games play: picks up edits to the person's .glsl files and reports shaders Ren'Py couldn't compile,
    /// so a filter can be written with the game open beside it.
    func startFilterWatch() {
        guard filterWatch == nil else { return }
        filterWatch = Task { [weak self] in
            while let self, !self.playing.isEmpty, !Task.isCancelled {
                let found = CustomFilters.list(in: Store.filtersFolder)
                if found != self.customFilters { self.customFilters = found }
                for id in self.playing {
                    self.applyFilterLive(id)
                    let error = FilterLoader.lastError(copy: self.runningCopies[id] ?? Store.workingCopy(id))
                    if self.filterErrors[id] != error {
                        self.filterErrors[id] = error
                        if let error, let game = self.game(id) { self.log.post(.warning, "\(game.title): filter \(game.filter?.name ?? "") didn't compile; kept the last one. \(error)", source: "Filters") }
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
            self?.filterErrors = [:]
            self?.filterWatch = nil
        }
    }
}

extension AppModel {
    /// S-016: checks a .glsl file, copies it into RenChan's Filters folder, and picks it for the game.
    func addCustomFilter(for id: Game.ID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "glsl") ?? .plainText]
        panel.message = String(localized: "Choose a .glsl fragment shader whose first line names it, such as // {\"name\": \"Sepia\"}.")
        panel.prompt = String(localized: "Add Filter")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let filter = try CustomFilters.add(url, to: Store.filtersFolder)
            customFilters = CustomFilters.list(in: Store.filtersFolder)
            update(id) { $0.filter = FilterSetting(custom: filter.file, strength: $0.filter?.strength ?? 1) }
            log.post(.info, "Added the filter \(filter.name) from \(url.lastPathComponent)", source: "Filters")
        } catch let problem as CustomFilter.Problem {
            notice = problem.message
        } catch {
            notice = String(localized: "RenChan couldn't add \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

extension CustomFilter.Problem {
    var message: String {
        switch self {
        case .noHeader: String(localized: "The filter needs a first line that names it, such as // {\"name\": \"Sepia\"}.")
        case .noName: String(localized: "The filter's first line needs a name, such as // {\"name\": \"Sepia\"}.")
        case .noCode: String(localized: "The filter has a name but no shader code after it.")
        }
    }
}
