import Foundation

/// Which Python a Ren'Py version runs game code with. A game's Python line
/// decides which runtimes can play it: 8.x can't run 7.x code, and back.
public enum PythonLine: String, Codable, Sendable {
    case python2, python3
}

/// A Ren'Py version such as 8.6.1, or 7.4.11.2266 with its build number.
public struct RenPyVersion: Comparable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    /// Reads "8.6.1", "Ren'Py 8.6.1.26111705" or "7.4.11.2266"; nil when it isn't a version.
    public init?(_ text: some StringProtocol) {
        let digits = text.drop { !$0.isNumber }.prefix { $0.isNumber || $0 == "." }
        let parts = digits.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        self.parts = parts
    }

    public var major: Int { parts[0] }
    public var minor: Int { parts[1] }
    public var patch: Int { parts.count > 2 ? parts[2] : 0 }

    /// Ren'Py 8 moved to Python 3; everything before runs Python 2.
    public var pythonLine: PythonLine { major >= 8 ? .python3 : .python2 }

    /// "8.6.1", without the build number.
    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: RenPyVersion, rhs: RenPyVersion) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}
