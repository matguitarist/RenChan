import RenChanKit
import SwiftUI

/// The inspector's My Game section: status, rating, labels and notes (S-011).
struct MyGameSection: View {
    @Environment(AppModel.self) private var model
    let game: Game
    @State private var newLabel = ""
    /// Notes being typed, not yet in the library.
    @State private var notes: String?

    var body: some View {
        Section("My Game") {
            Picker("Status", selection: Binding(get: { game.status }, set: { value in model.update(game.id) { $0.status = value } })) {
                ForEach(PlayStatus.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            LabeledContent("Rating") {
                StarRating(rating: Binding(get: { game.rating }, set: { value in model.update(game.id) { $0.rating = value } }))
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Labels")
                if game.labels.isEmpty {
                    Text("No labels").font(.callout).foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: Space.xs) {
                        ForEach(game.labels, id: \.self) { label in
                            LabelChip(text: label) { model.update(game.id) { $0.labels.removeAll { $0 == label } } }
                        }
                    }
                }
                TextField("Add Label", text: $newLabel, prompt: Text("Add a label"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .onSubmit {
                        let label = newLabel
                        model.update(game.id) { $0.labels = Labels.add(label, to: $0.labels) }
                        newLabel = ""
                    }
                    .textInputSuggestions {
                        ForEach(model.allLabels.filter { label in
                            !game.labels.contains(label) && (newLabel.isEmpty || label.localizedStandardContains(newLabel))
                        }, id: \.self) { Text($0).textInputCompletion($0) }
                    }
            }
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Notes")
                TextField("Notes", text: Binding(get: { notes ?? game.notes }, set: { notes = $0 }),
                          prompt: Text("Routes done, choices to try…"), axis: .vertical)
                    .lineLimit(3...10)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
        }
        .onChange(of: game.id) { old, _ in
            newLabel = ""
            saveNotes(to: old)
        }
        .onDisappear { saveNotes(to: game.id) }
        // Typing changes only this view; the library takes the notes after half a second of quiet.
        .task(id: notes) {
            guard notes != nil else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveNotes(to: game.id)
        }
    }

    private func saveNotes(to id: Game.ID) {
        guard let text = notes else { return }
        notes = nil
        if model.game(id)?.notes != text { model.update(id) { $0.notes = text } }
    }
}

/// One to five stars; clicking the current rating clears it.
struct StarRating: View {
    @Binding var rating: Int?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = rating == star ? nil : star
                } label: {
                    Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                        .foregroundStyle(star <= (rating ?? 0) ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.tertiary))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Rating")
        .accessibilityValue(rating.map { $0 == 1 ? String(localized: "1 star") : String(localized: "\($0) stars") } ?? String(localized: "Not rated"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, (rating ?? 0) + 1)
            case .decrement: rating = (rating ?? 0) <= 1 ? nil : (rating ?? 0) - 1
            @unknown default: break
            }
        }
        .help("Rate this game")
    }
}

/// A label with a button to take it off the game.
private struct LabelChip: View {
    let text: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            Text(verbatim: text).font(.callout)
            Button(action: remove) {
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Remove label \(text)"))
            .help("Remove this label")
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 2)
        .background(Palette.accent.opacity(0.15), in: Capsule())
    }
}

/// Lays children in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            let gap = rows[rows.count - 1].items.isEmpty ? 0 : spacing
            rows[rows.count - 1].items.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

/// The toolbar's Filter menu: status, rating, labels (S-011).
struct FilterMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Menu {
            Picker("Status", selection: $model.filter.status) {
                Text("Any Status").tag(PlayStatus?.none)
                ForEach(PlayStatus.allCases, id: \.self) { Text($0.title).tag(PlayStatus?.some($0)) }
            }
            Picker("Rating", selection: $model.filter.minimumRating) {
                Text("Any Rating").tag(Int?.none)
                ForEach(1...5, id: \.self) { stars in
                    Text(stars == 5 ? String(localized: "5 Stars") : String(localized: "\(stars) Stars or More")).tag(Int?.some(stars))
                }
            }
            let labels = model.allLabels
            if !labels.isEmpty {
                Section("Labels") {
                    ForEach(labels, id: \.self) { label in
                        Toggle(label, isOn: Binding(get: { model.filter.labels.contains(label) },
                                                    set: { if $0 { model.filter.labels.insert(label) } else { model.filter.labels.remove(label) } }))
                    }
                }
            }
            Divider()
            Button("Clear Filters") { model.filter = LibraryFilter() }
                .disabled(!model.filter.isActive)
        } label: {
            Label("Filter", systemImage: model.filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help(model.filter.isActive ? "Filters are on: change or clear them" : "Show only games with a status, rating or label")
    }
}

extension PlayStatus {
    var title: String {
        switch self {
        case .notStarted: String(localized: "Not Started")
        case .playing: String(localized: "Playing")
        case .finished: String(localized: "Finished")
        }
    }
}

extension Game {
    /// "★★★☆☆", or nothing for a game not rated.
    var stars: String {
        guard let rating else { return "" }
        return String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating)
    }
}
