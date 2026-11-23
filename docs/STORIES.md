# RenChan — User stories

Source of truth for what RenChan builds. Brief: `docs/BRIEF.md`. Research: `docs/research/`.
The roadmap is the "RenChan Roadmap" project in Thimble. Snapshot pages are named in `Screens:`.
Test games: `Tests/Fixtures/` holds tiny generated Ren'Py games (one per version line); `[live]` lines run against real games in `~/Games/RenPy`.

---

## M1 Play any Ren'Py game (0.1.0)

### S-001 Add a game
As the user, I drop a game folder, a `.app` or a zip on the window (or use File › Add Game…, ⌘O), and it appears in the library with its title and icon.
Screens: library-empty, library
UX: empty library says "Drop a Ren'Py game here" with an Add Game… button; a zip is unpacked into RenChan's folder after showing its size; a folder that isn't a Ren'Py game is refused in one line naming what was missing (`game/`).
Acceptance:
- [unit] Finds the base folder in a plain folder, a `.app` (`Contents/Resources/autorun`) and a zip with one top folder.
- [unit] Zip extraction refuses paths that escape the target (Zip Slip).
- [self] Dropping each fixture adds one game; dropping it again doesn't add a duplicate.
Status: done

### S-002 Detect the Ren'Py version
As the user, I see each game's Ren'Py version and whether it is Python 2 or 3 in its details.
Screens: game-details
Depends: S-001
Acceptance:
- [unit] Reads `vc_version.py` + `__init__.py`, then `log.txt`, `script_version.txt`, `lib/` names, then the `.rpyc` header, in that order, and says which one it used.
- [unit] Every fixture version line (6.99, 7.4, 7.8, 8.0, 8.3, 8.6) is detected with the right Python line.
- [live] 20 real games detected; none with the wrong Python line.
Waiting: the [live] line needs 20 real games (Plan › "Pick 20 real test games").
Status: doing

### S-003 Get a runtime
As the user, the first time I play a game, RenChan downloads the runtime it needs from renpy.org with progress, checks it, and keeps it for other games.
Screens: runtime-download, runtimes
Depends: S-002
UX: a sheet with the version, size and progress; Cancel keeps nothing half-done; the Runtimes page lists each runtime, its size, the games using it and Remove.
Acceptance:
- [unit] Picks 7.8.7 for Python 2 games from 7.4 on, the newest 8.x for Python 3 games, and the exact version for older games.
- [unit] A checksum mismatch deletes the download and reports it.
- [live] Downloads and unpacks 7.8.7 and 8.6.1; their Python starts. (`RENCHAN_LIVE=1 swift test --filter Live`, passed 2026-11-22)
Status: done

### S-004 Play a game
As the user, I press Play (⌘Return) and the game opens natively, running from a working copy so the original is never changed.
Screens: library, game-details
Depends: S-003
UX: the button reads Play, then Playing… with a Stop item in the Game menu; Intel-only runtimes show "Runs under Rosetta" before the first launch.
Acceptance:
- [unit] The working copy is an APFS clone; on another volume, RenChan asks before a full copy.
- [self] A fixture game launches, writes its `.rpyc` files only into the copy, and the original's checksum is unchanged.
- [live] A Windows-only Ren'Py 8 game and a 7.x game play on Apple Silicon.
Waiting: the [live] line needs a real Windows-only Ren'Py 8 game and a 7.x game.
Status: doing

### S-005 See why a game didn't start
As the user, when a game quits with an error, RenChan shows Ren'Py's traceback and log, with Copy and Show in Finder, and offers to try the game's exact Ren'Py version.
Screens: launch-error
Depends: S-004
Acceptance:
- [self] A fixture with a broken script shows the traceback with file and line.
- [unit] "Try exact version" is offered only when the default runtime differs from the detected one.
Status: done

### S-006 Library grid and list
As the user, I browse games as a cover grid or a list (⌘1 / ⌘2), search by title (⌘F), and sort by title, added, or last played.
Screens: library, library-list
Depends: S-001
Acceptance:
- [snap] Grid and list in light and dark, English and French.
- [self] Search narrows as I type; sort survives a relaunch.
Status: done

### S-007 Open saves
As the user, I open a game's save folder from its details, and RenChan shows where the saves are and how many there are.
Screens: game-details
Depends: S-002
Acceptance:
- [unit] Finds `config.save_directory` from `options.rpy`/`.rpyc` or the folder Ren'Py created.
Status: done

### S-008 Remove a game
As the user, I remove a game from the library; RenChan deletes its working copy and asks separately before touching saves. The original is never deleted.
Depends: S-004
Acceptance:
- [self] Removing deletes the copy, keeps saves, keeps the original.
Status: done

## M2 A library worth keeping (0.2.0)

### S-009 Playtime and last played
As the user, I see how long I've played each game and when I last played it.
Acceptance:
- [unit] Time counts from launch to quit; a crash still records it.
Status: todo

### S-010 Details from VNDB
As the user, I match a game to VNDB and get its cover, developer, release date and description, and my own edits stay when I refresh.
Acceptance:
- [unit] A title search returns candidates; a manual cover is kept on refresh.
- [live] Matches three known games.
Status: todo

### S-011 Labels, rating and notes
As the user, I add labels, a rating and notes to a game, and filter the library by label, rating, or status (not started, playing, finished).
Status: todo

### S-012 Back up saves
As the user, I back up a game's saves with one click, see past backups by date, and restore one.
Acceptance:
- [unit] A restore keeps a backup of the saves it replaces.
Status: todo

### S-013 Update a game to a new version
As the user, I point a game at its new version's folder or zip; its labels, playtime, filter and mods carry over.
Status: todo

## M3 Screen filters (0.3.0)

### S-014 Turn on a filter
As the user, I pick a filter for a game (Sharpen, CRT, Night warmth, Grayscale, Protanopia, Deuteranopia, Tritanopia) and it applies the next time it plays.
Acceptance:
- [unit] On 7.7+/8.2+ the loader sets `config.layer_transforms[None]`; on 7.4.6–7.6 it uses `camera`; below 7.4 the picker is off and says why.
- [live] Each filter shows on an 8.6 and a 7.8 game.
Status: todo

### S-015 Tune a filter live
As the user, I change a filter's strength while the game runs and see it change in the game.
Acceptance:
- [unit] RenChan writes parameters to a file the loader reads each second.
Status: todo

### S-016 Add my own shader
As the user, I add a `.glsl` fragment shader with a small JSON header and it shows up as a filter.
Status: todo

## M4 Mods (0.4.0)

### S-017 Install a mod
As the user, I drop a mod (zip, `.rpa`, `.rpy`) on a game and it appears in that game's Mods list, stored by RenChan, not in the game.
Acceptance:
- [unit] Zip Slip is refused; a zip's `game/` folder is found at any depth.
Status: todo

### S-018 Turn mods on and off, and order them
As the user, I switch each mod on or off and drag to set load order; the next launch uses exactly that set.
Acceptance:
- [self] Turning a mod off removes its files from the working copy before launch.
Status: todo

### S-019 Conflicts
As the user, I'm warned when two enabled mods replace the same file or screen, and told which one wins.
Status: todo

### S-020 Modded saves stay apart
As the user, modded play keeps its own saves by default, and my saves are backed up before the first modded launch.
Acceptance:
- [unit] Launch sets `RENPY_PATH_TO_SAVES` to the game's modded save folder when any mod is on.
Status: todo

### S-021 Install URM
As the user, I add my own copy of Universal Ren'Py Mod once and turn it on for any game with one switch.
Status: todo

## M5 Mod API and tools (0.5.0)

### S-022 Developer console
As the user, I switch on Ren'Py's console (Shift+O) and fast skip for a game.
Status: todo

### S-023 RenChan mod API
As a mod author, I write a mod with a `renchan-mod.json` manifest and the `renchan` module (on start, after load, menu entry, keymap, own state kept outside saves) that works on Ren'Py 7.4+ and 8.x.
Acceptance:
- [unit] The sample mod loads on the 7.8 and 8.6 fixtures.
- Docs in `docs/MODDING.md`.
Status: todo

### S-024 New mod from a template
As a mod author, I create a mod for a game from a template and open it in my editor; RenChan reloads it on relaunch.
Status: todo

## M6 Ready to share (1.0.0)

### S-025 Signed, notarized, updates
As the user, I download a notarized RenChan that updates itself (Sparkle).
Status: todo

### S-026 French everywhere
As the user, every screen reads well in French.
Status: todo

### S-027 Compatibility report
As the user, I see per game whether it ran, on which runtime, and can export that for a bug report.
Status: todo

## Later
- F95zone and itch.io update checks with alerts.
- Import a library from F95Checker.
- Save viewer and editor (local only).
- Download Windows-only Steam games with SteamCMD.
- `renchan` CLI and MCP server.
- Windows and Linux apps reusing `Resources/RenChanRuntime/`.

## Dropped
- A Rust reimplementation of Ren'Py: real games need Ren'Py's own Python and API.
- Wine fallback: Whisky is dead and the native runtime covers Ren'Py games.
