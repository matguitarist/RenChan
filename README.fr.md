# RenChan

Une app Mac libre et gratuite qui rassemble vos romans visuels Ren’Py dans une bibliothèque et lance n’importe lequel nativement, y compris les jeux publiés uniquement pour Windows ou Linux, avec des filtres d’écran et des mods qui ne modifient jamais le jeu d’origine.

[English](README.md)

> RenChan n’en est qu’au début : la fenêtre se compile, la bibliothèque arrive avec la 0.1.0. Voir [docs/STORIES.md](docs/STORIES.md).

## Téléchargement

[RenChan.dmg](https://github.com/matguitarist/RenChan/releases/latest/download/RenChan.dmg), pour macOS 26 ou plus récent, dès la sortie de la 0.1.0.

## Fonctionnement

RenChan détecte la version de Ren’Py de chaque jeu, télécharge la version officielle correspondante depuis [renpy.org](https://www.renpy.org) et lance le jeu à partir d’une copie : le jeu que vous avez ajouté n’est jamais modifié. Ren’Py n’est pas inclus dans l’app. Les détails sont dans [docs/research/runtime.md](docs/research/runtime.md).

## Compilation

```zsh
./build.sh --open                     # compile et installe ~/Applications/RenChan.app
swift test                            # tests unitaires
tools/selftest.sh                     # l’autotest intégré
```

## Licence

MIT. Ren’Py est © Tom Rothamel et ses contributeurs, sous sa propre [licence](https://www.renpy.org/doc/html/license.html).
