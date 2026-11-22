# RenChan

A free, open-source Mac app that keeps your Ren'Py visual novels in one library and plays any of them natively, including games released only for Windows or Linux, with screen filters and mods that never change the original game.

[Français](README.fr.md)

> RenChan is at the very start: the window builds, the library comes in 0.1.0. See [docs/STORIES.md](docs/STORIES.md).

## Download

[RenChan.dmg](https://github.com/matguitarist/RenChan/releases/latest/download/RenChan.dmg), for macOS 26 or later, once 0.1.0 is out.

## How it works

RenChan detects each game's Ren'Py version, downloads a matching official runtime from [renpy.org](https://www.renpy.org), and runs the game from a copy, so the game you added is never modified. Ren'Py itself is not bundled. Details are in [docs/research/runtime.md](docs/research/runtime.md).

## Build

```zsh
./build.sh --open                     # builds and installs ~/Applications/RenChan.app
swift test                            # unit tests
tools/selftest.sh                     # the in-app self-test
```

## License

MIT. Ren'Py is © Tom Rothamel and contributors, under its own [license](https://www.renpy.org/doc/html/license.html).
