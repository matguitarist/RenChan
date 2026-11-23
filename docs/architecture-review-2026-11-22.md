# Architecture review, 2026-11-22 (after M2 S-009 to S-012)

Survey: 3,664 lines. The largest files are LibraryPage.swift (297), SelfTest.swift (219), Models.swift (215) and MyGameSection.swift (202); none is near 600. RenChanKit holds every rule with a unit test (playtime sessions, VNDB parsing, filters and labels, save backups); the app target only calls it. M2 touched more than 6 files per story, which is expected while the inspector grows.

## Library saves on every keystroke  [Worth exploring]

Files: Sources/RenChan/Models.swift (`update`), MyGameSection.swift (notes field)
Signal: state that changes many times a second on a model many views observe.
Problem: typing in Notes calls `update`, which rewrites library.json once per keystroke. Fine for 50 games, wasteful for 1,000.
Proposal: `update(_:save: .soon)` that mutates now and saves after 0.5 s of quiet, plus a flush in `applicationWillTerminate`.
Benefits: one write per pause; no change for callers that keep the default.
Proof of same behavior: self-test S-011 "labels, rating and notes are saved" after a flush.
Plan: add the debounced save and the flush; move the notes field over.

## Backup lists read from disk in view bodies  [Worth exploring]

Files: Sources/RenChan/Models+Backups.swift, BackupsSheet.swift
Signal: I/O on the main thread during a redraw.
Problem: `backups(_:)` lists the folder each time the inspector or sheet redraws. Cheap for a few backups; not for hundreds.
Proposal: `var backupLists: [Game.ID: [SaveBackup]]` filled on demand and cleared where `backupRevision` is bumped today.
Benefits: one read per change; the revision counter goes away.
Proof of same behavior: self-test S-012 checks; the save-backups snapshot.

## AppModel keeps every feature's state  [Speculative]

Files: Sources/RenChan/Models.swift and its five extensions
Signal: a model many features share.
Problem: none today; each feature's actions live in their own extension file. Revisit when mods (M4) add their state.

## Top recommendation

None is Strong. The debounced save is the first to do if the library grows or typing in Notes feels slow.

Considered, not recommended: a protocol for VNDB (one adapter; parsing is already tested on its own), moving `Store` out of App.swift (small and only paths).
