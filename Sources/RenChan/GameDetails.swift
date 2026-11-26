import AppKit
import RenChanKit
import SwiftUI

/// The inspector: one game's Ren'Py version, the runtime it plays on, its files and saves.
struct GameDetails: View {
    @Environment(AppModel.self) private var model
    let game: Game

    var body: some View {
        ScrollViewReader { proxy in form.onChange(of: model.inspectorScroll) { _, id in
            if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
        } }
    }

    private var form: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                        Text(game.title).font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        playButton
                    }
                    if let progress = model.copying[game.id] { copyProgress(progress) }
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
            FilterSection(game: game)
            WalkthroughsSection(game: game)
            ModsSection(game: game)
            Section("Saves") {
                LabeledContent("Folder") {
                    if game.saveDirectory != nil {
                        HStack(spacing: Space.sm) {
                            Button(savesTitle) { model.showSaves(game.id) }
                                .help("See each save and change its variables (Shift-Command-B)")
                            Button("Open Saves Folder", systemImage: "folder") { model.openSaves(game.id) }
                                .labelStyle(.iconOnly)
                                .help("Show the saves folder in the Finder (Option-Command-S)")
                        }
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
                        runtimePicker
                        Text(runtimeNote).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .id("runtime")
                RunAndDevToolsRows(game: game)
            }
            Section("Files") {
                LabeledContent("Location") {
                    Button("Show in Finder") { model.showInFinder(game.id) }
                }
                LabeledContent("Pictures") {
                    Button("Gallery…") { model.showGallery(game.id) }
                        .help("See every picture of the game, without playing it (Option-Command-G)")
                }
                WatchRows(game: game)
                LabeledContent("New version") {
                    HStack(spacing: Space.sm) {
                        if let info = game.vndb {
                            let links = model.downloadLinks(info.id)
                            Menu("Get It") {
                                ForEach(links, id: \.url) { link in
                                    Button(link.label) { model.openDownloadPage(link.url, for: info) }
                                }
                                if links.isEmpty {
                                    Text(model.releasesLoading.contains(info.id) ? String(localized: "Loading…") : String(localized: "No download pages on VNDB"))
                                }
                            }
                            .fixedSize()
                            .help("Open the page where the new version is downloaded")
                        }
                        Button("Update…") { model.chooseUpdate(game.id) }
                            .disabled(model.playing.contains(game.id))
                            .help("Point this game at its new version; playtime, labels, notes and backups stay (Shift-Command-U)")
                    }
                }
            }
            Section {
                Button("Remove from Library…", role: .destructive) { model.confirmRemove = game.id }
            }
        }
        .formStyle(.grouped)
        .task(id: game.vndb?.id) { if let id = game.vndb?.id { model.loadReleases(id) } }
    }

    /// The copy made before a first launch: a bar with how far a full copy got, or a spinner for a clone.
    private func copyProgress(_ progress: CopyProgress) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                Text("Copying the game: \(progress.copied.bytesText) of \(progress.total.bytesText)")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            } else {
                HStack(spacing: Space.sm) {
                    ProgressView().controlSize(.small)
                    Text("Preparing the game…").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var playButton: some View {
        if model.copying[game.id] != nil {
            Button("Cancel Copy", systemImage: "xmark") { model.stop(game.id) }
                .controlSize(.large)
                .help("Stop copying the game; nothing half-copied is kept (Command-Period)")
        } else if model.playing.contains(game.id) {
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

    /// Automatic is RenChan's pick; the others are the version the game was made with and installed runtimes.
    private var runtimePicker: some View {
        let choices = model.runtimeChoices(game)
        return Picker("Plays on", selection: Binding(get: { game.runtimeOverride ?? "" },
                                                     set: { model.setRuntime($0.isEmpty ? nil : $0, for: game.id) })) {
            Text(choices.automatic.map { String(localized: "Automatic (Ren'Py \($0))") } ?? String(localized: "Automatic")).tag("")
            if let exact = choices.exact {
                Text("Ren'Py \(exact), the version it was made with").tag(exact)
            }
            ForEach(choices.others, id: \.self) { version in
                Text(verbatim: "Ren'Py \(version)").tag(version)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(model.playing.contains(game.id) || model.copying[game.id] != nil)
        .help("The Ren'Py this game plays on. Automatic is RenChan's pick; another one downloads the first time you play.")
    }

    private var runtimeNote: String {
        guard let runtime = model.installedRuntime(for: game) else {
            return String(localized: "Downloads from renpy.org the first time you play")
        }
        return runtime.isUniversal ? String(localized: "Native on this Mac") : String(localized: "Runs under Rosetta")
    }
}
