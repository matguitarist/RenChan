import Foundation

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
