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
