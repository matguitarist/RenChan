import Foundation

/// A variable in a save, as RenChan's save tool reports it (S-036).
public struct SaveVariable: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case bool, int, float, string, none, other }
    public var id: String { name }
    public var name: String
    public var kind: Kind
    /// The value: true/false, a number, the text, or a short description for other kinds.
    public var value: String

    public init(name: String, kind: Kind, value: String) {
        self.name = name
        self.kind = kind
        self.value = value
    }

    public var editable: Bool { [.bool, .int, .float, .string].contains(kind) }

    /// The JSON value to send back for the text typed, or nil when it doesn't fit the kind.
    public func encode(_ text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .bool: return ["true": true, "false": false][trimmed.lowercased()]
        case .int: return Int(trimmed)
        case .float: return Double(trimmed.replacingOccurrences(of: ",", with: "."))
        case .string: return text
        case .none, .other: return nil
        }
    }
}

/// RenChan's save tool: a Ren'Py command, renchan_saves, in RenChan's copy of the game (S-036).
/// It runs the game's own Ren'Py without a window, so the save is read with the game's real classes and
/// written back signed with this Mac's keys, like Ren'Py's own saves. Only plain values change.
public enum SaveTool {
    public static let fileName = "zz_renchan_saves.rpy"

    public static func install(copy: URL) throws {
        let file = copy.appending(path: "game/\(fileName)")
        if (try? String(contentsOf: file, encoding: .utf8)) != source { try source.write(to: file, atomically: true, encoding: .utf8) }
    }

    /// renchan_saves dump SLOT OUT.json, or renchan_saves set SLOT CHANGES.json OUT.json
    public static func dumpArguments(slot: String, output: URL) -> [String] { ["renchan_saves", "dump", slot, output.path] }
    public static func setArguments(slot: String, changes: URL, output: URL) -> [String] { ["renchan_saves", "set", slot, changes.path, output.path] }

    public struct Report: Decodable, Sendable {
        public var variables: [SaveVariable]?
        public var changed: [String]?
        public var refused: [String]?
        public var error: String?
    }

    public static func readReport(_ url: URL) throws -> Report {
        try JSONDecoder().decode(Report.self, from: Data(contentsOf: url))
    }

    public static func writeChanges(_ changes: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: changes, options: [.sortedKeys]).write(to: url)
    }

    public static let source = #"""
    # RenChan's save tool. It only runs when RenChan starts Ren'Py with the renchan_saves command; play never uses it.
    init -1500 python:
        def _renchan_saves():
            import io, json, os, sys, zipfile
            import renpy.compat.pickle as _pickle

            ap = renpy.arguments.ArgumentParser(description="RenChan save tool")
            ap.add_argument("action")
            ap.add_argument("slot")
            ap.add_argument("files", nargs="+")
            args = ap.parse_args()
            out = args.files[-1]
            report = {}
            PY2 = sys.version_info[0] == 2
            text_types = (str, unicode) if PY2 else (str,)
            int_types = (int, long) if PY2 else (int,)

            def kind(v):
                if v is None:
                    return "none"
                if isinstance(v, bool):
                    return "bool"
                if isinstance(v, int_types):
                    return "int"
                if isinstance(v, float):
                    return "float"
                if isinstance(v, text_types):
                    return "string"
                return "other"

            def describe(v):
                k = kind(v)
                if k == "bool":
                    return "true" if v else "false"
                if k == "string":
                    return v.decode("utf-8", "replace") if PY2 and isinstance(v, str) else v
                if k in ("int", "float", "none"):
                    return repr(v)
                try:
                    return "%s (%d)" % (type(v).__name__, len(v))
                except Exception:
                    return type(v).__name__

            try:
                location = renpy.loadsave.location.newest(args.slot)
                if location is None:
                    raise Exception("No save in slot %s" % args.slot)
                path = location.filename(args.slot)
                zf = zipfile.ZipFile(path, "r")
                entries = [(info, zf.read(info.filename)) for info in zf.infolist()]
                zf.close()
                log_data = dict((i.filename, d) for i, d in entries)["log"]
                roots, log = _pickle.loads(log_data)
                deleted = getattr(renpy.rollback, "deleted", object())
                # Loading rolls back to the start of the statement the save was made in, from these records.
                records = [(getattr(rb, "stores", None) or {}).get("store") for rb in list(getattr(log, "log", [])) + [getattr(log, "current", None)] if rb is not None]
                # In the store, dict means Ren'Py's RevertableDict, so check for a mapping by its methods.
                records = [r for r in records if hasattr(r, "keys") and hasattr(r, "__setitem__")]

                def effective(name, value):
                    for r in reversed(records):
                        if name in r and r[name] is not deleted:
                            return r[name]
                    return value

                if args.action == "dump":
                    found = []
                    for key in sorted(roots):
                        if not key.startswith("store.") or key.startswith("store._") or "." in key[6:]:
                            continue
                        v = effective(key[6:], roots[key])
                        if callable(v) or isinstance(v, type(os)):
                            continue
                        found.append({"name": key[6:], "kind": kind(v), "value": describe(v)})
                    report["variables"] = found

                elif args.action == "set":
                    with io.open(args.files[0], "r", encoding="utf-8") as f:
                        changes = json.load(f)
                    changed, refused = [], []
                    for name, value in changes.items():
                        key = "store." + name
                        if key not in roots:
                            refused.append(name)
                            continue
                        old = effective(name, roots[key])
                        k = kind(old)
                        if k == "bool" and isinstance(value, bool):
                            new = value
                        elif k == "int" and isinstance(value, int_types) and not isinstance(value, bool):
                            new = int(value)
                        elif k == "float" and isinstance(value, (float,) + int_types) and not isinstance(value, bool):
                            new = float(value)
                        elif k == "string" and isinstance(value, text_types):
                            new = value.encode("utf-8") if PY2 and isinstance(old, str) else value
                        else:
                            refused.append(name)
                            continue
                        roots[key] = new
                        for r in records:
                            if name in r and r[name] is not deleted:
                                r[name] = new
                        changed.append(name)
                    if changed:
                        new_log = _pickle.dumps((roots, log))
                        signatures = renpy.savetoken.sign_data(new_log)
                        tmp = path + ".renchan"
                        zout = zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED)
                        for info, data in entries:
                            if info.filename == "log":
                                data = new_log
                            elif info.filename == "signatures":
                                continue
                            zout.writestr(info, data)
                        if signatures:
                            zout.writestr("signatures", signatures)
                        zout.close()
                        os.rename(tmp, path)
                    report["changed"] = sorted(changed)
                    report["refused"] = sorted(refused)
                else:
                    raise Exception("Unknown action %s" % args.action)
            except Exception as e:
                report["error"] = "%s: %s" % (type(e).__name__, e)

            data = json.dumps(report, ensure_ascii=True)
            with open(out, "wb") as f:
                f.write(data.encode("ascii"))
            return False

        renpy.arguments.register_command("renchan_saves", _renchan_saves)

    """#
}
