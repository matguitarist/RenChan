import Foundation

/// A mod in RenChan's mod library (S-017): files that go under a game's game/ folder, kept by RenChan, never in the game.
/// One copy serves every game it's added to, such as Universal Ren'Py Mod or a walkthrough (S-021).
public struct Mod: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var added: Date
    /// Paths under game/, such as "walkthrough.rpy" or "URM/0x52_URM.rpa".
    public var files: [String]

    public init(id: UUID = UUID(), name: String, added: Date = .now, files: [String]) {
        self.id = id
        self.name = name
        self.added = added
        self.files = files
    }
}

/// One mod on one game: on or off. A game's list is its load order; a later mod wins a file both have (S-018).
public struct ModUse: Codable, Hashable, Sendable, Identifiable {
    public var mod: UUID
    public var enabled: Bool
    public var id: UUID { mod }

    public init(mod: UUID, enabled: Bool = true) {
        self.mod = mod
        self.enabled = enabled
    }
}

public enum ModError: Error, Equatable {
    /// Not a zip, a folder, or a Ren'Py file.
    case notAMod
    /// No .rpy, .rpyc, .rpa or .rpym in it.
    case noScripts
    case unsafeZip(String)
    case failed(String)
}

/// The mod library: `root/mods.json` and `root/<id>/` with each mod's files laid out as under game/.
public enum ModLibrary {
    static let scriptExtensions: Set<String> = ["rpy", "rpyc", "rpa", "rpym", "rpymc"]
    static let skipped: Set<String> = [".DS_Store", "__MACOSX", "Thumbs.db"]

    public static func load(_ root: URL) -> [Mod] {
        guard let data = try? Data(contentsOf: root.appending(path: "mods.json")) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Mod].self, from: data)) ?? []
    }

    public static func save(_ mods: [Mod], to root: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(mods).write(to: root.appending(path: "mods.json"), options: .atomic)
    }

    public static func folder(_ mod: Mod, root: URL) -> URL { root.appending(path: mod.id.uuidString, directoryHint: .isDirectory) }

    /// Copies a zip, folder or single Ren'Py file into the library. Doesn't save mods.json.
    public static func importMod(_ source: URL, into root: URL) throws(ModError) -> Mod {
        let id = UUID()
        let target = root.appending(path: id.uuidString, directoryHint: .isDirectory)
        let incoming = root.appending(path: ".incoming-\(id.uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: incoming) }
        let name = displayName(source)
        do {
            if GameLocator.isDirectory(source) {
                return try place(contentRoot(source), id: id, name: name, target: target)
            }
            let ext = source.pathExtension.lowercased()
            if scriptExtensions.contains(ext) {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: target.appending(path: source.lastPathComponent))
                return Mod(id: id, name: name, files: [source.lastPathComponent])
            }
            guard ext == "zip" else { throw ModError.notAMod }
            do {
                try ZipImport.unpack(source, into: incoming)
            } catch .unsafeZip(let entry) {
                throw ModError.unsafeZip(entry)
            } catch {
                throw ModError.notAMod
            }
            return try place(contentRoot(incoming), id: id, name: name, target: target)
        } catch let error as ModError {
            try? FileManager.default.removeItem(at: target)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw .failed(error.localizedDescription)
        }
    }

    /// "Eternum_Walkthrough_Mod-0.8" → "Eternum Walkthrough Mod 0.8".
    static func displayName(_ url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        return base.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").joined(separator: " ")
    }

    /// The folder whose contents go under game/: a game/ folder at any depth that holds scripts,
    /// else the folder itself, unwrapping lone folders.
    static func contentRoot(_ folder: URL) -> URL {
        if let found = findManifest(folder, depth: 3) { return found }
        var queue: [(URL, Int)] = [(folder, 0)]
        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()
            let game = children(current).first { $0.lastPathComponent.lowercased() == "game" && GameLocator.isDirectory($0) }
            if let game, hasScripts(game) { return game }
            if depth < 4 { queue += children(current).filter { GameLocator.isDirectory($0) }.map { ($0, depth + 1) } }
        }
        var root = folder
        while true {
            let inside = children(root)
            guard inside.count == 1, let only = inside.first, GameLocator.isDirectory(only), !hasScriptsDirectly(root) else { return root }
            root = only
        }
    }

    static func findManifest(_ folder: URL, depth: Int) -> URL? {
        if FileManager.default.fileExists(atPath: folder.appending(path: ModManifest.fileName).path) { return folder }
        guard depth > 0 else { return nil }
        for child in children(folder) where GameLocator.isDirectory(child) {
            if let found = findManifest(child, depth: depth - 1) { return found }
        }
        return nil
    }

    /// The mod's files now, so files an author adds to a mod made from the template go in at the next launch (S-024).
    public static func currentFiles(_ mod: Mod, root: URL) -> [String] {
        let found = files(in: folder(mod, root: root)).filter { $0 != ModManifest.fileName }
        return found.isEmpty ? mod.files : found
    }

    public static func manifest(_ mod: Mod, root: URL) -> ModManifest? { ModManifest.read(folder(mod, root: root)) }

    static func children(_ folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { !skipped.contains($0.lastPathComponent) && !$0.lastPathComponent.hasPrefix(".") }
    }

    static func hasScriptsDirectly(_ folder: URL) -> Bool {
        children(folder).contains { scriptExtensions.contains($0.pathExtension.lowercased()) }
    }

    static func hasScripts(_ folder: URL) -> Bool { !files(in: folder).filter { scriptExtensions.contains(($0 as NSString).pathExtension.lowercased()) }.isEmpty }

    /// Every file under `folder`, as paths relative to it.
    static func files(in folder: URL) -> [String] {
        let base = folder.resolvingSymlinksInPath().path
        guard let walker = FileManager.default.enumerator(at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var found: [String] = []
        for case let url as URL in walker {
            if skipped.contains(url.lastPathComponent) || url.lastPathComponent.hasPrefix(".") {
                walker.skipDescendants()
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            found.append(String(url.resolvingSymlinksInPath().path.dropFirst(base.count + 1)))
        }
        return found.sorted()
    }

    static func place(_ content: URL, id: UUID, name: String, target: URL) throws -> Mod {
        let manifest = ModManifest.read(content)
        let files = files(in: content).filter { $0 != ModManifest.fileName || manifest == nil }
        guard files.contains(where: { scriptExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) else { throw ModError.noScripts }
        for file in files {
            let destination = target.appending(path: file)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: content.appending(path: file), to: destination)
        }
        if manifest != nil { try FileManager.default.copyItem(at: content.appending(path: ModManifest.fileName), to: target.appending(path: ModManifest.fileName)) }
        return Mod(id: id, name: manifest?.name ?? name, files: files)
    }
}

/// Puts exactly the enabled mods into the modded working copy before a launch (S-018).
public enum ModInstaller {
    /// What RenChan placed last time, under game/.
    public static func manifest(_ copy: URL) -> URL { copy.appending(path: "renchan_mods.json") }

    /// Takes out what was placed before (bringing back the game's own files), then places `mods` in order.
    /// Returns the paths placed.
    @discardableResult
    public static func apply(_ mods: [Mod], root: URL, base: URL, copy: URL) throws -> [String] {
        let fm = FileManager.default
        let game = copy.appending(path: "game", directoryHint: .isDirectory)
        let placedBefore = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: manifest(copy)))) ?? []
        for path in placedBefore {
            for variant in compiledVariants(path) {
                let url = game.appending(path: variant)
                try? fm.removeItem(at: url)
                let original = base.appending(path: "game/\(variant)")
                if fm.fileExists(atPath: original.path) {
                    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: original, to: url)
                }
            }
        }
        var placed: [String] = []
        for mod in mods {
            let folder = ModLibrary.folder(mod, root: root)
            for file in ModLibrary.currentFiles(mod, root: root) {
                let destination = game.appending(path: file)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                // A compiled file of the game's own beside a mod's source would shadow it.
                for variant in compiledVariants(file) { try? fm.removeItem(at: game.appending(path: variant)) }
                try fm.copyItem(at: folder.appending(path: file), to: destination)
                if !placed.contains(file) { placed.append(file) }
            }
        }
        try JSONEncoder().encode(placed).write(to: manifest(copy), options: .atomic)
        return placed
    }

    /// A .rpy and the .rpyc Ren'Py compiles beside it.
    static func compiledVariants(_ path: String) -> [String] {
        switch (path as NSString).pathExtension.lowercased() {
        case "rpy": [path, path + "c"]
        case "rpym": [path, path + "c"]
        default: [path]
        }
    }

    /// S-020: modded play keeps its saves apart from the game's.
    public static func environment(modded: Bool, saves: URL) -> [String: String] {
        modded ? ["RENPY_PATH_TO_SAVES": saves.path] : [:]
    }
}

/// Two enabled mods that touch the same thing (S-019).
public struct ModConflict: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// The same file under game/: the later mod in the list wins.
        case file(String)
        /// The same screen name: Ren'Py keeps the one it loads last.
        case screen(String)
    }
    public var kind: Kind
    /// Mod names, in load order.
    public var mods: [String]
    /// The mod whose file is used, for file conflicts.
    public var winner: String? { if case .file = kind { mods.last } else { nil } }
}

public enum ModConflicts {
    /// Conflicts between the enabled mods, in load order.
    public static func find(_ mods: [Mod], root: URL) -> [ModConflict] {
        var byFile: [String: [String]] = [:]
        var fileOrder: [String] = []
        var byScreen: [String: [String]] = [:]
        var screenOrder: [String] = []
        for mod in mods {
            for file in ModLibrary.currentFiles(mod, root: root) {
                let key = file.lowercased()
                if byFile[key] == nil { fileOrder.append(key) }
                byFile[key, default: []].append(mod.name)
                guard (file as NSString).pathExtension.lowercased() == "rpy",
                      let text = try? String(contentsOf: ModLibrary.folder(mod, root: root).appending(path: file), encoding: .utf8) else { continue }
                for name in screens(in: text) where !(byScreen[name]?.contains(mod.name) ?? false) {
                    if byScreen[name] == nil { screenOrder.append(name) }
                    byScreen[name, default: []].append(mod.name)
                }
            }
        }
        let files = fileOrder.compactMap { key in byFile[key].flatMap { $0.count > 1 ? ModConflict(kind: .file(key), mods: $0) : nil } }
        let screens = screenOrder.compactMap { name in byScreen[name].flatMap { $0.count > 1 ? ModConflict(kind: .screen(name), mods: $0) : nil } }
        return files + screens
    }

    /// Names after `screen` at the start of a line.
    static func screens(in text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let words = line.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == " " || $0 == "(" || $0 == ":" })
            guard words.count > 1, words[0] == "screen" else { return nil }
            return String(words[1])
        }
    }
}
