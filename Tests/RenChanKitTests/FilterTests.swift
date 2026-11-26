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
    let live = URL(fileURLWithPath: "/tmp/copy/renchan_filter.json"), error = URL(fileURLWithPath: "/tmp/copy/renchan_filter_error.txt")
    let modern = FilterLoader.source(tier: .layerTransforms, liveFile: live, errorFile: error)
    #expect(modern.contains("config.layer_transforms[None]") && modern.contains(live.path) && modern.contains(error.path))
    #expect(modern.contains("renchan_filter_slot(0, None)") && modern.contains("renchan_filter_slot(1, \"master\")"))
    #expect(modern.contains(#"config.layer_transforms["master"]"#))
    #expect(modern.contains("init 999 python:") && modern.contains("except Exception") && modern.contains(#"getattr(renpy.display.draw, "shader_cache", None)"#))
    // Before 8.2 and 7.7 the cache is private: it's found among Python's objects, so a new filter is still checked first.
    #expect(modern.contains("from renpy.gl2.gl2shadercache import ShaderCache"))
    // Ren'Py draws a filter with renpy.texture, the vertex shader that writes v_tex_coord; checking it alone fails.
    #expect(modern.contains(#"cache.get((name, "renpy.texture"))"#))
    let older = FilterLoader.source(tier: .camera, liveFile: live, errorFile: error)
    #expect(older.contains("camera=True") && !older.contains("layer_transforms") && older.contains(#"renchan_filter_slot(0, "*")"#))
    // On the camera tier the game's own camera is left alone until a filter is picked, which a periodic check notices.
    #expect(older.contains(#"if renchan_filter["passes"] or renchan_filter["shown"]:"#) && older.contains("config.periodic_callbacks.append(renchan_filter_poll)"))
    #expect(!modern.contains("periodic_callbacks"))
    // No f-strings or other Python 3 only syntax: 7.x runs Python 2.
    #expect(!modern.contains("f\"") && !older.contains("f\""))
    for filter in ScreenFilter.allCases { #expect(!filter.fragment.isEmpty) }
}

private struct LiveState: Decodable {
    struct Pass: Decodable { var functions: String; var fragment: String; var game: Bool; var layer: String? }
    var strength: Double; var name: String; var key: String; var passes: [Pass]
}

private func liveState(_ copy: URL) throws -> LiveState {
    try JSONDecoder().decode(LiveState.self, from: Data(contentsOf: FilterLoader.liveFile(copy)))
}

@Test func theFilterCanChangeWhileTheGamePlays() throws {
    let copy = Fixture.game(at: Fixture.folder().appending(path: "play"))
    let file = copy.appending(path: "game/\(FilterLoader.fileName)")
    let compiled = copy.appending(path: "game/zz_renchan_filter.rpyc")
    #expect(try FilterLoader.install(FilterSetting(filter: .crt, strength: 0.4), runtime: "8.6.1", copy: copy) == .layerTransforms)
    #expect(FileManager.default.fileExists(atPath: file.path))
    // S-015: the state is in a file the loader reads twice a second, outside game/.
    var state = try liveState(copy)
    #expect(state.strength == 0.4 && state.name == "crt" && state.passes.count == 1)
    let crtKey = state.key
    FilterLoader.update(FilterSetting(filter: .crt, strength: 1.7), custom: [], copy: copy)
    state = try liveState(copy)
    #expect(state.strength == 1 && state.key == crtKey)
    // Another filter changes the key, so the loader compiles it; FSR Upscale has two passes, the first at the game's size.
    FilterLoader.update(FilterSetting(filter: .fsrUpscale), custom: [], copy: copy)
    state = try liveState(copy)
    #expect(state.key != crtKey && state.passes.map(\.game) == [true, false] && !state.passes[0].functions.isEmpty)
    // FSR draws on the game's images only, so Ren'Py's own text stays at the screen's resolution; CRT covers everything.
    #expect(state.passes.map(\.layer) == ["master", "master"])
    FilterLoader.update(FilterSetting(filter: .crt), custom: [], copy: copy)
    #expect(try liveState(copy).passes.map(\.layer) == [nil])
    // None keeps the loader, drawing nothing, so a filter can be picked again while the game runs.
    try "compiled".write(to: compiled, atomically: true, encoding: .utf8)
    #expect(try FilterLoader.install(nil, runtime: "8.6.1", copy: copy) == .layerTransforms)
    #expect(try liveState(copy).passes.isEmpty && FileManager.default.fileExists(atPath: file.path))
    // The camera tier gets the loader without a filter too, so one can be picked while the game runs (it used to
    // go in only with a filter, and a filter picked during play did nothing on 7.4.6 to 8.1).
    #expect(try FilterLoader.install(nil, runtime: "8.1.3", copy: copy) == .camera)
    #expect(FileManager.default.fileExists(atPath: file.path))
    #expect(try liveState(copy).passes.isEmpty)
    #expect(try FilterLoader.install(FilterSetting(filter: .crt), runtime: "8.1.3", copy: copy) == .camera)
    // A runtime too old for filters gets no loader: it's taken out with its .rpyc and its state.
    try "compiled".write(to: compiled, atomically: true, encoding: .utf8)
    #expect(try FilterLoader.install(FilterSetting(filter: .crt), runtime: "7.3.5", copy: copy) == .unsupported)
    #expect(!FileManager.default.fileExists(atPath: file.path) && !FileManager.default.fileExists(atPath: compiled.path))
    #expect(!FileManager.default.fileExists(atPath: FilterLoader.liveFile(copy).path))
    // What Ren'Py reports for a shader it couldn't compile.
    #expect(FilterLoader.lastError(copy: copy) == nil)
    try "0:3: syntax error".write(to: FilterLoader.errorFile(copy), atomically: true, encoding: .utf8)
    #expect(FilterLoader.lastError(copy: copy) == "0:3: syntax error")
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
    let state = try liveState(copy)
    #expect(state.passes.first?.fragment == "c = c * (1.0 - 0.5 * s);" && state.name == "Dim.glsl")
    // A filter whose file is gone plays without a filter.
    try FilterLoader.install(FilterSetting(custom: "Gone.glsl"), runtime: "8.6.1", copy: copy, custom: found)
    #expect(try liveState(copy).passes.isEmpty)
}
