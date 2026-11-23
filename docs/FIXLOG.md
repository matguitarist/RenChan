# RenChan — Fix log

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
