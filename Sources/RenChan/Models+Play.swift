import AppKit
import Foundation
import RenChanKit

/// Getting a runtime and playing a game (S-003, S-004, S-005).
extension AppModel {
    /// The runtime version a game plays on.
    func runtimeVersion(for game: Game) -> String {
        RuntimeCatalog.choose(version: game.version, pythonLine: game.pythonLine, override: game.runtimeOverride)
            ?? RuntimeCatalog.python3
    }

    func installedRuntime(for game: Game) -> Runtime? {
        runtimes.first { $0.version == runtimeVersion(for: game) }
    }

    /// Play: downloads the runtime first when it's missing, makes the working copy, starts Ren'Py.
    func play(_ id: Game.ID) {
        guard let game = game(id), !playing.contains(id) else { return }
        if game.pythonLine == nil {
            log.post(.warning, "\(game.title): no Ren'Py version found; trying Ren'Py \(RuntimeCatalog.python3)", source: "Play")
        }
        let version = runtimeVersion(for: game)
        guard let runtime = runtimes.first(where: { $0.version == version }) else {
            startDownload(version, then: id)
            return
        }
        let copy = Store.workingCopy(id)
        let hasCopy = FileManager.default.fileExists(atPath: copy.appending(path: "game").path)
        if !hasCopy, !WorkingCopy.sameVolume(game.baseURL, copy), confirmFullCopy?.id != id {
            confirmFullCopy = FullCopyRequest(id: id, size: WorkingCopy.size(of: game.baseURL))
            return
        }
        launch(game, on: runtime, allowFullCopy: confirmFullCopy?.id == id)
    }

    func confirmCopyAndPlay() {
        guard let request = confirmFullCopy, let game = game(request.id), let runtime = installedRuntime(for: game) else { return }
        launch(game, on: runtime, allowFullCopy: true)
        confirmFullCopy = nil
    }

    private func launch(_ game: Game, on runtime: Runtime, allowFullCopy: Bool) {
        let copy = Store.workingCopy(game.id)
        do {
            let outcome = try WorkingCopy.prepare(base: game.baseURL, copy: copy, allowFullCopy: allowFullCopy)
            if outcome != .reused { log.post(.info, "Made a working copy of \(game.title) (\(outcome == .cloned ? "APFS clone" : "full copy"))", source: "Play") }
            // S-014: the filter file goes in the copy only, and comes out when the filter is off.
            let tier = try FilterLoader.install(game.filter, runtime: runtime.version, copy: copy)
            if let filter = game.filter {
                if tier == .unsupported {
                    log.post(.warning, "\(game.title): Ren'Py \(runtime.version) can't show filters; playing without \(filter.filter.rawValue)", source: "Play")
                } else {
                    log.post(.info, "\(game.title): filter \(filter.filter.rawValue) at \(Int(filter.strength * 100))% (\(tier == .camera ? "camera" : "layer transform"))", source: "Play")
                }
            }
            var environment: [String: String] = [:]
            if Store.isOverridden { environment["HOME"] = Store.renpyHome.path }
            let plan = LaunchPlan(runtime: runtime, copy: copy, outputFile: Store.gameFolder(game.id).appending(path: "run.log"),
                                  environment: environment)
            let process = try plan.makeProcess()
            let started = Date()
            let id = game.id
            process.terminationHandler = { @Sendable finished in
                let status = finished.terminationStatus
                Task { @MainActor in self.finished(id, status: status, plan: plan, started: started) }
            }
            try process.run()
            processes[game.id] = process
            playing.insert(game.id)
            PlaySession.begin(at: started, file: Store.sessionFile(game.id))
            update(game.id) { $0.markPlayed(at: started) }
            let rosetta = runtime.isUniversal ? "" : " under Rosetta"
            log.post(.info, "Started \(game.title) on Ren'Py \(runtime.version)\(rosetta)", source: "Play")
        } catch {
            log.post(.error, "Couldn't start \(game.title): \(error.localizedDescription)", source: "Play")
            notice = String(localized: "RenChan couldn't start \(game.title): \(error.localizedDescription)")
        }
    }

    private func finished(_ id: Game.ID, status: Int32, plan: LaunchPlan, started: Date) {
        processes[id] = nil
        playing.remove(id)
        let seconds = PlaySession.end(at: .now, file: Store.sessionFile(id))
        update(id) { $0.playtime += seconds }
        guard let game = game(id) else { return }
        if game.saveDirectory == nil, let found = SaveFolder.changed(since: started, root: Store.saveRoot).first {
            update(id) { $0.saveDirectory = found }
            log.post(.info, "\(game.title) keeps its saves in ~/Library/RenPy/\(found)", source: "Library")
        }
        let result = LaunchResult.read(copy: plan.copy, outputFile: plan.outputFile, exitCode: status, started: started)
        guard result.failed else {
            log.post(.info, "\(game.title) quit", source: "Play")
            return
        }
        let file = ["traceback.txt", "errors.txt"].map { plan.copy.appending(path: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        log.post(.error, "\(game.title) quit with an error (exit \(status)) on Ren'Py \(plan.runtime.version)", source: "Play")
        launchError = LaunchFailure(game: id, title: game.title,
                                    text: result.traceback ?? result.outputTail,
                                    tracebackFile: result.traceback == nil ? plan.outputFile : file,
                                    exactVersion: RuntimeCatalog.exactAlternative(version: game.version, chosen: plan.runtime.version))
    }

    /// Runs RenChan didn't see end (it quit while a game played) count up to the game's last log line.
    func recoverSessions() {
        for game in games {
            guard let seconds = PlaySession.recover(file: Store.sessionFile(game.id),
                                                    lastActivity: Store.gameFolder(game.id).appending(path: "run.log")) else { continue }
            update(game.id) { $0.playtime += seconds }
            log.post(.info, "Counted \(Int(seconds / 60)) min of \(game.title) played while RenChan was closed", source: "Play")
        }
    }

    func stop(_ id: Game.ID) {
        processes[id]?.terminate()
    }

    /// From the error sheet: play again on the game's exact Ren'Py version.
    func tryExactVersion(_ failure: LaunchFailure) {
        launchError = nil
        guard let version = failure.exactVersion else { return }
        update(failure.game) { $0.runtimeOverride = version }
        log.post(.info, "Trying \(failure.title) on its own Ren'Py \(version)", source: "Play")
        play(failure.game)
    }

    // MARK: Runtimes (S-003)

    func startDownload(_ version: String, then game: Game.ID? = nil) {
        guard download == nil else { return }
        download = DownloadState(version: version, then: game)
        log.post(.info, "Downloading Ren'Py \(version) from renpy.org", source: "Runtimes")
        let store = runtimeStore
        downloadTask = Task {
            do {
                try await RuntimeDownload.install(version, into: store) { received, total in
                    Task { @MainActor in
                        self.download?.received = received
                        self.download?.total = total
                    }
                }
                let size = self.download?.received ?? 0
                self.runtimes = store.installed()
                self.log.post(.info, "Installed Ren'Py \(version) (\(size.bytesText)); checksum matches", source: "Runtimes")
                let next = self.download?.then
                self.download = nil
                if let next { self.play(next) }
            } catch is CancellationError {
                self.download = nil
                self.log.post(.info, "Cancelled the Ren'Py \(version) download", source: "Runtimes")
            } catch {
                self.download = nil
                let words: String
                switch error {
                case RuntimeDownload.Failure.checksumMismatch:
                    words = String(localized: "The download of Ren'Py \(version) didn't match renpy.org's checksum, so it was deleted. Try again later.")
                case RuntimeDownload.Failure.http(let code):
                    words = String(localized: "renpy.org has no Ren'Py \(version) to download (error \(code)).")
                default:
                    words = String(localized: "Ren'Py \(version) couldn't be downloaded: \(error.localizedDescription)")
                }
                self.log.post(.error, "Ren'Py \(version) download failed: \(error)", source: "Runtimes")
                self.notice = words
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    func games(using runtime: Runtime) -> [Game] {
        games.filter { runtimeVersion(for: $0) == runtime.version }
    }

    func removeRuntime(_ version: String) {
        confirmRemoveRuntime = nil
        guard let runtime = runtimes.first(where: { $0.version == version }) else { return }
        do {
            try runtimeStore.remove(runtime)
            runtimes = runtimeStore.installed()
            log.post(.info, "Removed Ren'Py \(version)", source: "Runtimes")
        } catch {
            notice = error.localizedDescription
        }
    }
}
