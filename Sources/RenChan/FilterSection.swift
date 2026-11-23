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
                // None while playing fades the running filter out now; another filter waits for the next launch.
                if new == .none { model.tuneFilter(game.id, strength: 0) }
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
                        model.tuneFilter(game.id, strength: value)
                    }), in: 0...1)
                    .frame(maxWidth: 180)
                }
                if setting.custom == nil && setting.filter == .fsrUpscale {
                    Text("Draws the game at its own size, then upscales it to your screen with AMD FSR 1. Best for games made for 720p or 1080p; text can look a little softer.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let file = setting.custom, !model.customFilters.contains(where: { $0.file == file }) {
                    Text("This filter's file is gone from RenChan's Filters folder, so the game plays without it.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text(model.playing.contains(game.id) ? "Strength changes show in the game right away. Another filter shows the next time you play."
                                                     : "Applies when you play. The game itself isn't changed.")
                    .font(.caption).foregroundStyle(.secondary)
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
    /// S-015: while the game runs, its filter reads this strength within a second.
    func tuneFilter(_ id: Game.ID, strength: Double) {
        guard playing.contains(id) else { return }
        FilterLoader.writeStrength(strength, copy: Store.workingCopy(id))
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
