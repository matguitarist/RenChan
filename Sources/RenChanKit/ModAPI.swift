import Foundation

/// renchan-mod.json at a mod's top (S-023).
public struct ModManifest: Codable, Hashable, Sendable {
    public var name: String
    public var version: String?
    public var author: String?
    public var description: String?
    /// The oldest Ren'Py it needs, such as "7.4".
    public var renpy: String?

    public init(name: String, version: String? = nil, author: String? = nil, description: String? = nil, renpy: String? = nil) {
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.renpy = renpy
    }

    public static let fileName = "renchan-mod.json"

    public static func read(_ folder: URL) -> ModManifest? {
        (try? Data(contentsOf: folder.appending(path: fileName))).flatMap { try? JSONDecoder().decode(ModManifest.self, from: $0) }
    }
}

/// The `renchan` module mods call (S-023), written into the modded copy before each launch.
/// Works on Ren'Py 7.4+ (Python 2) and 8.x (Python 3).
public enum ModAPI {
    public static let fileName = "00_renchan_api.rpy"
    public static let version = 1

    /// Where mods keep state between launches, outside saves: the copy's base folder, not game/.
    public static func stateFolder(_ copy: URL) -> URL { copy.appending(path: "renchan_state", directoryHint: .isDirectory) }

    public static func install(copy: URL) throws {
        try FileManager.default.createDirectory(at: stateFolder(copy), withIntermediateDirectories: true)
        try CopyScript.place(source(stateFolder: stateFolder(copy)), named: fileName, in: copy)
    }

    public static func source(stateFolder: URL) -> String {
        let path = stateFolder.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return #"""
        # RenChan's mod API, version \#(version). Written by RenChan before each modded launch. See docs/MODDING.md.
        init -999 python in renchan:
            import json as _json
            import os as _os
            import sys as _sys
            import types as _types
            import renpy as _renpy

            def _native(s):
                # Ren'Py 7 makes str unicode in game code; module names and keywords need Python 2's own str.
                if _sys.version_info[0] == 2 and not isinstance(s, bytes):
                    return s.encode("ascii")
                return s

            # Kept in a module, not the store, so none of it goes into saves.
            _rt = _sys.modules.get("renchan_runtime")
            if _rt is None:
                _rt = _types.ModuleType(_native("renchan_runtime"))
                _rt.menu = []
                _rt.states = {}
                _rt.keys = 0
                _sys.modules["renchan_runtime"] = _rt

            version = \#(version)
            state_folder = "\#(path)"

            def on_start(fn):
                """Calls fn() when a new game starts."""
                _renpy.config.start_callbacks.append(fn)

            def after_load(fn):
                """Calls fn() after a save is loaded."""
                _renpy.config.after_load_callbacks.append(fn)

            def menu_entry(label, fn):
                """Adds a button to the mods menu, which F8 opens."""
                _rt.menu.append((label, fn))

            def entries():
                return list(_rt.menu)

            def keymap(key, fn):
                """Calls fn() when key is pressed, such as "K_F9" or "alt_K_w"."""
                _rt.keys += 1
                _renpy.config.underlay.append(_renpy.exports.Keymap(**{_native(key): fn}))

            def state(name):
                """A dict kept between launches, outside the saves. Call save_state(name) after changing it."""
                if name not in _rt.states:
                    data = {}
                    try:
                        with open(_os.path.join(state_folder, name + ".json")) as f:
                            data = _json.load(f)
                    except Exception:
                        pass
                    _rt.states[name] = data
                return _rt.states[name]

            def save_state(name):
                try:
                    if not _os.path.isdir(state_folder):
                        _os.makedirs(state_folder)
                    with open(_os.path.join(state_folder, name + ".json"), "w") as f:
                        _json.dump(_rt.states.get(name, {}), f)
                except Exception as e:
                    _renpy.display.log.write("RenChan state %s not saved: %r" % (name, e))

        init -998 python:
            config.underlay.append(renpy.Keymap(K_F8=ToggleScreen("renchan_mods_menu")))

        screen renchan_mods_menu():
            zorder 1000
            frame:
                xalign 0.98
                yalign 0.02
                padding (16, 12)
                vbox:
                    spacing 6
                    text "Mods" size 22
                    for label, fn in renchan.entries():
                        textbutton label action [Function(fn), Hide("renchan_mods_menu")]
                    if not renchan.entries():
                        text "No mod added a menu entry." size 16
                    textbutton "Close" action Hide("renchan_mods_menu")

        """#
    }
}

/// A new mod from RenChan's template (S-024): a manifest and one .rpy that uses the API.
public enum ModTemplate {
    /// "My Cheat Menu" → "my_cheat_menu".
    public static func slug(_ name: String) -> String {
        let lowered = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        let parts = lowered.split(separator: "_").map(String.init)
        let joined = parts.joined(separator: "_")
        guard let first = joined.first else { return "my_mod" }
        return first.isLetter ? joined : "mod_" + joined
    }

    public static func create(_ name: String, author: String? = nil, into root: URL) throws -> Mod {
        let id = UUID()
        let folder = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        let slug = slug(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = ModManifest(name: name, version: "0.1", author: author, description: "", renpy: "7.4")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: folder.appending(path: ModManifest.fileName))
        let quoted = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = #"""
        # \#(name): a RenChan mod. Edit this file, save it, then Play: RenChan copies it into the game at each launch.
        # The renchan module is described in RenChan's docs/MODDING.md.

        init 10 python:
            def \#(slug)_started():
                renpy.notify("\#(quoted) is on. Press F8 for the mods menu.")

            def \#(slug)_menu():
                s = renchan.state("\#(slug)")
                s["opened"] = s.get("opened", 0) + 1
                renchan.save_state("\#(slug)")
                renpy.notify("\#(quoted): opened %d times" % s["opened"])

            renchan.on_start(\#(slug)_started)
            renchan.menu_entry("\#(quoted)", \#(slug)_menu)

        """#
        try script.write(to: folder.appending(path: "\(slug).rpy"), atomically: true, encoding: .utf8)
        return Mod(id: id, name: name, files: ModLibrary.files(in: folder).filter { $0 != ModManifest.fileName })
    }
}
