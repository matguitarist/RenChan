import Foundation

/// The translations a game ships in game/tl/<language>/, on disk or inside its .rpa archives (S-039).
public enum GameLanguages {
    /// Language folder names such as "french", sorted; Ren'Py's "None" (the original language) left out.
    /// `extraPaths` are paths under game/ from mods, such as "tl/german/script.rpy".
    public static func find(base: URL, extraPaths: [String] = []) -> [String] {
        let game = base.appending(path: "game", directoryHint: .isDirectory)
        var found = Set<String>()
        let tl = game.appending(path: "tl", directoryHint: .isDirectory)
        for folder in (try? FileManager.default.contentsOfDirectory(at: tl, includingPropertiesForKeys: nil)) ?? [] where GameLocator.isDirectory(folder) {
            found.insert(folder.lastPathComponent)
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: game, includingPropertiesForKeys: nil)) ?? []
        for archive in files where archive.pathExtension.lowercased() == "rpa" {
            found.formUnion(names(in: archivePaths(archive).compactMap(translationPath)))
        }
        found.formUnion(names(in: extraPaths))
        return found.filter { $0 != "None" && !$0.hasPrefix(".") && !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// "tl/french/script.rpy" or "game/tl/french/…" gives "french".
    public static func names(in paths: [String]) -> Set<String> {
        var found = Set<String>()
        for path in paths {
            let parts = path.split(separator: "/").map(String.init)
            // tl/<language>/<file>, at the top of game/.
            guard let index = parts.firstIndex(of: "tl"), index + 2 < parts.count, index == 0 || (index == 1 && parts[0] == "game") else { continue }
            found.insert(parts[index + 1])
        }
        return found
    }

    /// The file names an RPA-2.0 or RPA-3.0 archive holds, read from its index (a zlib-compressed pickle).
    /// The pickle isn't decoded: the names are found as text in it, which is all a language list needs.
    public static func archivePaths(_ url: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 64),
              let line = String(data: head.prefix(while: { $0 != 0x0A }), encoding: .ascii) else { return [] }
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "RPA-3.0" || parts[0] == "RPA-2.0", let offset = UInt64(parts[1], radix: 16) else { return [] }
        guard (try? handle.seek(toOffset: offset)) != nil, let compressed = try? handle.read(upToCount: 64 << 20), compressed.count > 6 else { return [] }
        // zlib: a two-byte header, raw DEFLATE, and a four-byte checksum. Apple's .zlib reads the raw DEFLATE.
        let raw = Data(compressed.dropFirst(2).dropLast(4))
        guard let index = try? (raw as NSData).decompressed(using: .zlib) as Data else { return [] }
        let text = String(decoding: index.map { $0 < 0x20 || $0 > 0x7E ? 0x0A : $0 }, as: UTF8.self)
        return text.split(separator: "\n").map(String.init).filter { $0.contains("/") || $0.contains(".") }
    }

    /// A name read from an archive index, as "tl/…". A pickle may put its one-byte length just before
    /// a short name, so one stray character before "tl/" or "game/tl/" is allowed.
    static func translationPath(_ text: String) -> String? {
        guard let range = text.range(of: "tl/") else { return nil }
        var prefix = String(text[..<range.lowerBound])
        if prefix.hasSuffix("game/") { prefix.removeLast(5) }
        guard prefix.count <= 1 else { return nil }
        return String(text[range.lowerBound...])
    }

    /// "french" → "French", "schinese" → "Schinese", "pt_br" → "Pt br".
    public static func title(_ name: String, locale: Locale = .current) -> String {
        // Ren'Py's translation folders use English names ("french"); show them in the person's language when known.
        if let code = codes[name.lowercased()], let local = locale.localizedString(forLanguageCode: code) {
            return local.prefix(1).uppercased() + local.dropFirst()
        }
        let spaced = name.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    /// The usual English folder names of Ren'Py translations, with their language codes.
    static let codes: [String: String] = [
        "english": "en", "french": "fr", "francais": "fr", "spanish": "es", "espanol": "es", "german": "de", "deutsch": "de",
        "italian": "it", "portuguese": "pt", "brazilian": "pt-BR", "portuguese_br": "pt-BR", "russian": "ru", "ukrainian": "uk",
        "polish": "pl", "czech": "cs", "dutch": "nl", "swedish": "sv", "finnish": "fi", "danish": "da", "norwegian": "nb",
        "turkish": "tr", "greek": "el", "hungarian": "hu", "romanian": "ro", "japanese": "ja", "korean": "ko",
        "chinese": "zh", "schinese": "zh-Hans", "tchinese": "zh-Hant", "simplified_chinese": "zh-Hans", "traditional_chinese": "zh-Hant",
        "arabic": "ar", "hebrew": "he", "vietnamese": "vi", "thai": "th", "indonesian": "id", "piglatin": "",
    ].filter { !$0.value.isEmpty }
}

/// Writes RenChan's language file into the copy before a launch, or takes it out (S-039).
/// Ren'Py starts in config.language when it is set (00start.rpy, 6.99 to 8.x).
public enum LanguageLoader {
    public static let fileName = "zz_renchan_language.rpy"

    /// The language Ren'Py calls None: the one the game was written in.
    public static let original = "None"

    public static func install(_ language: String?, copy: URL) throws {
        let file = copy.appending(path: "game/\(fileName)")
        guard let language, !language.isEmpty else {
            for url in [file, file.deletingPathExtension().appendingPathExtension("rpyc")] { try? FileManager.default.removeItem(at: url) }
            return
        }
        let text = source(language)
        if (try? String(contentsOf: file, encoding: .utf8)) != text { try text.write(to: file, atomically: true, encoding: .utf8) }
    }

    /// Python 2 and 3. Runs after the game's own init, so it wins over a language the game sets.
    public static func source(_ language: String) -> String {
        if language == original {
            // The game's own language, even after a translation was used: Ren'Py remembers the last one in its preferences.
            return """
            # Written by RenChan before each launch, in RenChan's copy of the game only.
            init 999 python:
                config.language = None
                _preferences.language = None

            """
        }
        let escaped = language.unicodeScalars.map { $0.isASCII && $0 != "\"" && $0 != "\\" ? String($0) : String(format: "\\U%08x", $0.value) }.joined()
        return """
        # Written by RenChan before each launch, in RenChan's copy of the game only.
        init 999 python:
            config.language = u"\(escaped)"

        """
    }
}
