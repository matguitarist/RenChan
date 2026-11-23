import RenChanKit
import SwiftUI

extension ScreenFilter {
    var title: String {
        switch self {
        case .sharpen: String(localized: "Sharpen")
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
            Picker("Filter", selection: Binding(get: { game.filter?.filter }, set: { new in
                model.update(game.id) { $0.filter = new.map { FilterSetting(filter: $0, strength: game.filter?.strength ?? 1) } }
                // None while playing fades the running filter out now; another filter waits for the next launch.
                if new == nil { model.tuneFilter(game.id, strength: 0) }
            })) {
                Text("None").tag(ScreenFilter?.none)
                Divider()
                ForEach([ScreenFilter.sharpen, .crt, .nightWarmth, .grayscale], id: \.self) { Text($0.title).tag(Optional($0)) }
                Section("Color Blindness") {
                    ForEach([ScreenFilter.protanopia, .deuteranopia, .tritanopia], id: \.self) { Text($0.title).tag(Optional($0)) }
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
                Text(model.playing.contains(game.id) ? "Strength changes show in the game right away. Another filter shows the next time you play."
                                                     : "Applies when you play. The game itself isn't changed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
