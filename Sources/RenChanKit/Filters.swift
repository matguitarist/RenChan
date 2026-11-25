import Foundation

/// A screen filter RenChan can lay over a whole game (S-014). Each is a GLSL 1.00 fragment that changes
/// `gl_FragColor` after Ren'Py has drawn the screen, so it works on every GL2 renderer RenChan runs.
public enum ScreenFilter: String, Codable, CaseIterable, Sendable {
    case sharpen, crt, nightWarmth, grayscale, protanopia, deuteranopia, tritanopia
    /// AMD FidelityFX FSR 1 (MIT): RCAS alone, or EASU from the game's own resolution then RCAS (S-031).
    case fsrSharpen, fsrUpscale

    /// The shader passes, in order. Most filters are one pass on the screen as drawn.
    public var passes: [FilterPass] {
        switch self {
        case .fsrSharpen: [FSR.rcas]
        case .fsrUpscale: [FSR.easu, FSR.rcas]
        default: [FilterPass(fragment: fragment)]
        }
    }

    /// The fragment code. `c` is the screen's color, `s` the strength from 0 to 1, `px` one pixel in texture units.
    var fragment: String {
        switch self {
        case .fsrSharpen, .fsrUpscale:
            return FSR.rcas.fragment
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

/// One shader pass of a filter.
public struct FilterPass: Hashable, Sendable {
    /// GLSL function definitions the fragment calls.
    public var functions = ""
    /// Changes `c`; can read `s`, `px`, `tex0`, `v_tex_coord` and `res0`.
    public var fragment: String
    /// Draws from the game's own resolution (config.screen_width) instead of the screen's: what an upscaler needs.
    public var gameResolution = false
    /// Draws on the game's images only (the master layer), so text, the dialogue box and menus stay as Ren'Py drew
    /// them at the screen's resolution. On the camera tier every filter is on the master layer anyway.
    public var imagesOnly = false

    public init(functions: String = "", fragment: String, gameResolution: Bool = false, imagesOnly: Bool = false) {
        self.functions = functions
        self.fragment = fragment
        self.gameResolution = gameResolution
        self.imagesOnly = imagesOnly
    }
}


/// The filter a game plays with, and how strong it is.
public struct FilterSetting: Codable, Hashable, Sendable {
    /// A built-in filter. Ignored when `custom` is set.
    public var filter: ScreenFilter
    /// The file name of one of the person's own filters (S-016), such as "Sepia.glsl".
    public var custom: String?
    /// 0 to 1.
    public var strength: Double

    public init(filter: ScreenFilter, strength: Double = 1) {
        self.filter = filter
        self.strength = min(1, max(0, strength))
    }

    public init(custom: String, strength: Double = 1) {
        self.init(filter: .grayscale, strength: strength)
        self.custom = custom
    }

    /// For the log and the loader's first line.
    public var name: String { custom ?? filter.rawValue }
}
