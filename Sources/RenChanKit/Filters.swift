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

/// AMD FidelityFX Super Resolution 1, ported to GLSL 1.00 from the MIT-licensed ffx_fsr1.h
/// (Copyright (c) 2021 Advanced Micro Devices, Inc.; MIT license in THIRD-PARTY.md). EASU upscales with edge-aware
/// Lanczos taps; RCAS sharpens. Measured on a hard edge, 640×360 to 3840×2160: 4 px of ramp against Ren'Py's 6.
enum FSR {
    static let easu = FilterPass(functions: """
    float renchan_luma(vec3 c) { return c.b * 0.5 + (c.r * 0.5 + c.g); }
    void renchan_easu_set(inout vec2 dir, inout float len, float w, float lA, float lB, float lC, float lD, float lE) {
        float lenX = 1.0 / max(max(abs(lD - lC), abs(lC - lB)), 1e-5);
        float dirX = lD - lB;
        dir.x += dirX * w;
        lenX = clamp(abs(dirX) * lenX, 0.0, 1.0);
        len += lenX * lenX * w;
        float lenY = 1.0 / max(max(abs(lE - lC), abs(lC - lA)), 1e-5);
        float dirY = lE - lA;
        dir.y += dirY * w;
        lenY = clamp(abs(dirY) * lenY, 0.0, 1.0);
        len += lenY * lenY * w;
    }
    void renchan_easu_tap(inout vec3 aC, inout float aW, vec2 off, vec2 dir, vec2 len, float lob, float clp, vec3 c) {
        vec2 v = vec2(off.x * dir.x + off.y * dir.y, off.x * (-dir.y) + off.y * dir.x) * len;
        float d2 = min(v.x * v.x + v.y * v.y, clp);
        float wB = 2.0 / 5.0 * d2 - 1.0;
        float wA = lob * d2 - 1.0;
        wB *= wB;
        wA *= wA;
        wB = 25.0 / 16.0 * wB - (25.0 / 16.0 - 1.0);
        float w = wB * wA;
        aC += c * w;
        aW += w;
    }
    """, fragment: """
    vec2 pp = v_tex_coord * res0 - vec2(0.5);
    vec2 fp = floor(pp);
    pp -= fp;
    vec2 t = vec2(1.0) / res0;
    vec2 p0 = (fp + vec2(0.5)) * t;
    vec3 bC = texture2D(tex0, p0 + vec2(0.0, -1.0) * t).rgb;
    vec3 cC = texture2D(tex0, p0 + vec2(1.0, -1.0) * t).rgb;
    vec3 eC = texture2D(tex0, p0 + vec2(-1.0, 0.0) * t).rgb;
    vec3 fC = texture2D(tex0, p0).rgb;
    vec3 gC = texture2D(tex0, p0 + vec2(1.0, 0.0) * t).rgb;
    vec3 hC = texture2D(tex0, p0 + vec2(2.0, 0.0) * t).rgb;
    vec3 iC = texture2D(tex0, p0 + vec2(-1.0, 1.0) * t).rgb;
    vec3 jC = texture2D(tex0, p0 + vec2(0.0, 1.0) * t).rgb;
    vec3 kC = texture2D(tex0, p0 + vec2(1.0, 1.0) * t).rgb;
    vec3 lC = texture2D(tex0, p0 + vec2(2.0, 1.0) * t).rgb;
    vec3 nC = texture2D(tex0, p0 + vec2(0.0, 2.0) * t).rgb;
    vec3 oC = texture2D(tex0, p0 + vec2(1.0, 2.0) * t).rgb;
    float bL = renchan_luma(bC); float cL = renchan_luma(cC); float eL = renchan_luma(eC); float fL = renchan_luma(fC);
    float gL = renchan_luma(gC); float hL = renchan_luma(hC); float iL = renchan_luma(iC); float jL = renchan_luma(jC);
    float kL = renchan_luma(kC); float lL = renchan_luma(lC); float nL = renchan_luma(nC); float oL = renchan_luma(oC);
    vec2 dir = vec2(0.0);
    float len = 0.0;
    renchan_easu_set(dir, len, (1.0 - pp.x) * (1.0 - pp.y), bL, eL, fL, gL, jL);
    renchan_easu_set(dir, len, pp.x * (1.0 - pp.y), cL, fL, gL, hL, kL);
    renchan_easu_set(dir, len, (1.0 - pp.x) * pp.y, fL, iL, jL, kL, nL);
    renchan_easu_set(dir, len, pp.x * pp.y, gL, jL, kL, lL, oL);
    float dirR = dir.x * dir.x + dir.y * dir.y;
    if (dirR < 1.0 / 32768.0) { dir = vec2(1.0, 0.0); } else { dir *= inversesqrt(dirR); }
    len = len * 0.5;
    len *= len;
    float stretch = (dir.x * dir.x + dir.y * dir.y) / max(abs(dir.x), abs(dir.y));
    vec2 len2 = vec2(1.0 + (stretch - 1.0) * len, 1.0 - 0.5 * len);
    float lob = 0.5 + ((1.0 / 4.0 - 0.04) - 0.5) * len;
    float clp = 1.0 / lob;
    vec3 aC = vec3(0.0);
    float aW = 0.0;
    renchan_easu_tap(aC, aW, vec2(0.0, -1.0) - pp, dir, len2, lob, clp, bC);
    renchan_easu_tap(aC, aW, vec2(1.0, -1.0) - pp, dir, len2, lob, clp, cC);
    renchan_easu_tap(aC, aW, vec2(-1.0, 1.0) - pp, dir, len2, lob, clp, iC);
    renchan_easu_tap(aC, aW, vec2(0.0, 1.0) - pp, dir, len2, lob, clp, jC);
    renchan_easu_tap(aC, aW, vec2(0.0, 0.0) - pp, dir, len2, lob, clp, fC);
    renchan_easu_tap(aC, aW, vec2(-1.0, 0.0) - pp, dir, len2, lob, clp, eC);
    renchan_easu_tap(aC, aW, vec2(1.0, 1.0) - pp, dir, len2, lob, clp, kC);
    renchan_easu_tap(aC, aW, vec2(2.0, 1.0) - pp, dir, len2, lob, clp, lC);
    renchan_easu_tap(aC, aW, vec2(2.0, 0.0) - pp, dir, len2, lob, clp, hC);
    renchan_easu_tap(aC, aW, vec2(1.0, 0.0) - pp, dir, len2, lob, clp, gC);
    renchan_easu_tap(aC, aW, vec2(1.0, 2.0) - pp, dir, len2, lob, clp, oC);
    renchan_easu_tap(aC, aW, vec2(0.0, 2.0) - pp, dir, len2, lob, clp, nC);
    c = clamp(aC / max(aW, 1e-5), min(min(fC, gC), min(jC, kC)), max(max(fC, gC), max(jC, kC)));
    """, gameResolution: true, imagesOnly: true)

    /// Strength 1 is AMD's sharpest setting.
    static let rcas = FilterPass(fragment: """
    vec3 rb = texture2D(tex0, v_tex_coord + vec2(0.0, -px.y)).rgb;
    vec3 rd = texture2D(tex0, v_tex_coord + vec2(-px.x, 0.0)).rgb;
    vec3 rf = texture2D(tex0, v_tex_coord + vec2(px.x, 0.0)).rgb;
    vec3 rh = texture2D(tex0, v_tex_coord + vec2(0.0, px.y)).rgb;
    vec3 mn4 = min(min(rb, rd), min(rf, rh));
    vec3 mx4 = max(max(rb, rd), max(rf, rh));
    vec3 hitMin = min(mn4, c) / max(4.0 * mx4, vec3(1e-4));
    vec3 hitMax = (vec3(1.0) - max(mx4, c)) / min(4.0 * mn4 - vec3(4.0), vec3(-1e-4));
    vec3 lobeRGB = max(-hitMin, hitMax);
    float lobe = max(-0.1875, min(max(lobeRGB.r, max(lobeRGB.g, lobeRGB.b)), 0.0)) * s;
    c = clamp((lobe * (rb + rd + rf + rh) + c) / (4.0 * lobe + 1.0), 0.0, 1.0);
    """, imagesOnly: true)
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

/// A filter the person added (S-016): a .glsl file in RenChan's Filters folder whose first line is a JSON header,
/// `// {"name": "Sepia"}` or `/* {"name": "Sepia"} */`, followed by fragment code like the built-in ones:
/// it changes `c` (the color), and can read `s` (strength), `px` (one pixel), `tex0` and `v_tex_coord`.
public struct CustomFilter: Hashable, Sendable, Identifiable {
    public var file: String
    public var name: String
    public var fragment: String
    public var id: String { file }

    public enum Problem: Error, Equatable {
        case noHeader, noName, noCode
    }

    private struct Header: Decodable { var name: String? }

    public static func parse(_ text: String, file: String) throws -> CustomFilter {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let header: Substring
        let body: Substring
        if trimmed.hasPrefix("/*"), let end = trimmed.range(of: "*/") {
            header = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<end.lowerBound]
            body = trimmed[end.upperBound...]
        } else if trimmed.hasPrefix("//") {
            let line = trimmed.firstIndex(of: "\n") ?? trimmed.endIndex
            header = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<line]
            body = trimmed[line...]
        } else {
            throw Problem.noHeader
        }
        guard let parsed = try? JSONDecoder().decode(Header.self, from: Data(header.utf8)) else { throw Problem.noHeader }
        guard let name = parsed.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { throw Problem.noName }
        let code = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw Problem.noCode }
        return CustomFilter(file: file, name: name, fragment: code)
    }
}

/// The person's own filters, one .glsl file each in a folder RenChan owns (S-016).
public enum CustomFilters {
    /// Every filter in `folder` that reads, A to Z by name.
    public static func list(in folder: URL) -> [CustomFilter] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "glsl" }
            .compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).flatMap { try? CustomFilter.parse($0, file: url.lastPathComponent) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Checks the file, then copies it in. A file with the same name is replaced, so a fixed shader updates in place.
    @discardableResult
    public static func add(_ url: URL, to folder: URL) throws -> CustomFilter {
        let filter = try CustomFilter.parse(String(contentsOf: url, encoding: .utf8), file: url.lastPathComponent)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: url.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: url, to: target)
        return filter
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

    /// Puts the loader in `copy` for a runtime, or removes it (and its compiled .rpyc). On 7.7+ and 8.2+ it goes in
    /// even with no filter, so one can be picked while the game runs; it draws nothing extra until then. On the camera
    /// tier it goes in only with a filter. Returns the tier used, or .unsupported when the loader is out.
    @discardableResult
    public static func install(_ setting: FilterSetting?, runtime: String, copy: URL, custom: [CustomFilter] = []) throws -> FilterTier {
        let file = copy.appending(path: "game/\(fileName)")
        let compiled = file.deletingPathExtension().appendingPathExtension("rpyc")
        let tier = FilterTier.forRuntime(runtime)
        let passes = passes(setting, custom: custom)
        let wanted = tier == .layerTransforms || (tier == .camera && setting != nil && passes != nil)
        guard wanted else {
            for url in [file, compiled, liveFile(copy), errorFile(copy)] { try? FileManager.default.removeItem(at: url) }
            return .unsupported
        }
        try? FileManager.default.removeItem(at: errorFile(copy))
        try? FileManager.default.removeItem(at: copy.appending(path: "renchan_filter_strength.txt"))
        try state(setting, passes: passes ?? []).write(to: liveFile(copy), options: .atomic)
        let text = source(tier: tier, liveFile: liveFile(copy), errorFile: errorFile(copy))
        if (try? String(contentsOf: file, encoding: .utf8)) != text {
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
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
                    def renchan_filter_camera():
                        try:
                            renpy.show_layer_at(renchan_filter_transforms, layer="master", reset=False, camera=True)
                        except Exception:
                            pass
                    config.interact_callbacks.append(renchan_filter_camera)
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
                                      "passes": [], "count": 0, "path": "\#(literal(liveFile))", "error": "\#(literal(errorFile))"}
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
                                cache = renpy.display.draw.shader_cache
                                pinned = getattr(cache, "pinned", None)
                                if pinned is not None:
                                    cache.pinned = True
                                try:
                                    # Ren'Py draws a mesh with renpy.texture, whose vertex shader writes v_tex_coord.
                                    for name in names:
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
