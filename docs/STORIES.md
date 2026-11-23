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
Screens: game-details, library-list
UX:
- Flow: Play → the game quits, even with an error → the inspector's Playtime and Last Played update; the list has a Playtime column; Sort › Playtime.
- Surface: inline, in a "Play" section of the inspector and a list column (values on screen, nothing to open).
- States: never played "Never"; while playing "Playing now"; under a minute "Less than a minute". If RenChan quits while a game runs, the time counts up to the game's last log line.
- Words: "Playtime" / « Temps de jeu », "Last Played" / « Dernière partie », "Never" / « Jamais », "Playing now" / « En cours ».
- Access: VoiceOver reads "Playtime, 3 hours, 20 minutes".
Acceptance:
- [unit] Time counts from launch to quit; a crash still records it.
Status: done

### S-010 Details from VNDB
As the user, I match a game to VNDB and get its cover, developer, release date and description, and my own edits stay when I refresh.
Screens: game-details, vndb-search
UX:
- Flow: inspector "Find on VNDB…" (or Game › Find on VNDB…, ⇧⌘D) → sheet "Find on VNDB" with the title already searched → pick a result → "Use This Game" (Return) → cover, developer, release date and description fill in. Escape cancels and changes nothing.
- Matched: the Details section shows developer, released, description (four lines, "More" opens the rest), "Open on VNDB", and a … menu with "Refresh from VNDB" and "Unlink from VNDB".
- Cover: right-click › "Choose Cover…" picks an image; "Reset Cover" goes back to VNDB's cover or the game's own art. A chosen cover is never replaced by a refresh.
- Surface: a sheet (one short task that finishes or cancels); details inline in the inspector.
- States: searching shows a spinner in the list; no results "No games on VNDB match “…”." with the field to try another title; offline "VNDB can't be reached. Check your connection and try again." inline under the field.
- Words: "Find on VNDB…" / « Chercher sur VNDB… », "Use This Game" / « Utiliser ce jeu », "Refresh from VNDB" / « Actualiser depuis VNDB ».
- Access: Return picks the selected result, arrows move in the list; VoiceOver reads title, developer and year per row.
Acceptance:
- [unit] A title search returns candidates; a manual cover is kept on refresh.
- [live] Matches three known games. (`RENCHAN_LIVE=1 swift test --filter Live`, passed 2026-11-22)
Status: done

### S-011 Labels, rating and notes
As the user, I add labels, a rating and notes to a game, and filter the library by label, rating, or status (not started, playing, finished).
Screens: game-details, library-filtered
UX:
- Flow: inspector "My Game" section → Status picker (Not Started, Playing, Finished), five stars, labels (type and Return adds one, × removes it), notes (saved as you type). Playing a game moves Not Started to Playing.
- Filter: toolbar Filter menu with Status, Rating ("3 Stars or More"…) and each label; the button fills when a filter is on; "Clear Filters" in the menu and in the empty state.
- Surface: inline in the inspector; a toolbar menu for the filter (a few choices tied to one control).
- States: no labels "No labels"; nothing matches "No Games Match These Filters" with "Clear Filters".
- Words: "Status" / « Statut », "Not Started" / « Pas commencé », "Playing" / « En cours », "Finished" / « Terminé », "Rating" / « Note », "Labels" / « Étiquettes », "Notes" / « Notes ».
- Access: stars are one control with a value ("3 stars") and increment/decrement; labels are buttons "Remove label Romance".
Status: done

### S-012 Back up saves
As the user, I back up a game's saves with one click, see past backups by date, and restore one.
Screens: game-details, save-backups
UX:
- Flow: inspector "Back Up Saves" (or Game › Back Up Saves, ⌥⌘B) → a backup with today's date, the inspector's Saves section says when the last backup was made. "Backups…" (Game › Save Backups…) → sheet "Save Backups" listing each backup with its date, number of saves and size → "Restore…" asks "Restore the saves from <date>?" with "Restore" → RenChan backs up the current saves first, then restores. Move to Trash removes a backup (it can come back from the Trash).
- Surface: a button inline; the list in a sheet; a confirmation dialog for Restore.
- States: no saves folder yet "Found the first time you play" and the buttons off; no backups "No backups yet" with "Back Up Now"; while the game plays, Restore is off with "Quit the game to restore".
- Words: "Back Up Saves" / « Copier les sauvegardes », "Save Backups" / « Copies des sauvegardes », "Restore…" / « Restaurer… », "Before restore" / « Avant restauration ».
- Access: the list is a Table; Return on a row asks to restore.
Acceptance:
- [unit] A restore keeps a backup of the saves it replaces.
Status: done

### S-013 Update a game to a new version
As the user, I point a game at its new version's folder or zip; its labels, playtime, filter and mods carry over.
Screens: game-details
UX:
- Flow: Game › Update to New Version… (⇧⌘U), right-click, or the inspector's Files › Update… → a panel opens beside the current version → pick the new folder, .app or zip → "Update “Eternum 0.9.5” to Eternum-0.10-pc.zip?" with Update → the game keeps its place, playtime, status, rating, labels, notes, cover and save backups, and the next Play makes a fresh working copy.
- Surface: an open panel, then a confirmation dialog (it changes which files the game plays).
- States: playing "Quit Eternum before updating it."; the same version "Eternum already plays this version."; another game's files "This version is already in the library as …"; not a game or not a zip: the same one-line refusals as Add Game.
- Words: "Update to New Version…" / « Mettre à jour vers une nouvelle version… », "Update" / « Mettre à jour ».
- Access: the dialog's Update is the default button; Escape cancels.
Acceptance:
- [unit] An update keeps the id, playtime, status, rating, labels, notes, VNDB details and cover, and clears a runtime picked for the old version.
- [self] A folder update and a zip update; the old version's files are untouched and RenChan's copy of an old zip is removed.
Status: done

### S-028 Discover games on VNDB
As the user, I search VNDB for Ren'Py games, see where each one is sold or downloaded, and the game I add after visiting one of those pages gets its VNDB details.
Screens: discover
UX:
- Flow: sidebar Discover → popular Ren'Py games until I type → search (Return) in the toolbar field; "Ren'Py Only" toggle → pick a game → inspector "Where to Get It" lists releases (official first) with buttons such as Itch.io, Steam, Patreon → the page opens in the browser → I download and drop the game on RenChan → it is linked to that entry.
- Surface: a sidebar page (a place to come back to) with the inspector.
- States: loading spinner; offline "VNDB Can't Be Reached" with Try Again; no results; a game already in the library shows "In Library" and "Show in Library".
- Words: "Discover" / « Découvrir », "Where to Get It" / « Où l’obtenir », "Fan release" / « Version de fans ».
- Notes: VNDB hosts no games, so RenChan opens the store pages; itch.io and Steam need the person's own account.
Acceptance:
- [unit] A Ren'Py-only search, popular games when the search is empty, official releases first, title matching for the added game.
- [self] Only a game with a matching title, added after opening a page, is linked.
- [live] Finds Eternum among Ren'Py games with an official release and its links.
Status: done

### S-029 Get a game's new version
As the user, from a game linked to VNDB, I open the page where its new version is downloaded, then update it.
Screens: game-details
UX:
- Flow: inspector Files › New version › "Get It" menu (official download pages) → browser → Update… with the downloaded file (S-013).
- Words: "Get It" / « Obtenir ».
Acceptance:
- [self] Get It lists official pages only, each once.
Status: done

### S-030 Find games already on this Mac
As the user, RenChan finds the Ren'Py games already in my Applications, Games, Downloads and Desktop folders, and I add the ones I want at once.
Screens: find-games, library-empty
UX:
- Flow: File › Find Games on This Mac… (⇧⌘O) or the empty library's button → sheet "Find Games on This Mac" while it looks → each new game with a checkbox (all on), its Ren'Py version and path → "Add 2 Games" (Return). "Look in Another Folder…" scans a folder I pick.
- Surface: a sheet (one short task); the scan reads only and never opens a game.
- States: looking (spinner and words); nothing new "No New Games Found"; games already in the library are left out; RenChan's own copies are never listed.
- Words: "Find Games on This Mac…" / « Trouver les jeux sur ce Mac… », "Add 2 Games" / « Ajouter 2 jeux ».
Acceptance:
- [unit] Finds Mac builds and game folders (game/ with renpy/ or lib/) two levels down; skips other apps, bare game/ folders and RenChan's folder.
- [self] Finds a folder game and a Mac build; adds only the chosen ones.
Status: done

## M3 Screen filters (0.3.0)

### S-014 Turn on a filter
As the user, I pick a filter for a game (Sharpen, CRT, Night warmth, Grayscale, Protanopia, Deuteranopia, Tritanopia) and it applies the next time it plays.
Acceptance:
- [unit] On 7.7+/8.2+ the loader sets `config.layer_transforms[None]`; on 7.4.6–7.6 it uses `camera`; below 7.4 the picker is off and says why.
- [live] Each filter shows on an 8.6 and a 7.8 game.
- [self] The filter file lands in the working copy only, and leaves when the filter is off.
UX:
- Flow: select a game → inspector › Screen Filter › Filter (None, Sharpen, CRT, Night Warmth, Grayscale; Color Blindness: Protanopia, Deuteranopia, Tritanopia) → Strength slider → Play.
- Surface: inline in the inspector (one value of the selection).
- States: None hides Strength; a runtime before 7.4.6 disables the picker and says why; while playing, "Changes show the next time you play."
- Words: "Screen Filter" / « Filtre d’écran », "Strength" / « Intensité », "Color Blindness" / « Daltonisme ».
Status: done

### S-015 Tune a filter live
As the user, I change a filter's strength while the game runs and see it change in the game.
Acceptance:
- [unit] RenChan writes parameters to a file the loader reads each second.
- [live] Grayscale started at 0 turns the running game gray once the file says 1 (7.8.7 and 8.6.1).
- [self] Moving Strength while playing writes the file.
UX:
- Flow: game playing → inspector › Screen Filter › Strength slider → the game changes within a second. Filter › None fades it out now; another filter waits for the next launch, and the note says so.
- Surface: the same inline slider as S-014.
- Words: "Strength changes show in the game right away. Another filter shows the next time you play."
Status: done

### S-016 Add my own shader
As the user, I add a `.glsl` fragment shader with a small JSON header and it shows up as a filter.
Acceptance:
- [unit] A file needs a header with a name and some code; a broken file in the folder is skipped; a filter whose file is gone plays without a filter.
- [live] A Sepia shader turns red brown on 7.8.7 and 8.6.1.
- [self] An added filter is listed and played.
UX:
- Flow: inspector › Screen Filter › Add Filter… → open panel (.glsl) → copied into RenChan's Filters folder and picked for this game → listed under "Your Filters" in every game's picker. "Show Filters Folder" opens the folder.
- States: no header, no name or no code → a notice that shows the header to write; file gone → "(missing)" in the picker and an orange note.
- Words: "Add Filter…" / « Ajouter un filtre… », "Your Filters" / « Vos filtres ». Format in docs/custom-filters.md.
Status: done

## M4 Mods (0.4.0)

### S-031 FSR sharpening and upscaling
As the user, I pick "FSR" as a filter and a game made for 720p looks sharp in fullscreen: AMD FidelityFX FSR 1 (MIT), RCAS sharpening always, EASU upscaling when Ren'Py can hand over the game's own resolution. MetalFX is out: Ren'Py draws with OpenGL in its own process.
Acceptance:
- [live] FSR draws on 7.8.7 and 8.6.1; a hard edge stays sharper than with bilinear scaling (4 px of ramp against 6).
- [unit] FSR Upscale is two passes, the first at the game's resolution (`gl_drawable_resolution=False`).
UX:
- Flow: Screen Filter › Filter › FSR Upscale or FSR Sharpen → Strength sets RCAS sharpness, live.
- States: FSR Upscale explains itself under the slider: game drawn at its own size, then upscaled; text can look softer.
- Words: "FSR Upscale" / « Agrandissement FSR », "FSR Sharpen" / « Netteté FSR ». License in THIRD-PARTY.md.
Status: done

### S-017 Install a mod
As the user, I drop a mod (zip, `.rpa`, `.rpy`) on a game and it appears in that game's Mods list, stored by RenChan, not in the game. Walkthrough mods are mods: the same import covers them.
Acceptance:
- [unit] Zip Slip is refused; a zip's `game/` folder is found at any depth.
- [self] A mod is added and kept by RenChan; a mod no game uses leaves the library.
UX:
- Flow: inspector › Mods › Add Mod… (zip, folder, .rpy/.rpyc/.rpa) or drop on the Mods section → copied to RenChan's Mods folder → on, last in the list.
- States: empty explains drop and that the game is never changed; not a mod / no scripts / Zip Slip → a notice saying why.
- Words: "Add Mod…" / « Ajouter un mod… », "Remove from This Game" / « Retirer de ce jeu ».
Status: done

### S-018 Turn mods on and off, and order them
As the user, I switch each mod on or off and drag to set load order; the next launch uses exactly that set.
Acceptance:
- [self] Turning a mod off removes its files from the working copy before launch.
- [unit] A later mod wins a shared file; turning mods off brings back the game's own files.
- [live] A placed mod runs in real Ren'Py 7.8.7 and 8.6.1.
UX:
- Flow: a switch per mod; drag rows, or Move Up / Move Down in the context menu, to set the order. Mods on → the game plays from a second clone (play-modded).
Status: done

### S-019 Conflicts
As the user, I'm warned when two enabled mods replace the same file or screen, and told which one wins.
- [unit] Shared files (with the winner) and shared screen names are found.
UX:
- States: an orange line per conflict under the list, also written to the log at launch.
Status: done

### S-020 Modded saves stay apart
As the user, modded play keeps its own saves by default, and my saves are backed up before the first modded launch.
Acceptance:
- [unit] Launch sets `RENPY_PATH_TO_SAVES` to the game's modded save folder when any mod is on.
- [live] Saves land in the modded saves folder, not ~/Library/RenPy.
- [self] Modded saves stay apart, after one "Before mods" backup.
Status: done

### S-021 Install URM
As the user, I add my own copy of Universal Ren'Py Mod once and turn it on for any game with one switch.
- [self] A library mod goes on another game in one step.
UX:
- Flow: Mods › Add from Library › Universal Ren'Py Mod. One copy in the library serves every game.
Status: done

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
