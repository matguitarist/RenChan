import AppKit
import RenChanKit
import SwiftUI

/// The inspector: one game's Ren'Py version, the runtime it plays on, its files and saves.
struct GameDetails: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text(game.title).font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        playButton
                    }
                    Cover(game: game)
                        .aspectRatio(Cover.ratio, contentMode: .fit)
                        .frame(width: 180)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        .frame(maxWidth: .infinity)
                }
            }
            MyGameSection(game: game)
            VNDBSection(game: game)
            Section("Activity") {
                LabeledContent("Playtime", value: game.playtimeText)
                LabeledContent("Last Played") {
                    if model.playing.contains(game.id) {
                        Text("Playing now").foregroundStyle(Palette.accentText)
                    } else {
                        Text(game.lastPlayedText)
                    }
                }
            }
            Section("Saves") {
                LabeledContent("Folder") {
                    if game.saveDirectory != nil {
                        Button(savesTitle) { model.openSaves(game.id) }
                    } else {
                        Text("Found the first time you play").foregroundStyle(.secondary)
                    }
                }
                if let folder = game.saveDirectory {
                    Text(verbatim: "~/Library/RenPy/\(folder)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    BackupRow(game: game)
                }
            }
            Section("Ren'Py") {
                LabeledContent("Version") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(game.version?.description ?? String(localized: "Unknown"))
                        if let source = game.versionSource {
                            Text("From \(source.rawValue)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Python", value: game.pythonLine?.title ?? String(localized: "Unknown"))
                LabeledContent("Plays on") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Ren'Py \(model.runtimeVersion(for: game))")
                        Text(runtimeNote).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Files") {
                LabeledContent("Location") {
                    Button("Show in Finder") { model.showInFinder(game.id) }
                }
            }
            Section {
                Button("Remove from Library…", role: .destructive) { model.confirmRemove = game.id }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var playButton: some View {
        if model.playing.contains(game.id) {
            Button("Stop", systemImage: "stop.fill") { model.stop(game.id) }
                .controlSize(.large)
                .help("Quit the game (Command-Period)")
        } else {
            Button("Play", systemImage: "play.fill") { model.play(game.id) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.download != nil)
                .help("Play \(game.title) (Command-Return)")
        }
    }

    private var savesTitle: String {
        let count = model.saveCount(game) ?? 0
        return count == 1 ? String(localized: "1 Save") : String(localized: "\(count) Saves")
    }

    private var runtimeNote: String {
        guard let runtime = model.installedRuntime(for: game) else {
            return String(localized: "Downloads from renpy.org the first time you play")
        }
        return runtime.isUniversal ? String(localized: "Native on this Mac") : String(localized: "Runs under Rosetta")
    }
}
