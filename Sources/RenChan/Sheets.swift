import AppKit
import RenChanKit
import SwiftUI

/// Downloading a runtime (S-003): version, progress, Cancel.
struct DownloadSheet: View {
    @Environment(AppModel.self) private var model
    let initial: DownloadState
    /// The live progress; the sheet item only carries the version.
    private var state: DownloadState { model.download ?? initial }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text("Downloading Ren'Py \(state.version)").font(.title3.weight(.semibold))
            Text("From renpy.org, once. Every game that plays on Ren'Py \(state.version) uses it.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let total = state.total, total > 0 {
                ProgressView(value: Double(state.received), total: Double(total))
                Text("\(state.received.bytesText) of \(total.bytesText)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                Text(state.received.bytesText).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.cancelDownload() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 480)
        .noInitialFocus()
    }
}

/// A game that quit with an error (S-005): Ren'Py's traceback, Copy, Show in Finder, Try the exact version.
struct LaunchErrorSheet: View {
    @Environment(AppModel.self) private var model
    let failure: LaunchFailure

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Label {
                Text("\(failure.title) quit with an error").font(.title3.weight(.semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text(failure.exactVersion.map { String(localized: "This is what Ren'Py wrote when it stopped. The game was made with Ren'Py \($0): playing it on that version may help.") }
                 ?? String(localized: "This is what Ren'Py wrote when it stopped."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(verbatim: failure.text.isEmpty ? String(localized: "Ren'Py wrote nothing.") : failure.text)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Space.md)
            }
            .frame(height: 260)
            .cardBackground(Radius.control)
            HStack(spacing: Space.sm) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(failure.text, forType: .string)
                }
                if let file = failure.tracebackFile {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                }
                Spacer()
                if let exact = failure.exactVersion {
                    Button("Try Ren'Py \(exact)") { model.tryExactVersion(failure) }
                }
                Button("Close") { model.launchError = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.xl)
        .frame(width: 640)
        .noInitialFocus()
    }
}
