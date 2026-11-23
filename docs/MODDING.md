# Writing a mod for RenChan

A RenChan mod is a folder of Ren'Py files that RenChan copies into its own copy of a game, under `game/`, at each launch.
The game itself is never changed. Any Ren'Py mod works as it is; the parts below are what RenChan adds.

## Start from the template

Select a game, then inspector › Mods › **New Mod…**. RenChan makes a mod with a `renchan-mod.json` and one `.rpy`,
turns it on for that game, and opens the script in your editor. Save, then Play: RenChan copies the mod's current files in
at every launch, including files you add later. Context menu › Show in Finder opens its folder.

## renchan-mod.json

```json
{ "name": "Bridge Helper", "version": "0.1", "author": "Ana", "description": "Shows which answer leads where.", "renpy": "7.4" }
```

Put it at the mod's top. RenChan shows the name, version and author, and doesn't copy the manifest into the game.
Files go under `game/` with the same paths they have beside the manifest.

## The renchan module

RenChan writes `game/00_renchan_api.rpy` at `init -999` in every modded launch, so any `init` block of yours can call it.
It runs on Ren'Py 7.4+ (Python 2) and 8.x (Python 3): write code both can run (no f-strings).

| Call | What it does |
| --- | --- |
| `renchan.version` | The API version, 1. |
| `renchan.on_start(fn)` | Calls `fn()` when a new game starts. |
| `renchan.after_load(fn)` | Calls `fn()` after a save is loaded. |
| `renchan.menu_entry(label, fn)` | Adds a button to the Mods menu, which F8 opens in the game. |
| `renchan.keymap(key, fn)` | Calls `fn()` on a key, such as `"K_F9"` or `"alt_K_w"`. |
| `renchan.state(name)` | A dict kept between launches, outside the saves. |
| `renchan.save_state(name)` | Writes that dict to RenChan's copy of the game. |

State lives outside saves on purpose: a save made while a mod was on still loads after the mod is turned off,
as long as the mod didn't put its own classes into the store.

```renpy
init 10 python:
    def bridge_menu():
        s = renchan.state("bridge")
        s["opened"] = s.get("opened", 0) + 1
        renchan.save_state("bridge")
        renpy.notify("Opened %d times" % s["opened"])

    renchan.menu_entry("Bridge Helper", bridge_menu)
```

## Saves

With any mod on, the game plays from its own copy and keeps its saves apart (`RENPY_PATH_TO_SAVES`), and RenChan
backs up the normal saves once before the first modded launch.
