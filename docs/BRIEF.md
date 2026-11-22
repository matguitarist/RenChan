# RenChan

A free, open-source Mac app that keeps your Ren'Py visual novels in one library and plays any of them natively, including Windows/Linux-only releases, with screen filters and mods that never touch the original game.

App name in the UI: **RenChan**. Bundle id: `com.mathieuares.renchan`. License: MIT. _Decided by the agent._

## Replaces
WinWorp (paid, closed, not notarized); the manual "copy `game/` into the matching SDK" routine; F95Checker's library on the Mac; dropping URM and other mods into game folders by hand.

## Main jobs
1. **Add and play:** drop a game folder, `.app` or zip; RenChan detects its Ren'Py version, gets a matching runtime from renpy.org, and plays it natively, untouched.
2. **Keep the library:** grid and list with covers, VNDB details, playtime, last played, labels, notes, save backups.
3. **Change how it looks:** turn on a screen filter per game (sharpen, CRT, colorblind, night warmth) with a live preview.
4. **Mod it:** install mods (zip, `.rpa`, `.rpy`, URM), turn them on and off, order them, keep separate saves for modded play, and write mods against RenChan's small API.

## Data
- **Game:** title, source path (bookmark), kind (folder / app / zip), detected Ren'Py version, Python line, working copy path, save directory, VNDB id, cover, labels, notes, rating, playtime, last played, filter, mod list.
- **Runtime:** Ren'Py version, Mac lib folder, universal or Intel, path, size, checksum.
- **Mod:** id, name, version, kind (rpy / rpa / zip / urm), files, enabled, order, Ren'Py range, flags (touches saves).
- **Filter:** id, name, shader source, parameters, minimum Ren'Py tier.

## Platforms
Mac first and only for now: Swift 6, SwiftUI, SwiftPM at the root (`new-mac-app`). The parts that run inside games are Ren'Py `.rpy` files in `Resources/RenChanRuntime/` and work on any OS, so a Windows/Linux app later can reuse them.

## Shape
One window with a sidebar (Library, Runtimes, Mods, Filters; Settings in its own window), macOS 26 or later, Liquid Glass. Data in `~/Library/Application Support/RenChan` (working copies, runtimes, mod store, save backups). Internet only for downloading runtimes and VNDB data. No accounts.

How it plays a game: a working copy of the game's base folder is made with an APFS clone (no extra space on the same volume) and run with `lib/<folder>/python -EO renpy.py <copy>` from a downloaded runtime. RenChan's `.rpy` files (filter loader, mod API) and enabled mods go into the copy. The original is never written to. See `docs/research/runtime.md`.

## System hooks
Drag and drop onto the window and Dock icon; open `.rpa`/mod zips with RenChan; a `renchan` CLI later.

## Reference
WinWorp for the run flow; F95Checker for the library; RenDroid for mod rules. Research in `docs/research/`.

## Look
Native Mac, cover-art grid, accent sakura pink (`#E8749A`), English and French.

## Not in version one
- Rewriting the Ren'Py engine (in Rust or anything else): real games need Ren'Py's own Python.
- Wine fallback, Windows and Linux apps.
- F95zone/itch update checks, save editor, SteamCMD downloads (under Later).
