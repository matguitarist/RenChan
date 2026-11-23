import AppKit
import PDFKit
import RenChanKit
import SwiftUI

/// Which walkthrough a Walkthrough window shows (S-032).
struct WalkthroughRef: Codable, Hashable {
    var game: UUID
    var walkthrough: UUID
}

/// Walkthroughs (S-032): add, open, remember the page.
extension AppModel {
    func walkthroughURL(_ game: Game, _ walkthrough: Walkthrough) -> URL {
        Store.walkthroughsFolder(game.id).appending(path: walkthrough.file)
    }

    func addWalkthroughWithPanel(to id: Game.ID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .plainText, .init(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Choose a walkthrough: a PDF or a text file. RenChan keeps its own copy.")
        panel.prompt = String(localized: "Add Walkthrough")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { addWalkthrough(url, to: id) }
    }

    @discardableResult
    func addWalkthrough(_ url: URL, to id: Game.ID) -> Walkthrough? {
        guard let game = game(id) else { return nil }
        do {
            let walkthrough = try Walkthroughs.add(url, into: Store.walkthroughsFolder(id))
            update(id) { $0.walkthroughs.append(walkthrough) }
            log.post(.info, "Added the walkthrough \(walkthrough.name) to \(game.title)", source: "Walkthroughs")
            return walkthrough
        } catch {
            notice = error.message(url.lastPathComponent)
            return nil
        }
    }

    func removeWalkthrough(_ walkthroughID: UUID, from id: Game.ID) {
        guard let game = game(id), let walkthrough = game.walkthroughs.first(where: { $0.id == walkthroughID }) else { return }
        try? FileManager.default.trashItem(at: walkthroughURL(game, walkthrough), resultingItemURL: nil)
        update(id) { $0.walkthroughs.removeAll { $0.id == walkthroughID } }
    }

    func setWalkthroughPage(_ page: Int, _ ref: WalkthroughRef) {
        update(ref.game) { game in
            if let index = game.walkthroughs.firstIndex(where: { $0.id == ref.walkthrough }), game.walkthroughs[index].page != page {
                game.walkthroughs[index].page = page
            }
        }
    }
}

extension WalkthroughError {
    func message(_ file: String) -> String {
        switch self {
        case .notSupported: String(localized: "\(file) isn't a walkthrough RenChan can show. Choose a PDF or a text file.")
        case .notAPDF: String(localized: "\(file) isn't really a PDF. If it came from itch.io, its download link may have expired: download it again.")
        case .failed(let reason): String(localized: "RenChan couldn't add \(file): \(reason)")
        }
    }
}

/// Game › Show Walkthrough: opens the selected game's first walkthrough.
struct ShowWalkthroughButton: View {
    @Environment(\.openWindow) private var openWindow
    let model: AppModel
    let selection: Game.ID?

    var body: some View {
        let first = model.game(selection)?.walkthroughs.first
        Button("Show Walkthrough") {
            if let selection, let first { openWindow(id: "walkthrough", value: WalkthroughRef(game: selection, walkthrough: first.id)) }
        }
        .keyboardShortcut("j", modifiers: [.command, .shift])
        .disabled(first == nil)
    }
}

/// A walkthrough beside the game: PDF or text, with search, the last page kept, and an option to float above the game.
struct WalkthroughWindow: View {
    @Environment(AppModel.self) private var model
    let ref: WalkthroughRef
    @AppStorage("walkthroughFloats") private var floats = true
    @State private var query = ""
    @State private var findNext = 0

    var body: some View {
        let game = model.game(ref.game)
        let walkthrough = game?.walkthroughs.first { $0.id == ref.walkthrough }
        Group {
            if let game, let walkthrough {
                let url = model.walkthroughURL(game, walkthrough)
                switch walkthrough.kind {
                case .pdf:
                    PDFReader(url: url, page: walkthrough.page, query: query, findNext: findNext) { model.setWalkthroughPage($0, ref) }
                case .text:
                    ScrollView {
                        Text(verbatim: (try? String(contentsOf: url, encoding: .utf8)) ?? "")
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Space.lg)
                    }
                }
            } else {
                ContentUnavailableView("Walkthrough Removed", systemImage: "book.closed",
                                       description: Text("This walkthrough is no longer in RenChan."))
            }
        }
        .navigationTitle(walkthrough.map { "\($0.name) — \(game?.title ?? "")" } ?? String(localized: "Walkthrough"))
        .searchable(text: $query, prompt: Text("Find in Walkthrough"))
        .onSubmit(of: .search) { findNext += 1 }
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $floats) { Label("Float Above Game", systemImage: floats ? "pin.fill" : "pin") }
                    .help("Keep the walkthrough above the game's window")
            }
        }
        .background(WindowLevel(floats: floats))
        .frame(minWidth: 380, minHeight: 420)
    }
}

/// Puts the hosting window above other apps' windows, such as Ren'Py's, while `floats` is on.
/// Touches the window only when the level must change, so it never starts another layout pass.
private struct WindowLevel: NSViewRepresentable {
    let floats: Bool

    final class Probe: NSView {
        var floats = false { didSet { apply() } }
        override func viewDidMoveToWindow() { apply() }
        func apply() {
            guard let window else { return }
            let level: NSWindow.Level = floats ? .floating : .normal
            if window.level != level { window.level = level }
            if !window.collectionBehavior.contains(.fullScreenAuxiliary) { window.collectionBehavior.insert(.fullScreenAuxiliary) }
        }
    }

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.floats = floats
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {
        if probe.floats != floats { probe.floats = floats }
    }
}

/// PDFKit's view: opens at `page`, reports page changes, finds `query` each time `findNext` changes.
private struct PDFReader: NSViewRepresentable {
    let url: URL
    let page: Int
    let query: String
    let findNext: Int
    let pageChanged: (Int) -> Void

    final class Coordinator: NSObject {
        var pageChanged: (Int) -> Void = { _ in }
        var lastFind = 0
        @objc func changed(_ note: Notification) {
            guard let view = note.object as? PDFView, let page = view.currentPage, let document = view.document else { return }
            pageChanged(document.index(for: page))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = PDFDocument(url: url)
        if let target = view.document?.page(at: page) { view.go(to: target) }
        context.coordinator.pageChanged = pageChanged
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.changed), name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.pageChanged = pageChanged
        guard findNext != context.coordinator.lastFind else { return }
        context.coordinator.lastFind = findNext
        guard !query.isEmpty, let document = view.document else { return }
        let found = document.findString(query, fromSelection: view.currentSelection, withOptions: [.caseInsensitive])
            ?? document.findString(query, fromSelection: nil, withOptions: [.caseInsensitive])
        if let found {
            view.setCurrentSelection(found, animate: true)
            view.scrollSelectionToVisible(nil)
        } else {
            NSSound.beep()
        }
    }
}

/// The inspector's Walkthroughs section (S-032).
struct WalkthroughsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let game: Game

    var body: some View {
        Section("Walkthroughs") {
            if game.walkthroughs.isEmpty {
                Text("Drop a walkthrough PDF or text file here, such as the one a developer posts on itch.io, and read it beside the game.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(game.walkthroughs) { walkthrough in
                LabeledContent {
                    Button("Open") { openWindow(id: "walkthrough", value: WalkthroughRef(game: game.id, walkthrough: walkthrough.id)) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: walkthrough.name)
                        if walkthrough.kind == .pdf && walkthrough.page > 0 {
                            Text("Page \(walkthrough.page + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .contextMenu {
                    Button("Remove Walkthrough") { model.removeWalkthrough(walkthrough.id, from: game.id) }
                }
            }
            Button("Add Walkthrough…") { model.addWalkthroughWithPanel(to: game.id) }
                .help("Add a PDF or text walkthrough to read beside the game")
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls { model.addWalkthrough(url, to: game.id) }
            return !urls.isEmpty
        }
    }
}
