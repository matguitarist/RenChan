import Foundation
import Testing
@testable import RenChanKit

@Test func eachRuntimeGetsItsFilterTier() {
    #expect(FilterTier.forRuntime("8.6.1") == .layerTransforms)
    #expect(FilterTier.forRuntime("8.2.0") == .layerTransforms)
    #expect(FilterTier.forRuntime("7.8.7") == .layerTransforms)
    #expect(FilterTier.forRuntime("7.7.0") == .layerTransforms)
    #expect(FilterTier.forRuntime("8.1.3") == .camera)
    #expect(FilterTier.forRuntime("7.6.3") == .camera)
    #expect(FilterTier.forRuntime("7.4.6") == .camera)
    #expect(FilterTier.forRuntime("7.4.5") == .unsupported)
    #expect(FilterTier.forRuntime("6.99.14.3") == .unsupported)
}

@Test func theLoaderUsesLayerTransformsOrCamera() {
    let setting = FilterSetting(filter: .grayscale, strength: 0.5)
    let modern = FilterLoader.source(setting, tier: .layerTransforms)
    #expect(modern.contains("config.layer_transforms[None]") && modern.contains("u_renchan_strength=0.500"))
    #expect(!modern.contains("gl_drawable_resolution") && !modern.contains("renchan.filter1"))
    // S-031: FSR Upscale is two passes, the first from the game's own resolution.
    let fsr = FilterLoader.source(FilterSetting(filter: .fsrUpscale), tier: .layerTransforms)
    #expect(fsr.contains("renchan.filter1") && fsr.contains("gl_drawable_resolution=False") && fsr.contains("fragment_functions="))
    #expect(modern.contains("init 999 python:") && modern.contains("except Exception"))
    let older = FilterLoader.source(setting, tier: .camera)
    #expect(older.contains("camera=True") && !older.contains("layer_transforms"))
    // No f-strings or other Python 3 only syntax: 7.x runs Python 2.
    #expect(!modern.contains("f\"") && !older.contains("f\""))
    for filter in ScreenFilter.allCases { #expect(!filter.fragment.isEmpty) }
}

@Test func turningAFilterOffRemovesItsFilesFromTheCopy() throws {
    let copy = Fixture.game(at: Fixture.folder().appending(path: "play"))
    let file = copy.appending(path: "game/\(FilterLoader.fileName)")
    let compiled = copy.appending(path: "game/zz_renchan_filter.rpyc")
    #expect(try FilterLoader.install(FilterSetting(filter: .crt, strength: 0.4), runtime: "8.6.1", copy: copy) == .layerTransforms)
    #expect(FileManager.default.fileExists(atPath: file.path))
    // S-015: the strength is in a file the loader reads each second, outside game/.
    let live = FilterLoader.liveFile(copy)
    #expect(try String(contentsOf: live, encoding: .utf8) == "0.400")
    #expect(try String(contentsOf: file, encoding: .utf8).contains(live.path))
    FilterLoader.writeStrength(1.7, copy: copy)
    #expect(try String(contentsOf: live, encoding: .utf8) == "1.000")
    try "compiled".write(to: compiled, atomically: true, encoding: .utf8)
    try FilterLoader.install(nil, runtime: "8.6.1", copy: copy)
    #expect(!FileManager.default.fileExists(atPath: file.path) && !FileManager.default.fileExists(atPath: compiled.path))
    #expect(!FileManager.default.fileExists(atPath: live.path))
    // A runtime too old for filters gets no file either.
    #expect(try FilterLoader.install(FilterSetting(filter: .crt), runtime: "7.3.5", copy: copy) == .unsupported)
    #expect(!FileManager.default.fileExists(atPath: file.path))
}

@Test func aCustomFilterNeedsAHeaderWithANameAndSomeCode() throws {
    let sepia = try CustomFilter.parse("""
    // {"name": "Sepia"}
    c = vec3(dot(c, vec3(0.393, 0.769, 0.189)), dot(c, vec3(0.349, 0.686, 0.168)), dot(c, vec3(0.272, 0.534, 0.131)));
    """, file: "Sepia.glsl")
    #expect(sepia.name == "Sepia" && sepia.fragment.hasPrefix("c = vec3"))
    #expect(try CustomFilter.parse("/* {\"name\": \"Dim\"} */\nc = c * 0.5;", file: "Dim.glsl").name == "Dim")
    #expect(throws: CustomFilter.Problem.noHeader) { try CustomFilter.parse("c = c * 0.5;", file: "x.glsl") }
    #expect(throws: CustomFilter.Problem.noName) { try CustomFilter.parse("// {\"title\": \"Dim\"}\nc = c * 0.5;", file: "x.glsl") }
    #expect(throws: CustomFilter.Problem.noCode) { try CustomFilter.parse("// {\"name\": \"Dim\"}\n", file: "x.glsl") }
}

@Test func customFiltersAreCopiedInAndUsedByTheLoader() throws {
    let root = Fixture.folder()
    let source = root.appending(path: "Dim.glsl")
    try "// {\"name\": \"Dim\"}\nc = c * (1.0 - 0.5 * s);".write(to: source, atomically: true, encoding: .utf8)
    let folder = root.appending(path: "Filters")
    try CustomFilters.add(source, to: folder)
    try "not a filter".write(to: folder.appending(path: "Broken.glsl"), atomically: true, encoding: .utf8)
    let found = CustomFilters.list(in: folder)
    #expect(found.map(\.name) == ["Dim"])
    let copy = Fixture.game(at: root.appending(path: "play"))
    try FilterLoader.install(FilterSetting(custom: "Dim.glsl"), runtime: "8.6.1", copy: copy, custom: found)
    let text = try String(contentsOf: copy.appending(path: "game/\(FilterLoader.fileName)"), encoding: .utf8)
    #expect(text.contains("c = c * (1.0 - 0.5 * s);") && text.contains("Filter: Dim.glsl"))
    // A filter whose file is gone plays without a filter.
    #expect(try FilterLoader.install(FilterSetting(custom: "Gone.glsl"), runtime: "8.6.1", copy: copy, custom: found) == .unsupported)
    #expect(!FileManager.default.fileExists(atPath: copy.appending(path: "game/\(FilterLoader.fileName)").path))
}
