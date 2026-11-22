# RenChan

A native macOS app in SwiftUI that keeps a library of Ren'Py visual novels and
plays any of them natively, including Windows- and Linux-only releases, on
official Ren'Py runtimes, with screen filters and mods that never touch the
original game. Brief: `docs/BRIEF.md`. Stories: `docs/STORIES.md`.

Shared rules for my Mac apps (build and check, design rules, skills, git):
@~/.claude/mac-app-conventions.md

Shared rules for how every project is laid out and named:
@~/.claude/project-layout.md

## How games run (read before touching Play, Mods or Filters)

- RenChan never writes to a game the person added. It plays an APFS clone of the game's base folder in `~/Library/Application Support/RenChan/`, and only that copy gets `.rpyc` files, RenChan's `.rpy` files and mods. A test checks the original's checksum.
- Games run on official runtimes downloaded from renpy.org (checked against `checksums.txt`) with `lib/<folder>/python -EO renpy.py <copy>`. The runtime rules are in `docs/research/runtime.md`.
- RenChan's own in-game files are `.rpy` sources (never `.rpyc`), so Python 2 (7.x) and Python 3 (8.x) runtimes each compile them.
- Ren'Py writes saves, persistent data, backups and `tokens/security_keys.txt` under `~/Library/RenPy`. Every test that starts Ren'Py sets `HOME` to a folder in /tmp, so nothing lands in the person's real `~/Library/RenPy`.

## Layout

- `Sources/RenChan/` the app. `App.swift` has the window, menus, and the library location.
- `Sources/RenChanKit/` rules and data logic with no SwiftUI. Tests in `Tests/RenChanKitTests/`.
- `Package.swift` a Swift package. There is no Xcode project.
- `build.sh` builds, signs, and installs `~/Applications/RenChan.app`.
- Release: `tools/release.sh <version>` (settings in `release.conf`, version in `Info.plist.in`). Use the mac-release skill.
- `Icon/AppIcon.icon` the app icon, an Icon Composer file (JSON plus SVG layers). `build.sh` compiles it with `tools/make_icon.sh`; `tools/icon_review.sh` renders every look into one PNG.
- `docs/` the brief, the research, and the user stories.

## Checks specific to this app

- `APP_SNAPSHOT_MIN=1 tools/snap.sh` shoots the window at its smallest size.
- Never test against the real library in `~/Library/Application Support/RenChan/` or the real `~/Library/RenPy`.
