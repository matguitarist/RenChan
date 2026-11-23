# RenChan — Fix log

## 2026-11-22 A download that isn't a zip showed unzip's raw error

Dropping `cosy-cafe-mac.zip` showed several lines of zipinfo output. The file was 118 bytes of XML: itch.io's download links expire after 60 seconds, and Safari saved the "Request has expired" error page under the zip's name. RenChan now checks the zip signature (PK) before asking to unpack, and says the file isn't a zip, its size, and to download again.
Test: `aDownloadThatIsntAZipIsRefusedPlainly` in LocatorTests.
Rule: check what a file is by its first bytes before handing it to a tool, and turn a tool's raw error into what happened and what to do.

## 2026-11-22 Snapshots crashed in a layout loop after the owner tiled the window
- Symptom: `tools/snap.sh` ended with exit 133 (SIGTRAP in -[NSWindow _postWindowNeedsUpdateConstraints]) on every page, even on code that had passed minutes before. The app itself ran fine.
- Cause: snapshot mode reads the owner's real `NSWindow Frame main`, which carried macOS tiling state; a tiled window restored into the snapshot run's appearance switches loops AppKit's constraint passes. Snapshot runs also rewrote the owner's saved frame.
- Fix: `snap.sh` exports the app's defaults, removes the frame for the run, and imports them back afterwards.
- Rule: a test or snapshot run must not read or write the owner's UI state either: set aside and restore the app's defaults around it, like the store and HOME.
