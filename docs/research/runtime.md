# Running Ren'Py games, filters and mods without touching the game

Research for RenChan. Done 2026-11-22.
[V] verified in a source, [K] from knowledge, [U] unverified, test first.

Question: how does RenChan run any Ren'Py game's `game/` folder on a Mac with an official runtime, and add filters and mods without changing the game?
Decision it informs: version detection, the runtime list, the launch command, the filter tiers and the mod loading.

## Findings
### Runtimes
- Official SDKs are at `https://www.renpy.org/dl/<ver>/renpy-<ver>-sdk.{tar.bz2,zip,dmg}`, with `checksums.txt`. Not every version has a zip; `tar.bz2` is always there. The latest is 8.6.1 (2026-11-17). [V](https://www.renpy.org/dl/)
- Each SDK contains the Windows, Mac and Linux runtimes. [V](https://www.renpy.org/latest.html)
- Universal (native Apple Silicon) Mac runtimes start at 8.1 and 7.6. Before that, they're Intel-only and need Rosetta. [V](https://www.renpy.org/doc/html/changelog.html) [V] the 7.8.7 and 8.3.7 `sdk.update.json` files.

| Ren'Py | Python | Mac lib folder | On Apple Silicon |
| --- | --- | --- | --- |
| 6.x – 7.3 | 2 | `darwin-x86_64` | Rosetta |
| 7.4 | 2 | `mac-x86_64` | Rosetta |
| 7.5 | 2 | `py2-mac-x86_64` | Rosetta |
| 7.6 – 7.8.7 | 2 | `py2-mac-universal` | native |
| 8.0 | 3.9 | `py3-mac-x86_64` | Rosetta |
| 8.1+ | 3.9 → 3.12 | `py3-mac-universal` | native |

- Rosetta stays complete through macOS 27, then is cut down in macOS 28. [V](https://www.macrumors.com/2025/06/10/apple-to-phase-out-rosetta-2/)
- Launch: `renpy.sh <basedir>` [V](https://www.renpy.org/doc/html/cli.html), or, as renutil does, `lib/<arch>/python -EO renpy.py <basedir>` with `RENPY_LOG_TO_STDOUT=1`. [V](https://github.com/kobaltcore/renkit/blob/master/src/renutil.rs)
- A newer runtime keeps old behavior for older games through `script_version`. [V] changelog. Ren'Py 8 (Python 3) cannot run 7.x Python 2 code or most 7.x `.rpyc` files. [V](https://www.renpy.org/doc/html/incompatible.html) [K]
- Version detection, in order: `renpy/vc_version.py` + `renpy/__init__.py` (`version_tuple`), `log.txt` first line, `game/script_version.txt`, `lib/` folder names (`py2-*` 7.x, `py3-*` 8.x, `darwin-*`/`windows-*` older), the `.rpyc` header. [V](https://github.com/renpy/renpy/blob/7.4.11.2266/renpy/__init__.py) [K]
- Saves are in `~/Library/RenPy/<config.save_directory>`, shared by every runtime that runs the game. [V](https://www.renpy.org/doc/html/config.html) `RENPY_PATH_TO_SAVES` and `RENPY_MULTIPERSISTENT` move them. [V](https://www.renpy.org/doc/html/environment_variables.html)
- The license is MIT plus LGPL parts. Downloading from renpy.org on demand avoids redistributing anything. [V](https://www.renpy.org/doc/html/license.html)
- Files downloaded with URLSession get no quarantine flag. [K][U]

### Filters
- The model-based renderer (GL2), `renpy.register_shader`, `matrixcolor` and `blur` start at 7.4.0, and GL2 is the default from 7.4.5. A game can turn it off with `config.gl2 = False`. [V](https://www.renpy.org/doc/html/model.html)
- `config.layer_transforms[None]` transforms the whole screen after transitions, from 8.2 / 7.7. [V](https://www.renpy.org/doc/html/config.html) Before that, `camera` (7.4.6) or `show layer master at` exist, but `scene` and the game's own script clear them. [V](https://www.renpy.org/doc/html/displaying_images.html)
- Use `glsl=100` shaders to stay portable (8.6 defaults to ES 3.00; macOS uses GLSL 1.20). [V](https://www.renpy.org/doc/html/model.html)

### Mods
- Ren'Py loads every `.rpy`, `.rpyc` and `.rpa` under `game/`, ordered by `init` priority then file name. 8.4 adds `game/mods` with `mods.txt` ordering. [V](https://github.com/renpy/renpy/blob/master/sphinx/source/changelog.rst)
- `RENPY_SEARCHPATH` (7.2.1+) adds directories to the search path. Whether scripts there are compiled is unverified. [V](https://github.com/renpy/renpy/blob/master/renpy.py) [U]
- Hooks: `config.start_callbacks`, `config.after_load_callbacks` (rolled back unless `renpy.block_rollback()`), `config.label_overrides`, screen replacement at a later init priority, `config.underlay` keymaps, `config.console`/`config.developer`. [V](https://www.renpy.org/doc/html/config.html) [K]
- Saves pickle store objects: a save made with a mod's class won't load after the mod is removed. [K]

## Decisions
1. Two default runtimes, 7.8.7 for Python 2 games and the newest 8.x for Python 3 games, both native. The exact version is downloaded only when a game fails or is older than 7.4. Planned test: 20 real games.
2. Never run the original. RenChan makes a working copy of the game's base folder with an APFS clone (`clonefile`, which costs no space on the same volume), and runs and modifies only that copy. Planned test: clone a 4 GB game, check disk use, and check that `.rpyc` writes stay in the copy. A game on another volume is fully copied, after asking.
3. Launch through the runtime's Python directly (`lib/<folder>/python -EO renpy.py <copy>`), so RenChan reads the log and the exit code. [V]
4. RenChan's own files (filter loader, mod API, console switch) are `.rpy` sources in `game/renchan/` inside the copy, so each Python line compiles them itself. [V]
5. Filter tiers: full-screen filters on 7.7+/8.2+; `camera` filters on 7.4.6–7.6, marked "may reset during scenes"; none below 7.4 or with `config.gl2 = False`. [V]
6. Mods with a class in saved state are allowed but flagged. Modded play gets its own save folder by default (`RENPY_PATH_TO_SAVES`), and saves are backed up before the first modded launch. [V]
7. Pre-7.6 and 8.0 games run under Rosetta with a notice. macOS 28 behavior is retested when it ships. [V]

## Probes (2026-11-22, Ren'Py 8.6.1 on Apple Silicon, macOS 26)
- SDK `tar.bz2` sha256 matches `checksums.txt`; `lib/` holds `py3-mac-universal` and `python3.12`.
- `lib/py3-mac-universal/python -EO renpy.py <base> compile` runs headless in about 3 s for The Question.
- APFS clone (`cp -c -R`) of the base folder: compiling the clone wrote 52 `.rpyc` files into the clone and none into the original; the original's checksum was unchanged. Decision 2 holds.
- `RENPY_SEARCHPATH=<dir>` loads and runs a `.rpy` from outside the game, and writes its `.rpyc` next to it in that dir. So mods can live outside the copy, but each Python line needs its own mod folder.
- A `.rpy` in `game/renchan/` of the clone loads too.
- Ren'Py writes `~/Library/RenPy/<save_directory>`, `backups/<base folder name>` and `tokens/security_keys.txt` even for `compile`. Setting `HOME` to a temp folder keeps all of it out of the real `~/Library/RenPy`: every test does that.

## Open questions
- Do games that ship a patched `renpy/` folder need their own engine rather than a stock runtime? Detect a modified `renpy/` by comparing file hashes against the stock SDK.
- Does 6.99.x still run under Rosetta on macOS 26?
