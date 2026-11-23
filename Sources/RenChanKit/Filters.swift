import Foundation

/// A screen filter RenChan can lay over a whole game (S-014). Each is a GLSL 1.00 fragment that changes
/// `gl_FragColor` after Ren'Py has drawn the screen, so it works on every GL2 renderer RenChan runs.
public enum ScreenFilter: String, Codable, CaseIterable, Sendable {
    case sharpen, crt, nightWarmth, grayscale, protanopia, deuteranopia, tritanopia

    /// The fragment code. `c` is the screen's color, `s` the strength from 0 to 1, `px` one pixel in texture units.
    var fragment: String {
        switch self {
        case .grayscale:
            return "c = mix(c, vec3(dot(c, vec3(0.299, 0.587, 0.114))), s);"
        case .nightWarmth:
            return "c = c * vec3(1.0, 1.0 - 0.18 * s, 1.0 - 0.45 * s);"
        case .sharpen:
            return """
            vec3 around = texture2D(tex0, v_tex_coord + vec2(px.x, 0.0)).rgb + texture2D(tex0, v_tex_coord - vec2(px.x, 0.0)).rgb
                        + texture2D(tex0, v_tex_coord + vec2(0.0, px.y)).rgb + texture2D(tex0, v_tex_coord - vec2(0.0, px.y)).rgb;
            c = clamp(c + 0.6 * s * (4.0 * c - around), 0.0, 1.0);
            """
        case .crt:
            return """
            float line = 0.5 + 0.5 * sin(v_tex_coord.y / px.y * 3.14159);
            c = c * (1.0 - 0.3 * s * line);
            vec2 d = v_tex_coord - vec2(0.5);
            c = c * (1.0 - s * 0.6 * dot(d, d));
            """
        case .protanopia, .deuteranopia, .tritanopia:
            // Daltonize: simulate what the eye misses in LMS space, then move that difference to colors it sees.
            return """
            vec3 lms = mat3(17.8824, 3.45565, 0.0299566, 43.5161, 27.1554, 0.184309, 4.11935, 3.86714, 1.46709) * c;
            vec3 seen = \(simulation) * lms;
            vec3 back = mat3(0.0809444479, -0.0102485335, -0.000365296938, -0.130504409, 0.0540193266, -0.00412161469,
                             0.116721066, -0.113614708, 0.693511405) * seen;
            vec3 err = c - back;
            vec3 shift = vec3(0.0, err.r * 0.7 + err.g, err.r * 0.7 + err.b);
            c = clamp(c + s * shift, 0.0, 1.0);
            """
        }
    }

    /// The LMS matrix of the missing cone, column by column as GLSL reads it.
    private var simulation: String {
        switch self {
        case .protanopia: return "mat3(0.0, 0.0, 0.0, 2.02344, 1.0, 0.0, -2.52581, 0.0, 1.0)"
        case .deuteranopia: return "mat3(1.0, 0.494207, 0.0, 0.0, 0.0, 0.0, 0.0, 1.24827, 1.0)"
        default: return "mat3(1.0, 0.0, -0.395913, 0.0, 1.0, 0.801109, 0.0, 0.0, 0.0)"
        }
    }
}

/// The filter a game plays with, and how strong it is.
public struct FilterSetting: Codable, Hashable, Sendable {
    public var filter: ScreenFilter
    /// 0 to 1.
    public var strength: Double

    public init(filter: ScreenFilter, strength: Double = 1) {
        self.filter = filter
        self.strength = min(1, max(0, strength))
    }
}

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
public enum FilterLoader {
    /// Sorted after the game's own files; Ren'Py compiles it next to itself as .rpyc.
    public static let fileName = "zz_renchan_filter.rpy"

    /// The strength while the game runs (S-015): a number from 0 to 1 in the copy's base folder, outside game/.
    /// The loader reads it about once a second.
    public static func liveFile(_ copy: URL) -> URL { copy.appending(path: "renchan_filter_strength.txt") }

    public static func writeStrength(_ strength: Double, copy: URL) {
        try? String(format: "%.3f", min(1, max(0, strength))).write(to: liveFile(copy), atomically: true, encoding: .utf8)
    }

    /// Puts the filter in `copy` for a runtime, or removes it (and its compiled .rpyc) when there is no filter or no tier.
    /// Returns the tier used.
    @discardableResult
    public static func install(_ setting: FilterSetting?, runtime: String, copy: URL) throws -> FilterTier {
        let file = copy.appending(path: "game/\(fileName)")
        let compiled = file.deletingPathExtension().appendingPathExtension("rpyc")
        let tier = FilterTier.forRuntime(runtime)
        guard let setting, tier != .unsupported else {
            for url in [file, compiled, liveFile(copy)] { try? FileManager.default.removeItem(at: url) }
            return .unsupported
        }
        writeStrength(setting.strength, copy: copy)
        let text = source(setting, tier: tier, liveFile: liveFile(copy))
        if (try? String(contentsOf: file, encoding: .utf8)) != text {
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        return tier
    }

    /// Ren'Py script that runs on Python 2 (7.x) and Python 3 (8.x). Any failure leaves the game as it was.
    public static func source(_ setting: FilterSetting, tier: FilterTier, liveFile: URL? = nil) -> String {
        let strength = String(format: "%.3f", setting.strength)
        // Python 2 and 3 both read this string literal; the path never has a quote in it, but escape anyway.
        let path = (liveFile?.path ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let fragment = setting.filter.fragment.split(separator: "\n").map { "        " + $0 }.joined(separator: "\n")
        let apply: String
        switch tier {
        case .layerTransforms:
            apply = """
                    config.layer_transforms.setdefault(None, [])
                    config.layer_transforms[None] = list(config.layer_transforms[None]) + [renchan_filter_transform]
            """
        case .camera, .unsupported:
            apply = """
                    def renchan_filter_camera():
                        try:
                            renpy.show_layer_at([renchan_filter_transform], layer="master", reset=False, camera=True)
                        except Exception:
                            pass
                    config.interact_callbacks.append(renchan_filter_camera)
            """
        }
        return #"""
        # Written by RenChan before each launch, in RenChan's copy of the game only. Filter: \#(setting.filter.rawValue).
        init 999 python:
            try:
                if getattr(config, "gl2", True):
                    renpy.register_shader("renchan.filter", variables="""
                        uniform sampler2D tex0;
                        uniform vec2 res0;
                        uniform float u_renchan_strength;
                        varying vec2 v_tex_coord;
                    """, fragment_300="""
                        vec3 c = gl_FragColor.rgb;
                        float s = u_renchan_strength;
                        vec2 px = vec2(1.0) / res0;
        \#(fragment)
                        gl_FragColor = vec4(c, gl_FragColor.a);
                    """)
                    import time as renchan_time
                    def renchan_filter_function(trans, st, at, _live=[0.0, \#(strength)]):
                        now = renchan_time.time()
                        if now - _live[0] >= 1.0:
                            _live[0] = now
                            try:
                                with open("\#(path)") as f:
                                    _live[1] = max(0.0, min(1.0, float(f.read().strip())))
                            except Exception:
                                pass
                        trans.u_renchan_strength = _live[1]
                        return 1.0
                    renchan_filter_transform = Transform(mesh=True, shader="renchan.filter", u_renchan_strength=\#(strength),
                                                         function=renchan_filter_function)
        \#(apply)
            except Exception as e:
                renpy.write_log("RenChan filter off: %r" % (e,))

        """#
    }
}
