import Compression
import Foundation

/// Reads the files in a zip, such as a Ren'Py save. Stored and deflated entries only, which is what Ren'Py writes.
public struct ZipReader {
    public struct Entry: Sendable { public var name: String; var method: UInt16; var compressedSize: Int; var size: Int; var offset: Int }
    let data: Data
    public let entries: [Entry]

    public init(_ url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public init(data: Data) throws {
        self.data = data
        guard data.count >= 22 else { throw CocoaError(.fileReadCorruptFile) }
        // The end of central directory record is in the last 64 KB.
        var eocd = -1
        var i = data.count - 22
        let floor = max(0, data.count - 65_557)
        while i >= floor {
            if data.u32(i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw CocoaError(.fileReadCorruptFile) }
        let count = Int(data.u16(eocd + 10))
        var p = Int(data.u32(eocd + 16))
        var found: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= data.count, data.u32(p) == 0x0201_4b50 else { throw CocoaError(.fileReadCorruptFile) }
            let method = data.u16(p + 10)
            let compressed = Int(data.u32(p + 20)), size = Int(data.u32(p + 24))
            let nameLength = Int(data.u16(p + 28)), extra = Int(data.u16(p + 30)), comment = Int(data.u16(p + 32))
            let offset = Int(data.u32(p + 42))
            let name = String(decoding: data[data.startIndex + p + 46 ..< data.startIndex + p + 46 + nameLength], as: UTF8.self)
            found.append(Entry(name: name, method: method, compressedSize: compressed, size: size, offset: offset))
            p += 46 + nameLength + extra + comment
        }
        entries = found
    }

    public func read(_ name: String) -> Data? {
        guard let entry = entries.first(where: { $0.name == name }), entry.offset + 30 <= data.count,
              data.u32(entry.offset) == 0x0403_4b50 else { return nil }
        let start = entry.offset + 30 + Int(data.u16(entry.offset + 26)) + Int(data.u16(entry.offset + 28))
        guard start + entry.compressedSize <= data.count else { return nil }
        let raw = data[data.startIndex + start ..< data.startIndex + start + entry.compressedSize]
        switch entry.method {
        case 0: return Data(raw)
        case 8: return Self.inflate(Data(raw), size: entry.size)
        default: return nil
        }
    }

    static func inflate(_ input: Data, size: Int) -> Data? {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { inp in
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size,
                                          inp.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == size ? output : nil
    }
}

private extension Data {
    func u16(_ i: Int) -> UInt16 { UInt16(self[startIndex + i]) | UInt16(self[startIndex + i + 1]) << 8 }
    func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
}

/// One Ren'Py save file, such as 1-3.save (S-035).
public struct SaveFile: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public var url: URL
    /// "1-3", "auto-1", "quick-2": the name Ren'Py loads it by.
    public var slot: String
    public var date: Date
    /// The name the player typed, or Ren'Py's own text.
    public var name: String
    public var renpyVersion: String?
    /// Seconds played when it was saved, when the save says.
    public var playtime: TimeInterval?
    public var size: Int64

    /// "Page 1, slot 3", "Auto 1", "Quick 2".
    public var place: String {
        let parts = slot.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return slot }
        switch parts[0] {
        case "auto": return String(localized: "Auto \(parts[1])")
        case "quick": return String(localized: "Quick \(parts[1])")
        default: return Int(parts[0]) != nil ? String(localized: "Page \(parts[0]), slot \(parts[1])") : slot
        }
    }

    public func screenshot() -> Data? { (try? ZipReader(url))?.read("screenshot.png") }
}

public enum SaveList {
    /// Every .save in a folder, newest first. Unreadable files are left out.
    public static func list(in folder: URL) -> [SaveFile] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        return files.filter { $0.pathExtension == "save" }.compactMap(read).sorted { $0.date > $1.date }
    }

    public static func read(_ url: URL) -> SaveFile? {
        guard let zip = try? ZipReader(url), zip.entries.contains(where: { $0.name == "log" }) else { return nil }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let json = zip.read("json").flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let extra = zip.read("extra_info").map { String(decoding: $0, as: UTF8.self) } ?? ""
        let saveName = (json?["_save_name"] as? String) ?? extra
        var date = values?.contentModificationDate ?? .distantPast
        if let ctime = json?["_ctime"] as? Double { date = Date(timeIntervalSince1970: ctime) }
        let version = (json?["_renpy_version"] as? [Any])?.compactMap { ($0 as? NSNumber)?.stringValue }.joined(separator: ".")
            ?? zip.read("renpy_version").map { String(decoding: $0, as: UTF8.self) }
        // 1-1-LT1.save: Ren'Py adds -LT1 to the slot's name.
        let slot = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: #"-LT\d+$"#, with: "", options: .regularExpression)
        return SaveFile(url: url, slot: slot, date: date, name: saveName,
                        renpyVersion: version?.isEmpty == true ? nil : version,
                        playtime: json?["_game_runtime"] as? Double, size: Int64(values?.fileSize ?? 0))
    }
}
