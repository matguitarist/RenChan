# RenChan — Fix log

## 2026-11-25 Picking a filter while the game ran did nothing on Ren'Py 7.4.6 to 8.1

Symptom: on games that run on Ren'Py 7.4.6–7.6 or 8.0–8.1, choosing a filter in the inspector during play changed nothing, while the inspector said "Changes show in the game within a second". A game started with a filter couldn't switch to another one either; RenChan reported "'renpy.gl2.gl2draw.GL2Draw' object has no attribute 'shader_cache'".
Cause: two things. On this "camera" tier the loader went into the copy only when a filter was set at launch, so a game started without one had nothing reading the state file. And the loader checked a new filter with `renpy.display.draw.shader_cache`, which is public only from 8.2 and 7.7; before that it's a private Cython attribute, so every live switch failed the check and kept the old filter.
Fix: `FilterLoader.install` puts the loader in on every tier that can draw a filter. On the camera tier it leaves the game's own camera alone until a filter is picked, which a periodic callback notices within half a second. The check finds Ren'Py's `ShaderCache` once among Python's objects when the attribute is private.
Test: Live `aFilterPickedDuringPlayShowsOnOlderRenPy` on real 7.6.3 and 8.1.3 (fails on the old code); `theLoaderUsesLayerTransformsOrCamera` and `theFilterCanChangeWhileTheGamePlays` updated for the new rule; `aFilterChangesWhatTheGameShows` still passes on 7.8.7 and 8.6.1.
Rule: test a feature on every runtime tier it claims to support, not only the newest; an engine's internals (here a private attribute) differ between versions, so reach them with a fallback and a test per version.

## 2026-11-25 Play did nothing while another Ren'Py was downloading

Symptom: while Ren'Py 8.6.1 downloaded for one game, Play on a second game (Game › Play, Command-Return, or opening it from the Finder) did nothing, and the second game didn't start after the download either. No message said why.
Cause: `startDownload` returned at once when a download was under way, and the download remembered one game to play after it (`DownloadState.then`), so any other Play was dropped.
Fix: `waitingToPlay` keeps every game that pressed Play, in order. `downloadEnded` starts each game whose runtime is now in, then downloads the next missing runtime; a failure drops only the games that needed that version, and Cancel drops them all. The download sheet names the games that start afterwards.
Test: self-test "S-003 Play during a download waits its turn instead of being dropped", "when the download ends, every game whose Ren'Py is in starts" (both fail on the old code) and "a failed download drops its waiting games and says so"; snapshot `runtime-download`.
Rule: a request that arrives while the app is busy is queued or refused out loud, never ignored; one "then do this" slot is a queue of length one that drops the rest.

## 2026-11-25 A full copy froze RenChan, and a copy cut short was played as if complete

Symptom: Play on a game from another disk, after "Copy and Play", showed the spinning cursor for as long as the copy took (minutes for a 15 GB game). Force-quitting then left a working copy that every later Play reused, and the game crashed on its missing files.
Cause: `launch` ran `WorkingCopy.prepare` on the main thread, and `play` measured the game's size there too. FileKit's `FileClone.copy` writes straight into the target, `game/` first, and only cleans up when it throws; `prepare` took any copy with a `game/` folder as finished.
Fix: `WorkingCopy.prepare` makes the copy in a hidden `.<name>.partial` folder and renames it only when complete, throws away a leftover one, and can be stopped between files. The app makes the copy in a detached task with progress under the cover, Cancel Copy (and Command-Period) stops it, and the size for the question is measured off the main thread.
Test: `aCopyCutShortIsNeverTakenForAFinishedOne`; self-test "Play makes the working copy in the background, without blocking"; snapshot `library-copying`.
Rule: build anything that takes more than an instant to make under a temporary name and rename it into place when done, so its final name means "complete"; and never do disk work proportional to the person's data on the main thread.

## 2026-11-25 Stopping a game showed an error and counted as a failed run

Symptom: Game › Stop opened the error sheet ("quit with an error (exit 15)") with the run's output, and the compatibility report listed the run as failed on that runtime.
Cause: Stop ends Ren'Py with SIGTERM, and `LaunchResult.failed` counted any non-zero exit as an error; `finished` had no way to know the signal came from the person.
Fix: `stop` records the game in `stopRequested`; `finished` passes `stopped` to `LaunchResult.read`, and a stopped run fails only when the game wrote a traceback. It logs "Stopped <game>" and counts as worked.
Test: `aStoppedGameRecordsTheSignalAsBefore` (stopped is not failed, a traceback still is); self-test "S-004 Stop ends the game without an error sheet" (fails on the old code).
Rule: when the app ends a process itself, remember that it asked before reading the exit status; a signal the app sent is never the program's error.

## 2026-11-25 Removing or updating a game lost the saves made with mods and the mods' state

Symptom: after Remove from Library, every save made with mods on was gone for good, though the dialog said "your saves stay where they are". After Update Game, a mod's `renchan.state` (settings, trackers) started empty.
Cause: RenChan kept "Modded Saves", "Walkthroughs" and the mod API's `renchan_state` inside folders it treats as its own and disposable: Remove deletes the game's whole folder, and an update deletes the modded copy that held `renchan_state`.
Fix: `remove` moves what holds the person's files (`RemovedGame.keepAside`) to the Trash before deleting the rest, and keeps the game when that fails; `ModAPI.install(copy:state:)` keeps mod state in the game's "Mod State" folder, outside the copy, and moves old state there once. Test runs trash into the test's data folder (`Store.trash`).
Test: `removingAGameKeepsAsideOnlyFoldersWithFiles`, `modStateLivesOutsideTheCopyAndOldStateMovesThere`; self-test "removing a game puts its modded saves in the Trash" and "a mod's saved state outlives an update".
Rule: never keep what a person made inside a folder the app deletes and rebuilds; before deleting a folder, list what in it can't be made again and put that somewhere the person can get it back.

## 2026-11-25 A backup of the modded saves was restored over the game's own saves

Symptom: restoring a "Before editing a save" backup taken in the Modded Saves view replaced the regular saves with the modded ones. With every mod off, editing a save in the Modded view changed the regular save of the same slot, after backing up the modded folder.
Cause: a game's saves have two homes (~/Library/RenPy and RenChan's Modded Saves), but a backup didn't record which one it came from, so restore always wrote to the regular one; and the save tool only pointed Ren'Py at the modded saves when `prepareMods` set it up, which it skips when no mod is on.
Fix: `SaveBackup.modded` is written in backup.json (old backups read as regular saves), restore and its own safety backup use that home, before-play backups compare and prune each home apart, and `runSaveTool` always sets `RENPY_PATH_TO_SAVES` for modded saves. The Backups sheet marks modded backups with a puzzle piece.
Test: `aBackupOfModdedSavesSaysSoAndOldBackupsDont`, `aNewerModdedBackupDoesntSkipTheBackupBeforePlay`; self-test "a backup of the modded saves restores into the modded saves" and "with every mod off, a Modded save is read from the modded saves" (both fail on the old code).
Rule: when the same kind of data lives in two places, every copy of it records where it came from, and every action that reads or writes it names the place instead of falling back to the usual one.

## 2026-11-24 A damaged save could close RenChan

The save reader cut each file name out of a save's zip directory without checking that the name ended inside the file, and it force-unwrapped the input of an empty deflated entry. A save cut short (Ren'Py still writing it, a full disk) could end the app as soon as the Saves window opened, since the window reads every save. The reader now rejects a name past the end of the file and returns nothing for an empty entry.
Test: `damagedSavesAreRejectedNotCrashed`.
Rule: a parser of files on disk checks every length it reads before it uses it; a file can always be cut short.

## 2026-11-23 Eden's gallery lists couldn't be changed

Eden keeps its gallery in persistent lists, `renders` (45) and `scenes` (15), of dictionaries such as `{'id': 'PizzaBoxRender', 'unlocked': False, 'name': 'Hawaiian Dream'}`. The editor showed each list as one read-only value ("RevertableList (45)"), so nothing could be unlocked. The save tool now opens lists and dictionaries of plain values into paths like `renders[0].unlocked`, notes the item's name, and writes a change into the same object.
Test: `persistentDataIsReadChangedAndUnlocked` (Live) changes values inside a list of dictionaries and a dictionary on 7.8.7 and 8.6.1.
Rule: the state a person wants to change is often nested; an editor of game data should reach plain values wherever they sit, not only at the top.

## 2026-11-23 Unlock All did nothing in Cosy Cafe's gallery

Unlock All worked for Eternum, but Cosy Cafe's gallery stayed locked even though RenChan marked 20,262 images as seen. Cosy Cafe doesn't use Ren'Py's Gallery: it checks its own persistent values, such as `akari_img_main32_50_unlocked` and `gallery_lucy1`, which is why turning one on by hand worked. The persistent page now finds a game's own unlock values (on/off values named with "unlock" or "gallery") and turns them all on with one button; a search can turn on any other set.
Test: `aGamesOwnUnlockFlagsAreFound`; the self-test reads the fixture's unlock values.
Rule: an "unlock everything" feature has to meet games where they keep their state; check a few real games before assuming they all use the engine's built-in mechanism.

## 2026-11-23 Switching to CRT, Sharpen or FSR while playing said the filter didn't compile

In Eternum, a change of filter during play worked for Grayscale but CRT, Sharpen and FSR Upscale showed "The game kept the last filter: this one didn't compile. Input of fragment shader 'v_tex_coord' not written by vertex shader". The loader checked a new filter by compiling its shader alone, but Ren'Py always draws it together with `renpy.texture`, whose vertex shader writes `v_tex_coord`. Every filter that reads nearby pixels failed that check, even though it would have drawn fine. The loader now compiles `(name, "renpy.texture")`, the same set Ren'Py draws.
Test: `aFilterChangesWhatTheGameShows` (Live) now also switches to CRT during play; `theLoaderUsesLayerTransformsOrCamera` checks the pair.
Rule: a check before use must test exactly what will be used (here, the same shader set Ren'Py draws), or it rejects good input and lets bad input through.

## 2026-11-22 A download that isn't a zip showed unzip's raw error

Dropping `cosy-cafe-mac.zip` showed several lines of zipinfo output. The file was 118 bytes of XML: itch.io's download links expire after 60 seconds, and Safari saved the "Request has expired" error page under the zip's name. RenChan now checks the zip signature (PK) before asking to unpack, and says the file isn't a zip, its size, and to download again.
Test: `aDownloadThatIsntAZipIsRefusedPlainly` in LocatorTests.
Rule: check what a file is by its first bytes before handing it to a tool, and turn a tool's raw error into what happened and what to do.

## 2026-11-22 Snapshots crashed in a layout loop after the owner tiled the window
- Symptom: `tools/snap.sh` ended with exit 133 (SIGTRAP in -[NSWindow _postWindowNeedsUpdateConstraints]) on every page, even on code that had passed minutes before. The app itself ran fine.
- Cause: snapshot mode reads the owner's real `NSWindow Frame main`, which carried macOS tiling state; a tiled window restored into the snapshot run's appearance switches loops AppKit's constraint passes. Snapshot runs also rewrote the owner's saved frame.
- Fix: `snap.sh` exports the app's defaults, removes the frame for the run, and imports them back afterwards.
- Rule: a test or snapshot run must not read or write the owner's UI state either: set aside and restore the app's defaults around it, like the store and HOME.
