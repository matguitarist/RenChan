import Foundation

/// How a runtime lets RenChan put a filter over the whole screen (docs/research/runtime.md).
public enum FilterTier: Equatable, Sendable {
    /// `config.layer_transforms[None]`: Ren'Py 7.7+ and 8.2+, after transitions, untouched by the game's script.
    case layerTransforms
    /// `camera` on the master layer, set again at each interaction: Ren'Py 7.4.6 to 7.6 and 8.0 to 8.1.
    case camera
    /// Before 7.4.6 there is no model renderer to run a shader in.
    case unsupported

    public static func forRuntime(_ version: String) -> FilterTier {
        guard let v = RenPyVersion(version) else { return .unsupported }
        if v >= RenPyVersion("8.2")! || (v >= RenPyVersion("7.7")! && v < RenPyVersion("8.0")!) { return .layerTransforms }
        if v >= RenPyVersion("7.4.6")! { return .camera }
        return .unsupported
    }
}

/// Writes RenChan's filter file into a working copy before a launch, or takes it out (S-014).
/// The .rpy is the same for every filter: what to draw comes from a state file RenChan rewrites while the game
/// runs, so the filter, its strength and a custom filter's code all change live (S-015).
public enum FilterLoader {
    /// Sorted after the game's own files; Ren'Py compiles it next to itself as .rpyc.
    public static let fileName = "zz_renchan_filter.rpy"
    /// Most passes any filter has (FSR Upscale: EASU then RCAS).
    static let slots = 2

    /// The filter state while the game runs: JSON with the strength and the passes, in the copy's base folder,
    /// outside game/. A bare number is read as the strength alone. The loader checks it twice a second.
    public static func liveFile(_ copy: URL) -> URL { copy.appending(path: "renchan_filter.json") }
    /// What Ren'Py said when a new filter's shader didn't compile; empty once one does.
    public static func errorFile(_ copy: URL) -> URL { copy.appending(path: "renchan_filter_error.txt") }

    /// The passes a setting draws with, or nil when its custom file is gone.
    public static func passes(_ setting: FilterSetting?, custom: [CustomFilter]) -> [FilterPass]? {
        guard let setting else { return [] }
        if let name = setting.custom {
            return custom.first { $0.file == name }.map { [FilterPass(fragment: $0.fragment)] }
        }
        return setting.filter.passes
    }

    struct State: Encodable {
        struct Pass: Encodable { var functions: String; var fragment: String; var game: Bool; var layer: String? }
        var strength: Double
        var name: String
        var key: String
        var passes: [Pass]
    }

    /// The state file's text. Its key changes whenever the shader code does, so an edited filter is compiled again.
    static func state(_ setting: FilterSetting?, passes: [FilterPass]) -> Data {
        let list = passes.map { State.Pass(functions: $0.functions.replacingOccurrences(of: "\"\"\"", with: ""),
                                           fragment: $0.fragment.replacingOccurrences(of: "\"\"\"", with: ""), game: $0.gameResolution,
                                           layer: $0.imagesOnly ? "master" : nil) }
        var hash: UInt64 = 0xcbf29ce484222325
        for pass in list { for byte in (pass.functions + "\u{1}" + pass.fragment + (pass.game ? "1" : "0") + (pass.layer ?? "") + "\u{2}").utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 } }
        let state = State(strength: min(1, max(0, setting?.strength ?? 0)), name: setting?.name ?? "none",
                          key: String(hash, radix: 16), passes: list)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(state)) ?? Data()
    }

    /// Changes the running game's filter: no filter, another one, a new strength, or a custom filter's edited code.
    /// Writes nothing when nothing changed, so it can be called every second.
    public static func update(_ setting: FilterSetting?, custom: [CustomFilter], copy: URL) {
        let data = state(setting, passes: passes(setting, custom: custom) ?? [])
        let file = liveFile(copy)
        if (try? Data(contentsOf: file)) != data { try? data.write(to: file, options: .atomic) }
    }

    /// The error Ren'Py gave for the last filter it couldn't compile, if any.
    public static func lastError(copy: URL) -> String? {
        let text = (try? String(contentsOf: errorFile(copy), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// Puts the loader in `copy` for a runtime, or removes it (and its compiled .rpyc). It goes in on every runtime
    /// that can draw a filter, even with no filter, so one can be picked while the game runs. Until then it draws
    /// nothing extra, and on the camera tier it leaves the game's own camera alone. Returns the tier used,
    /// or .unsupported when the loader is out.
    @discardableResult
    public static func install(_ setting: FilterSetting?, runtime: String, copy: URL, custom: [CustomFilter] = []) throws -> FilterTier {
        let tier = FilterTier.forRuntime(runtime)
        let passes = passes(setting, custom: custom)
        let wanted = tier != .unsupported
        guard wanted else {
            CopyScript.remove(named: fileName, from: copy)
            for url in [liveFile(copy), errorFile(copy)] { try? FileManager.default.removeItem(at: url) }
            return .unsupported
        }
        try? FileManager.default.removeItem(at: errorFile(copy))
        try? FileManager.default.removeItem(at: copy.appending(path: "renchan_filter_strength.txt"))
        try state(setting, passes: passes ?? []).write(to: liveFile(copy), options: .atomic)
        try CopyScript.place(source(tier: tier, liveFile: liveFile(copy), errorFile: errorFile(copy)), named: fileName, in: copy)
        return tier
    }

    /// Ren'Py script that runs on Python 2 (7.x) and Python 3 (8.x). Any failure leaves the game as it was.
    public static func source(tier: FilterTier, liveFile: URL, errorFile: URL) -> String {
        // Python 2 and 3 both read these string literals; the paths never have a quote in them, but escape anyway.
        func literal(_ url: URL) -> String {
            url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        // Slots on the whole screen (None) and on the game's images ("master"); the camera tier has one set, "*", for every pass.
        func transforms(_ layer: String) -> String {
            (0..<slots).map { "Transform(function=renchan_filter_slot(\($0), \(layer)))" }.joined(separator: ", ")
        }
        let apply: String
        switch tier {
        case .layerTransforms:
            apply = """
                    config.layer_transforms.setdefault(None, [])
                    config.layer_transforms[None] = list(config.layer_transforms[None]) + renchan_filter_transforms
                    config.layer_transforms["master"] = list(config.layer_transforms.get("master", [])) + renchan_filter_image_transforms
            """
        case .camera, .unsupported:
            apply = """
                    # The game's own camera stays its own until a filter is picked; from then on RenChan's is set
                    # again at each interaction, since scene and the game's camera statements clear it.
                    def renchan_filter_camera():
                        try:
                            if renchan_filter["passes"] or renchan_filter["shown"]:
                                renchan_filter["shown"] = True
                                renpy.show_layer_at(renchan_filter_transforms, layer="master", reset=False, camera=True)
                        except Exception:
                            pass
                    config.interact_callbacks.append(renchan_filter_camera)

                    # Before the camera is set, nothing reads the state file: check it twice a second, and redraw
                    # once a filter is picked so it shows within a second, as on newer Ren'Py.
                    def renchan_filter_poll():
                        try:
                            if renchan_filter["shown"]:
                                return
                            now = renchan_time.time()
                            if now - renchan_filter["checked"] < 0.5:
                                return
                            renchan_filter["checked"] = now
                            renchan_filter_read(True)
                            if renchan_filter["passes"]:
                                renpy.restart_interaction()
                        except Exception:
                            pass
                    config.periodic_callbacks.append(renchan_filter_poll)
            """
        }
        return #"""
        # Written by RenChan before each launch, in RenChan's copy of the game only.
        # The filter comes from renchan_filter.json, which RenChan rewrites while the game runs.
        init 999 python:
            try:
                if getattr(config, "gl2", True):
                    import time as renchan_time
                    import json as renchan_json
                    import os as renchan_os
                    renchan_filter = {"checked": 0.0, "mtime": None, "strength": 0.0, "key": None,
                                      "passes": [], "count": 0, "shown": False, "path": "\#(literal(liveFile))", "error": "\#(literal(errorFile))"}
                    # Declares RenChan's uniform at init, so filters registered later can use it.
                    renpy.register_shader("renchan.base", variables="""
                        uniform float u_renchan_strength;
                    """)

                    def renchan_filter_register(name, functions, fragment):
                        code = "\n".join("    " + line for line in fragment.split("\n"))
                        body = "\n    vec3 c = gl_FragColor.rgb;\n    float s = u_renchan_strength;\n    vec2 px = vec2(1.0) / res0;\n" + code + "\n    gl_FragColor = vec4(c, gl_FragColor.a);\n"
                        variables = """
                            uniform sampler2D tex0;
                            uniform vec2 res0;
                            uniform float u_renchan_strength;
                            varying vec2 v_tex_coord;
                        """
                        if functions:
                            renpy.register_shader(name, variables=variables, fragment_functions=functions, fragment_300=body)
                        else:
                            renpy.register_shader(name, variables=variables, fragment_300=body)

                    # Ren'Py's shader cache: a public attribute from 8.2 and 7.7; before that a private one, found once
                    # among Python's objects. None when it can't be found: the shader then compiles when it's drawn.
                    def renchan_filter_cache():
                        cache = getattr(renpy.display.draw, "shader_cache", None)
                        if cache is not None:
                            return cache
                        if "cache" not in renchan_filter:
                            renchan_filter["cache"] = None
                            try:
                                import gc
                                from renpy.gl2.gl2shadercache import ShaderCache
                                for item in gc.get_objects():
                                    if isinstance(item, ShaderCache):
                                        renchan_filter["cache"] = item
                                        break
                            except Exception:
                                pass
                        return renchan_filter["cache"]

                    def renchan_filter_read(compile_now):
                        st = renchan_filter
                        try:
                            mtime = renchan_os.path.getmtime(st["path"])
                        except Exception:
                            return
                        if mtime == st["mtime"]:
                            return
                        st["mtime"] = mtime
                        try:
                            with open(st["path"]) as f:
                                text = f.read()
                        except Exception:
                            return
                        try:
                            st["strength"] = max(0.0, min(1.0, float(text.strip())))
                            return
                        except ValueError:
                            pass
                        try:
                            data = renchan_json.loads(text)
                            st["strength"] = max(0.0, min(1.0, float(data.get("strength", 1.0))))
                            key = data.get("key")
                            if key == st["key"]:
                                return
                            st["key"] = key
                            passes = data.get("passes") or []
                            st["count"] += 1
                            names = []
                            for index, p in enumerate(passes[:\#(slots)]):
                                name = str("renchan.live%d_%d" % (st["count"], index))
                                renchan_filter_register(name, p.get("functions") or "", p.get("fragment") or "")
                                names.append(name)
                            if compile_now:
                                # Ren'Py compiles a shader when it first draws it; a mistake there would stop the game.
                                # Compiling here instead keeps the last filter and reports the mistake to RenChan.
                                # Pinned, Ren'Py 8.6 reports the shader's own error instead of retrying it in an older GLSL.
                                cache = renchan_filter_cache()
                                pinned = getattr(cache, "pinned", None)
                                if pinned is not None:
                                    cache.pinned = True
                                try:
                                    # Ren'Py draws a mesh with renpy.texture, whose vertex shader writes v_tex_coord.
                                    for name in names:
                                        if cache is not None:
                                            cache.get((name, "renpy.texture"))
                                finally:
                                    if pinned is not None:
                                        cache.pinned = pinned
                            st["passes"] = [(n, bool(p.get("game")), p.get("layer")) for n, p in zip(names, passes)]
                            message = ""
                        except Exception as e:
                            message = "%s" % (e,)
                            renpy.write_log("RenChan filter kept the last one: %r" % (e,))
                        try:
                            with open(st["error"], "w") as f:
                                f.write(message)
                        except Exception:
                            pass

                    renchan_filter_read(False)

                    def renchan_filter_slot(index, layer):
                        def function(trans, st, at):
                            now = renchan_time.time()
                            if index == 0 and layer != "master" and now - renchan_filter["checked"] >= 0.5:
                                renchan_filter["checked"] = now
                                renchan_filter_read(True)
                            mine = [p for p in renchan_filter["passes"] if layer == "*" or p[2] == layer]
                            try:
                                if index < len(mine):
                                    trans.mesh = True
                                    trans.shader = mine[index][0]
                                    trans.gl_drawable_resolution = not mine[index][1]
                                    trans.u_renchan_strength = renchan_filter["strength"]
                                else:
                                    trans.mesh = False
                                    trans.shader = None
                                    trans.gl_drawable_resolution = True
                            except Exception:
                                pass
                            return 0.5
                        return function

                    renchan_filter_transforms = [\#(tier == .camera ? transforms("\"*\"") : transforms("None"))]
                    renchan_filter_image_transforms = [\#(transforms("\"master\""))]
        \#(apply)
            except Exception as e:
                renpy.write_log("RenChan filter off: %r" % (e,))

        """#
    }
}
