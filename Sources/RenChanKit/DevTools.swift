import Foundation

/// Ren'Py's own developer tools, per game (S-022): the console (Shift+O) and fast skipping (>).
public struct DevTools: Codable, Hashable, Sendable {
    public var console = false
    public var fastSkip = false
    public var isOn: Bool { console || fastSkip }

    public init(console: Bool = false, fastSkip: Bool = false) {
        self.console = console
        self.fastSkip = fastSkip
    }
}

/// Writes RenChan's developer-tools file into the copy before a launch, or takes it out.
public enum DevToolsLoader {
    public static let fileName = "zz_renchan_devtools.rpy"

    public static func install(_ tools: DevTools, copy: URL) throws {
        guard tools.isOn else { return CopyScript.remove(named: fileName, from: copy) }
        try CopyScript.place(source(tools), named: fileName, in: copy)
    }

    /// Python 2 and 3. Runs after the game's own init, so the game can't turn them back off.
    public static func source(_ tools: DevTools) -> String {
        var lines = ["# Written by RenChan before each launch, in RenChan's copy of the game only.", "init 999 python:"]
        if tools.console { lines.append("    config.console = True") }
        if tools.fastSkip { lines.append("    config.fast_skipping = True") }
        return lines.joined(separator: "\n") + "\n"
    }
}
