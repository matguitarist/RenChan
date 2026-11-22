# Landscape: Ren'Py game managers, runners and mod tools on the Mac

Research for RenChan. Done 2026-11-22.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.

Question: what makes the best tool for keeping, running and modding Ren'Py games on a Mac?
Decision it informs: what goes in version one, and which app is the reference.

## Findings
- The usual way to run a Windows/Linux Ren'Py game on a Mac is manual: read `game/script_version.txt`, download the matching SDK, copy `game/` into it. People say it works for "99%" of games; the complaint is the manual version matching. [V](https://recoursive.com/2026/07/27/run_renpy_visual_novels_on_macos/) [V](https://fuckyeahrenpy.tumblr.com/post/100697586073/running-renpy-games-on-different-platforms)
- WinWorp automates exactly that: it detects the version, downloads the Mac runtime with a checksum check, runs natively and falls back to Wine. It's $4+, closed, not notarized, Apple Silicon and macOS 14+ only, has no mods or filters, and was tested on six games. It is the direct competitor. [V](https://wintercloudz1706.itch.io/winworp/devlog/1747322/winworp-020-windows-renpy-games-now-run-natively-on-your-mac)
- F95Checker is the library reference (free, GPL): update alerts, labels, ratings, notes, playtime, grid/list/kanban views, filters, launching. Its Mac support is weak: a blank webview in 11.0–11.0.3, it can't pick a `.app`, it needs a Terminal quarantine fix, and the maintainer has no Mac. [V](https://github.com/WillyJL/F95Checker) [V](https://github.com/WillyJL/F95Checker/issues/245)
- Playnite has no Mac version and none is planned. VNDB support depends on an unmaintained plugin. [V](https://playnite.net/) [V](https://github.com/JosefNemec/Playnite/issues/224)
- Universal Ren'Py Mod (URM) is the main player mod. It's one `.rpa` dropped into `game/` and offers a variable editor, choice hints, scene replay and save management. It is distributed through Patreon. [V](https://thebumguide.netlify.app/docs/guide/urm/)
- RenDroid (RenLauncher) has the best mod-manager rules: back up originals, turn mods on and off, order by priority, warn about conflicts, guard against Zip Slip, restore on uninstall. [V](https://renlauncher.org/blog/posts/rendroid-mod-guide)
- Other mod tools patch game files (RenModder deletes `.rpyc` files and writes into `renpy/common`) or are DDLC-only (Rencher, DDModDocker). None is native to the Mac. [V](https://github.com/Lines25/RenModder) [V](https://github.com/danatationn/Rencher)
- Whisky ended in April 2025. CrossOver costs about $74 a year, which is too much just to run a game Ren'Py can run natively. [V](https://appleinsider.com/articles/25/04/16/whisky-development-ends-on-macos-to-help-wine-flourish)
- VN Library is a native Mac VN library with VNDB data, but it only detects Ren'Py games and doesn't run them (0 stars, no license). [V](https://github.com/bumsar1/VNLibrary)
- Unsigned Mac game builds cause "is damaged" errors. App Translocation runs them from a read-only copy, and then saves fail. [V](https://itch.io/post/4493334) [V](https://itch.io/post/12474663)
- Save editors exist. Since 8.1 saves are signed, and web editors ask users to upload `security_keys.txt` (a privacy risk). [V] (search summary)

## Likes and dislikes
| App | People like | People dislike | Sources |
| --- | --- | --- | --- |
| Manual SDK method | free, native, nearly always works | manual version matching; SteamCMD needed for Windows-only Steam games | recoursive.com, tumblr guide |
| WinWorp | one click, native, picks the runtime | paid, closed, not notarized ("Open Anyway"), tested on few games, no mods | itch.io page |
| F95Checker | update alerts; labels, ratings, notes; playtime; views and filters | poor on the Mac; doesn't install games or carry mods and saves across updates; updater breaks | GitHub README and issues, xlibrary compare |
| Playnite | automatic metadata that keeps manual edits; extensions; themes | no Mac; plugins crash after updates; VNDB plugin unmaintained | playnite.net, issue #224 |
| URM | variable editor, choice hints | developers refuse support when it's installed; changes the game folder; breaks on some versions; Patreon | itch.io comments [K] |
| RenDroid / RenModder | toggle, priority, backups / a mod API | patch game files; RenModder's mod menu was cancelled | renlauncher.org, GitHub |
| CrossOver / Whisky | polished / was free | $74 a year / dead, laggy | appleinsider, itch.io |

Patterns: every tool that people like for running games matches the runtime automatically. Every mod tool people complain about writes into the game. Nothing built for the Mac covers library, running and mods together.

## Feature matrix
| Feature | WinWorp | F95Checker | URM | RenDroid | Manual | Version one? |
| --- | --- | --- | --- | --- | --- | --- |
| Detect the Ren'Py version | yes | no | — | ? | by hand | yes (M1) |
| Download a matching runtime | yes | no | — | ? | by hand | yes (M1) |
| Run Windows/Linux builds natively | yes | no | — | ? | yes | yes (M1) |
| Leave the original game untouched | ? | yes | no | no | no | yes (M1) |
| Library grid and list | basic | yes | — | ? | — | yes (M1) |
| Playtime and last played | ? | yes | — | — | — | yes (M2) |
| Labels, ratings, notes, filters | no | yes | — | — | — | yes (M2) |
| VNDB metadata | no | no | — | — | — | yes (M2) |
| Save backup | no | no | yes | — | — | yes (M2) |
| Screen filters (shaders) | no | no | no | no | — | yes (M3) |
| Install and toggle mods | no | no | — | yes | by hand | yes (M4) |
| Mod order and conflicts | no | no | — | yes | — | yes (M4) |
| Variable viewer / dev console | no | no | yes | — | — | console only (M5) |
| Mod API | no | no | 2.0 framework | — | — | yes (M5) |
| Update checks (F95zone, itch) | no | yes | — | — | — | Later |
| Wine fallback | yes | wrapper | — | — | — | Dropped |

## Decisions
1. RenChan's base job is WinWorp's job done free, open source and notarized, because that's the gap people already pay for. [V]
2. The library follows F95Checker (grid and list, playtime, labels, notes), plus VNDB metadata, because those are its most-liked points and nothing on the Mac does them well. [V]
3. Mods follow RenDroid's rules but never touch the original game, because patching game files is the main complaint about every mod tool. [V]
4. URM is a one-click install of the user's own copy, not bundled, because it's distributed through Patreon. [V]
5. No Wine fallback: games that the native runtime can't run go under "won't run" with the log. Whisky is dead and CrossOver is paid. [V]
6. A save editor waits: the Ren'Py console (M5) covers variables for now. [K]

## Open questions
- Which share of a real library runs on the newest runtime of its major line? Test on 20 games across 6.99–8.6.
- Is the VNDB API usable without a key, and at what rate limits? Check before M2.
