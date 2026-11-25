import Foundation

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
