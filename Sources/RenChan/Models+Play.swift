import AppKit
import FileKit
import Foundation
import ProcessKit
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
        guard let game = game(id), !playing.contains(id), copying[id] == nil else { return }
        if game.pythonLine == nil {
            log.post(.warning, "\(game.title): no Ren'Py version found; trying Ren'Py \(RuntimeCatalog.python3)", source: "Play")
        }
        let version = runtimeVersion(for: game)
        guard let runtime = runtimes.first(where: { $0.version == version }) else {
            startDownload(version, then: id)
            return
        }
        let copy = playCopy(game)
        let hasCopy = FileManager.default.fileExists(atPath: copy.appending(path: "game").path)
        if !hasCopy, !FileClone.sameVolume(game.baseURL, copy), confirmFullCopy?.id != id {
            // Measured off the main thread: a big game on a slow disk takes a while to add up.
            let base = game.baseURL
            Task { confirmFullCopy = FullCopyRequest(id: id, size: await FolderSize.allocated(of: base)) }
            return
        }
        launch(game, on: runtime, allowFullCopy: confirmFullCopy?.id == id)
    }

    func confirmCopyAndPlay() {
        guard let request = confirmFullCopy, let game = game(request.id), let runtime = installedRuntime(for: game) else { return }
        launch(game, on: runtime, allowFullCopy: true)
        confirmFullCopy = nil
    }

    /// The plain copy, or the modded one when any mod is on.
    func playCopy(_ game: Game) -> URL { game.hasModsOn ? Store.moddedCopy(game.id) : Store.workingCopy(game.id) }

    /// Makes the working copy off the main thread when there isn't one yet, then starts the game.
    private func launch(_ game: Game, on runtime: Runtime, allowFullCopy: Bool) {
        let copy = playCopy(game)
        guard !FileManager.default.fileExists(atPath: copy.appending(path: "game").path) else {
            start(game, on: runtime, copy: copy, outcome: .reused)
            return
        }
        let id = game.id, base = game.baseURL, flag = StopFlag()
        copyStops[id] = flag
        copying[id] = CopyProgress(total: allowFullCopy ? (confirmFullCopy?.size ?? 0) : 0, full: allowFullCopy)
        Task {
            let result = await Task.detached { () -> Result<WorkingCopy.Outcome, any Error> in
                var copied: Int64 = 0
                var shown = Date.distantPast
                return Result {
                    try WorkingCopy.prepare(base: base, copy: copy, allowFullCopy: allowFullCopy, stop: { flag.isSet }) { bytes in
                        copied += bytes
                        // A few updates a second, not one per file.
                        guard Date.now.timeIntervalSince(shown) > 0.25 else { return }
                        shown = .now
                        let total = copied
                        Task { @MainActor in self.copying[id]?.copied = total }
                    }
                }
            }.value
            copying[id] = nil
            copyStops[id] = nil
            switch result {
            case .success(let outcome):
                guard let game = self.game(id) else { return }
                start(game, on: runtime, copy: copy, outcome: outcome)
            case .failure(let error) where error is CancellationError:
                log.post(.info, "Stopped copying \(game.title); nothing was left half-copied", source: "Play")
            case .failure(let error):
                log.post(.error, "Couldn't start \(game.title): \(error.localizedDescription)", source: "Play")
                notice = String(localized: "RenChan couldn't start \(game.title): \(error.localizedDescription)")
            }
        }
    }

    private func start(_ game: Game, on runtime: Runtime, copy: URL, outcome: WorkingCopy.Outcome) {
        do {
            if outcome != .reused { log.post(.info, "Made a working copy of \(game.title) (\(outcome == .cloned ? "APFS clone" : "full copy"))", source: "Play") }
            // S-014: the filter file goes in the copy only, and comes out when the filter is off.
            let tier = try FilterLoader.install(game.filter, runtime: runtime.version, copy: copy, custom: customFilters)
            if let filter = game.filter {
                if let file = filter.custom, !customFilters.contains(where: { $0.file == file }) {
                    log.post(.warning, "\(game.title): the filter \(file) is no longer in RenChan's Filters folder; playing without it", source: "Play")
                } else if tier == .unsupported {
                    log.post(.warning, "\(game.title): Ren'Py \(runtime.version) can't show filters; playing without \(filter.name)", source: "Play")
                } else {
                    log.post(.info, "\(game.title): filter \(filter.name) at \(Int(filter.strength * 100))% (\(tier == .camera ? "camera" : "layer transform"))", source: "Play")
                }
            }
            var environment = try prepareMods(game, copy: copy)
            // S-022: Ren'Py's console and fast skip, in the copy only.
            try DevToolsLoader.install(game.devTools, copy: copy)
            // S-039: the language it starts in.
            try LanguageLoader.install(game.language, copy: copy)
            backUpBeforePlay(game)
            if Store.isOverridden { environment["HOME"] = Store.renpyHome.path }
            let plan = LaunchPlan(runtime: runtime, copy: copy, outputFile: Store.gameFolder(game.id).appending(path: "run.log"),
                                  environment: environment)
            let started = Date()
            let id = game.id
            let process = try plan.start { output in
                let status = LaunchPlan.exitCode(of: output)
                Task { @MainActor in self.finished(id, status: status, plan: plan, started: started) }
            }
            processes[game.id] = process
            runningCopies[game.id] = copy
            playing.insert(game.id)
            if tier != .unsupported { startFilterWatch() }
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
        runningCopies[id] = nil
        playing.remove(id)
        let stopped = stopRequested.remove(id) != nil
        let seconds = PlaySession.end(at: .now, file: Store.sessionFile(id))
        update(id) { $0.playtime += seconds }
        guard let game = game(id) else { return }
        if game.saveDirectory == nil, let found = SaveFolder.changed(since: started, root: Store.saveRoot).first {
            update(id) { $0.saveDirectory = found }
            log.post(.info, "\(game.title) keeps its saves in ~/Library/RenPy/\(found)", source: "Library")
        }
        let result = LaunchResult.read(copy: plan.copy, outputFile: plan.outputFile, exitCode: status, started: started, stopped: stopped)
        // S-027: every run goes into the compatibility report.
        let errorLine = result.failed ? (result.traceback ?? result.outputTail).split(separator: "\n").last.map(String.init) : nil
        update(id) {
            $0.record(RunRecord(date: started, runtime: plan.runtime.version, outcome: result.failed ? .failed : .worked, exitCode: status,
                                seconds: seconds, modded: plan.copy.lastPathComponent == Store.moddedCopy(id).lastPathComponent,
                                filter: game.filter?.name, error: errorLine))
        }
        guard result.failed else {
            log.post(.info, stopped ? "Stopped \(game.title)" : "\(game.title) quit", source: "Play")
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

    /// S-038: the saves are backed up before each launch when they changed since the last backup; the newest five stay.
    static let backupBeforePlayKey = "saves.backupBeforePlay"

    func backUpBeforePlay(_ game: Game) {
        guard UserDefaults.standard.object(forKey: Self.backupBeforePlayKey) as? Bool ?? true,
              let saves = savesFolder(game, modded: game.hasModsOn) else { return }
        do {
            if let backup = try SaveBackups.backUpBeforePlay(saves: saves, into: Store.backupsFolder(game.id), modded: game.hasModsOn) {
                backupRevision += 1
                log.post(.info, "Backed up \(backup.contents) of \(game.title) before playing", source: "Saves")
            }
        } catch {
            log.post(.warning, "Couldn't back up the saves of \(game.title) before playing: \(error.localizedDescription)", source: "Saves")
        }
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
        // While the copy is made, Stop cancels it.
        if let flag = copyStops[id] {
            flag.set()
            return
        }
        guard let process = processes[id] else { return }
        stopRequested.insert(id)
        process.stop()
    }

    /// The game's runtime menu: nil goes back to RenChan's own pick, which also undoes Try Exact Version.
    func setRuntime(_ version: String?, for id: Game.ID) {
        guard let game = game(id), game.runtimeOverride != version else { return }
        update(id) { $0.runtimeOverride = version }
        log.post(.info, version.map { "\(game.title) plays on Ren'Py \($0) from now on" }
                        ?? "\(game.title) plays on Ren'Py \(runtimeVersion(for: self.game(id) ?? game)) again, RenChan's own pick", source: "Play")
    }

    func runtimeChoices(_ game: Game) -> RuntimeChoices {
        RuntimeCatalog.choices(version: game.version, pythonLine: game.pythonLine, override: game.runtimeOverride, installed: runtimes.map(\.version))
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

    /// Downloads a runtime. `game` plays once its runtime is in, even when Play came during another download:
    /// it waits its turn, and the next missing runtime downloads after this one.
    func startDownload(_ version: String, then game: Game.ID? = nil) {
        if let game, !waitingToPlay.contains(game) { waitingToPlay.append(game) }
        if let current = download {
            if current.version != version {
                log.post(.info, "Ren'Py \(version) downloads after Ren'Py \(current.version)", source: "Runtimes")
            }
            return
        }
        download = DownloadState(version: version)
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
                self.downloadEnded(version, error: nil)
            } catch {
                self.downloadEnded(version, error: error)
            }
        }
    }

    /// The end of a download: games whose runtime is now in start, then the next missing runtime downloads.
    /// Cancel drops every waiting game; a failure drops only the ones that needed that version.
    func downloadEnded(_ version: String, error: (any Error)?) {
        let size = download?.received ?? 0
        download = nil
        runtimes = runtimeStore.installed()
        switch error {
        case nil:
            log.post(.info, "Installed Ren'Py \(version) (\(size.bytesText)); checksum matches", source: "Runtimes")
        case is CancellationError:
            waitingToPlay.removeAll()
            log.post(.info, "Cancelled the Ren'Py \(version) download", source: "Runtimes")
            return
        case let error?:
            waitingToPlay.removeAll { id in game(id).map { runtimeVersion(for: $0) == version } ?? true }
            downloadFailed(version, error)
        }
        let ready = waitingToPlay.filter { id in game(id).map { installedRuntime(for: $0) != nil } ?? false }
        waitingToPlay.removeAll { id in ready.contains(id) || game(id) == nil }
        for id in ready { play(id) }
        if let next = waitingToPlay.first.flatMap({ game($0) }) {
            startDownload(runtimeVersion(for: next))
        }
    }

    private func downloadFailed(_ version: String, _ error: any Error) {
        let words: String
        switch error {
        case RuntimeDownload.Failure.checksumMismatch:
            words = String(localized: "The download of Ren'Py \(version) didn't match renpy.org's checksum, so it was deleted. Try again later.")
        case RuntimeDownload.Failure.http(let code):
            words = String(localized: "renpy.org has no Ren'Py \(version) to download (error \(code)).")
        default:
            words = String(localized: "Ren'Py \(version) couldn't be downloaded: \(error.localizedDescription)")
        }
        log.post(.error, "Ren'Py \(version) download failed: \(error)", source: "Runtimes")
        notice = words
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
