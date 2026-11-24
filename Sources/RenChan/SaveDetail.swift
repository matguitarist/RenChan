import AppKit
import RenChanKit
import SwiftUI

/// One save: its screenshot and details, and its variables to change (S-035, S-036).
/// With no save, the persistent data every save shares, and Unlock All Images (S-040).
struct SaveDetail: View {
    @Environment(AppModel.self) private var model
    let game: Game
    let save: SaveFile?
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
        }
    }

    private var persistentSection: some View {
        Section {
            Text("What the game remembers across every save: unlocked galleries, endings seen, and its own settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !unlockFlags.isEmpty {
                let off = unlockFlags.filter { (edits[$0.name] ?? $0.value) == "false" }
                LabeledContent("Unlock Values") {
                    HStack(spacing: Space.sm) {
                        Text("\(off.count) of \(unlockFlags.count) off").foregroundStyle(.secondary).monospacedDigit()
                        Button("Turn All On") { for variable in off { edits[variable.name] = "true" } }
                            .disabled(loading || off.isEmpty)
                            .help("Turn on the game’s own gallery and unlock values below, then Save Changes to write them")
                    }
                }
            }
            LabeledContent("Gallery Images") {
                HStack(spacing: Space.sm) {
                    Text(images == 1 ? String(localized: "1 image") : String(localized: "\(images) images")).foregroundStyle(.secondary).monospacedDigit()
                    Button("Unlock All…") { confirmUnlock = true }
                        .disabled(loading || images == 0 || model.playing.contains(game.id))
                        .help("Mark every image the game defines as seen. This unlocks galleries made with Ren'Py’s own Gallery; games with their own gallery use the unlock values above.")
                }
            }
        } header: {
            Text("Persistent Data")
        }
    }

    /// The game's own gallery and unlock switches, which games with their own gallery check.
    private var unlockFlags: [SaveVariable] { variables.filter(\.isUnlockFlag) }

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

    private var shown: [SaveVariable] {
        search.isEmpty ? variables : variables.filter { $0.name.localizedCaseInsensitiveContains(search) }
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
                Text(verbatim: variable.name).font(.body.monospaced())
                if edits[variable.name] != nil { Circle().fill(Palette.accent).frame(width: Space.sm, height: Space.sm).help("Changed, not saved yet") }
            }
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
                    (variables, images) = try await model.readPersistent(of: game, modded: modded)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func write() {
        var changes: [String: Any] = [:]
        for (name, text) in edits { if let value = variables.first(where: { $0.name == name })?.encode(text) { changes[name] = value } }
        loading = true
        Task {
            do {
                let changed = if let save { try await model.writeVariables(changes, in: save, of: game, modded: modded) }
                              else { try await model.writePersistent(changes, of: game, modded: modded) }
                edits = [:]
                done = changed.count == 1 ? String(localized: "Saved 1 change. The saves were backed up first.")
                                          : String(localized: "Saved \(changed.count) changes. The saves were backed up first.")
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
