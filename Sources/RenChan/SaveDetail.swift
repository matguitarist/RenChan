import AppKit
import RenChanKit
import SwiftUI

/// One save: its screenshot and details, and its variables to change (S-035, S-036).
/// With no save, the persistent data every save shares, and Unlock All Images (S-040).
struct SaveDetail: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let save: SaveFile?
    /// Every save in the window, for Save to All Saves.
    let allSaves: [SaveFile]
    let modded: Bool
    let saved: () -> Void
    @State private var screenshot: NSImage?
    @State private var variables: [SaveVariable] = []
    @State private var edits: [String: String] = [:]
    @State private var search = ""
    @State private var loading = false
    @State private var error: String?
    @State private var done: String?
    @State private var images = 0
    @State private var confirmUnlock = false
    @State private var labels = 0
    @State private var seenLabels = 0
    @State private var confirmReplays = false
    @State private var onlyChanges = false
    @State private var confirmAll = false

    var body: some View {
        Form {
            if let save { saveSection(save) } else { persistentSection }
            Section {
                if loading {
                    HStack(spacing: Space.sm) { ProgressView().controlSize(.small); Text(save == nil ? "Reading the persistent data with Ren'Py…" : "Reading the save with Ren'Py…").foregroundStyle(.secondary) }
                } else if let error {
                    Text(error).foregroundStyle(.orange)
                    Button("Try Again") { load() }
                } else if variables.isEmpty {
                    Text(save == nil ? "The game keeps no persistent values of its own." : "This save has no variables RenChan can show.").foregroundStyle(.secondary)
                } else {
                    if !edits.isEmpty {
                        // Turn All On can stage many changes; this shows exactly what Save Changes will write.
                        Toggle(isOn: $onlyChanges) {
                            Text(edits.count == 1 ? String(localized: "Show Only the 1 Change") : String(localized: "Show Only the \(edits.count) Changes"))
                        }
                    }
                    let offShown = shown.filter { $0.kind == .bool && (edits[$0.name] ?? $0.value) == "false" }
                    if !search.isEmpty && !offShown.isEmpty {
                        Button("Turn On \(offShown.count) Shown") { for variable in offShown { edits[variable.name] = "true" } }
                            .help("Turn on every on/off value that matches the search. Nothing is written until Save Changes.")
                    }
                    ForEach(shown) { variable in row(variable) }
                    if shown.isEmpty { Text("No variable matches “\(search)”.").foregroundStyle(.secondary) }
                }
            } header: {
                Text("Variables")
            } footer: {
                Text(done ?? (save == nil ? String(localized: "On/off values, numbers and text can be changed. RenChan backs up the saves first; the game reads the changes the next time it starts.")
                                          : String(localized: "On/off values, numbers and text can be changed. RenChan backs up the saves first, and the game loads the save as usual.")))
                    .font(.caption).foregroundStyle(done == nil ? Color.secondary : Palette.accent)
            }
        }
        .formStyle(.grouped)
        .searchable(text: $search, placement: .toolbar, prompt: Text("Search Variables"))
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Revert") { edits = [:] }.disabled(edits.isEmpty)
                if save != nil && allSaves.count > 1 {
                    Button("Save to All Saves…") { confirmAll = true }
                        .disabled(edits.isEmpty || loading || invalid || model.playing.contains(game.id))
                        .help("Write these changes into every save of the game. Saves without a value skip it.")
                }
                Button("Save Changes") { write() }
                    .buttonStyle(.borderedProminent)
                    .disabled(edits.isEmpty || loading || invalid || model.playing.contains(game.id))
                    .keyboardShortcut("s")
                    .help("Back up the saves, then write these values into this save (Command-S)")
            }
            .padding(Space.md)
            .background(.bar)
        }
        .task {
            if let url = save?.url {
                screenshot = await Task.detached(priority: .utility) { SaveList.read(url)?.screenshot() }.value.flatMap(NSImage.init(data:))
            }
            load()
        }
        .confirmationDialog(edits.count == 1 ? String(localized: "Write 1 change into all \(allSaves.count) saves?")
                                             : String(localized: "Write \(edits.count) changes into all \(allSaves.count) saves?"), isPresented: $confirmAll) {
            Button("Save to All Saves") { write(everySave: true) }
        } message: {
            Text("RenChan backs up the saves first. A save that doesn’t have a value is left as it is.")
        }
        .confirmationDialog(String(localized: "Mark all \(labels) scenes as seen?"), isPresented: $confirmReplays) {
            Button("Mark All Seen") { unlockReplays() }
        } message: {
            Text("This unlocks the game’s replays. Text you haven’t read stays unread, so Skip still stops there. RenChan backs up the saves first.")
        }
        .confirmationDialog(String(localized: "Mark all \(images) images as seen?"), isPresented: $confirmUnlock) {
            Button("Unlock All Images") { unlock() }
        } message: {
            Text("This unlocks them in the game’s gallery. RenChan backs up the saves first.")
        }
    }

    @ViewBuilder
    private func saveSection(_ save: SaveFile) -> some View {
        Section {
            if let screenshot {
                Image(nsImage: screenshot).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 160).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            }
            LabeledContent("Name", value: save.name.isEmpty ? "—" : save.name)
            LabeledContent("Place", value: save.place)
            LabeledContent("Saved", value: save.date.formatted(date: .long, time: .shortened))
            if let playtime = save.playtime, playtime >= 60 {
                LabeledContent("Played", value: Duration.seconds(playtime).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
            }
            if let version = save.renpyVersion { LabeledContent("Ren'Py", value: version.split(separator: ".").prefix(3).joined(separator: ".")) }
            // A save keeps the story's own unlocks, such as which characters' galleries open.
            unlockRow
        }
    }

    private var persistentSection: some View {
        Section {
            Text("What the game remembers across every save: unlocked galleries, endings seen, and its own settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            unlockRow
            LabeledContent("Gallery Images") {
                HStack(spacing: Space.sm) {
                    Text(images == 1 ? String(localized: "1 image") : String(localized: "\(images) images")).foregroundStyle(.secondary).monospacedDigit()
                    Button("Unlock All…") { confirmUnlock = true }
                        .disabled(loading || images == 0 || model.playing.contains(game.id))
                        .help("Mark every image the game defines as seen. This unlocks galleries made with Ren'Py’s own Gallery; games with their own gallery use the unlock values above.")
                }
            }
            LabeledContent("Scenes Seen") {
                HStack(spacing: Space.sm) {
                    Text("\(seenLabels) of \(labels)").foregroundStyle(.secondary).monospacedDigit()
                    Button("Mark All Seen…") { confirmReplays = true }
                        .disabled(loading || labels == 0 || seenLabels >= labels || model.playing.contains(game.id))
                        .help("Mark every scene as played, which unlocks replays made with Ren'Py’s Replay. Text you haven’t read stays unread for Skip.")
                }
            }
        } header: {
            Text("Persistent Data")
        }
    }

    /// "Unlock Values: 4 of 5 off" with Turn All On; the changes wait for Save Changes.
    @ViewBuilder
    private var unlockRow: some View {
        if !unlockFlags.isEmpty {
            let off = unlockFlags.filter { (edits[$0.name] ?? $0.value) == "false" }
            LabeledContent("Unlock Values") {
                HStack(spacing: Space.sm) {
                    Text("\(off.count) of \(unlockFlags.count) off").foregroundStyle(.secondary).monospacedDigit()
                    Button("Turn All On") { for variable in off { edits[variable.name] = "true" } }
                        .disabled(loading || off.isEmpty)
                        .help("Turn on the game’s own on/off values for galleries, unlocks, endings, achievements and replays, then Save Changes to write them")
                }
            }
        }
    }

    /// The game's own gallery and unlock switches, which games with their own gallery check.
    private var unlockFlags: [SaveVariable] { variables.filter(\.isUnlockFlag) }

    private func unlockReplays() {
        loading = true
        error = nil
        Task {
            do {
                let count = try await model.unlockReplays(of: game, modded: modded)
                done = count == 1 ? String(localized: "Marked 1 scene as seen. The saves were backed up first.")
                                  : String(localized: "Marked \(count) scenes as seen. The saves were backed up first.")
                saved()
                loading = false
                load()
            } catch {
                loading = false
                self.error = error.localizedDescription
            }
        }
    }

    private func unlock() {
        loading = true
        error = nil
        Task {
            do {
                let count = try await model.unlockImages(of: game, modded: modded)
                done = count == 1 ? String(localized: "Unlocked 1 image. The saves were backed up first.")
                                  : String(localized: "Unlocked \(count) images. The saves were backed up first.")
                saved()
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    /// The search, then only the changes when asked, with pinned values first.
    private var shown: [SaveVariable] {
        var list = search.isEmpty ? variables : variables.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.note?.localizedCaseInsensitiveContains(search) == true }
        if onlyChanges && !edits.isEmpty { list = list.filter { edits[$0.name] != nil } }
        let pinned = Set(game.pinnedVariables)
        return list.filter { pinned.contains($0.name) } + list.filter { !pinned.contains($0.name) }
    }

    private var invalid: Bool {
        edits.contains { name, text in variables.first { $0.name == name }?.encode(text) == nil }
    }

    @ViewBuilder
    private func row(_ variable: SaveVariable) -> some View {
        let binding = Binding(get: { edits[variable.name] ?? variable.value },
                              set: { edits[variable.name] = $0 == variable.value ? nil : $0 })
        LabeledContent {
            switch variable.kind {
            case .bool:
                Toggle(isOn: Binding(get: { binding.wrappedValue == "true" }, set: { binding.wrappedValue = $0 ? "true" : "false" })) { Text(verbatim: variable.name) }
                    .labelsHidden()
            case .int, .float, .string:
                TextField(text: binding) { Text(verbatim: variable.name) }
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 220)
                    .foregroundStyle(variable.encode(binding.wrappedValue) == nil ? Color.orange : Color.primary)
            case .none, .other:
                Text(variable.value).foregroundStyle(.secondary).lineLimit(1)
                    .help("RenChan changes on/off values, numbers and text only")
            }
        } label: {
            HStack(spacing: Space.xs) {
                if game.pinnedVariables.contains(variable.name) {
                    Image(systemName: "pin.fill").font(.caption).foregroundStyle(Palette.accent).help("Pinned to the top")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: variable.name).font(.body.monospaced())
                    // The list item a value belongs to, such as a gallery entry's name.
                    if let note = variable.note { Text(verbatim: note).font(.caption).foregroundStyle(.secondary) }
                }
                if edits[variable.name] != nil { Circle().fill(Palette.accent).frame(width: Space.sm, height: Space.sm).help("Changed, not saved yet") }
            }
        }
        .contextMenu {
            Button(game.pinnedVariables.contains(variable.name) ? "Unpin" : "Pin to Top") { model.togglePin(variable.name, in: game.id) }
        }
    }

    private func load() {
        loading = true
        error = nil
        Task {
            defer { loading = false }
            do {
                if let save {
                    variables = try await model.readVariables(save, of: game, modded: modded)
                } else {
                    let info = try await model.readPersistent(of: game, modded: modded)
                    (variables, images, labels, seenLabels) = (info.variables, info.images, info.labels, info.seenLabels)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func write(everySave: Bool = false) {
        var changes: [String: Any] = [:]
        for (name, text) in edits { if let value = variables.first(where: { $0.name == name })?.encode(text) { changes[name] = value } }
        loading = true
        Task {
            do {
                if everySave {
                    let result = try await model.writeVariables(changes, in: allSaves, of: game, modded: modded)
                    done = String(localized: "Saved \(result.changed.count) changes in \(result.saves) saves. The saves were backed up first.")
                } else {
                    let changed = if let save { try await model.writeVariables(changes, in: save, of: game, modded: modded) }
                                  else { try await model.writePersistent(changes, of: game, modded: modded) }
                    done = changed.count == 1 ? String(localized: "Saved 1 change. The saves were backed up first.")
                                              : String(localized: "Saved \(changed.count) changes. The saves were backed up first.")
                }
                edits = [:]
                onlyChanges = false
                saved()
                loading = false
                load()
            } catch {
                loading = false
                self.error = error.localizedDescription
            }
        }
    }
}
