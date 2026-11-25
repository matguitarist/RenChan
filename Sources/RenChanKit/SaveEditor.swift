import Foundation

/// A variable in a save, as RenChan's save tool reports it (S-036).
public struct SaveVariable: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case bool, int, float, string, none, other }
    public var id: String { name }
    public var name: String
    public var kind: Kind
    /// The value: true/false, a number, the text, or a short description for other kinds.
    public var value: String
    /// For a value inside a list or dictionary, the name of the item it belongs to, such as "Hawaiian Dream".
    public var note: String?

    public init(name: String, kind: Kind, value: String, note: String? = nil) {
        self.name = name
        self.kind = kind
        self.value = value
        self.note = note
    }

    public var editable: Bool { [.bool, .int, .float, .string].contains(kind) }

    /// Words in the names of values games use to remember what the player unlocked, saw or finished.
    public static let unlockWords = ["unlock", "gallery", "seen", "ending", "achiev", "replay", "complete", "cleared"]

    /// On/off values a game keeps for its own gallery or unlocks, such as "lucy_img_main8_201_unlocked" or
    /// "gallery_lucy1": games with their own gallery check these, not Ren'Py's list of seen images (S-040).
    public var isUnlockFlag: Bool {
        guard kind == .bool else { return false }
        let name = name.lowercased()
        return Self.unlockWords.contains { name.contains($0) }
    }

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
        try CopyScript.place(source, named: fileName, in: copy)
    }

    /// renchan_saves dump SLOT OUT.json, or renchan_saves set SLOT CHANGES.json OUT.json
    public static func dumpArguments(slot: String, output: URL) -> [String] { ["renchan_saves", "dump", slot, output.path] }
    public static func setArguments(slot: String, changes: URL, output: URL) -> [String] { ["renchan_saves", "set", slot, changes.path, output.path] }
    /// The same changes in several saves at once, such as every save of the game.
    public static func setArguments(slots: [String], changes: URL, output: URL) -> [String] { setArguments(slot: slots.joined(separator: ","), changes: changes, output: output) }
    /// Persistent data, shared by every save (S-040): its fields, changes to them, and every image marked as seen.
    public static func persistentDumpArguments(output: URL) -> [String] { ["renchan_saves", "pdump", "-", output.path] }
    public static func persistentSetArguments(changes: URL, output: URL) -> [String] { ["renchan_saves", "pset", "-", changes.path, output.path] }
    public static func unlockImagesArguments(output: URL) -> [String] { ["renchan_saves", "unlock", "-", output.path] }
    /// Lists every picture of the game and where its bytes are, for RenChan's gallery (S-042).
    public static func picturesArguments(output: URL) -> [String] { ["renchan_saves", "pictures", "-", output.path] }
    /// Marks every label of the game as seen, which unlocks Ren'Py replays (S-040).
    public static func unlockReplaysArguments(output: URL) -> [String] { ["renchan_saves", "replays", "-", output.path] }

    public struct Report: Decodable, Sendable {
        public var variables: [SaveVariable]?
        public var changed: [String]?
        public var refused: [String]?
        /// How many saves a change was written into.
        public var saves: Int?
        /// Images newly marked as seen by unlock.
        public var unlocked: Int?
        /// Images the game defines, for unlock.
        public var images: Int?
        /// The game's own labels (scenes), and how many were played, for replays.
        public var labels: Int?
        public var seenLabels: Int?
        /// Every picture of the game, for pictures.
        public var pictures: [GamePicture]?
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
        class _RenChanDone(Exception):
            pass

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

            def convert(old, value):
                # The new value when it fits the old one's kind, else None.
                k = kind(old)
                if k == "bool" and isinstance(value, bool):
                    return (value,)
                if k == "int" and isinstance(value, int_types) and not isinstance(value, bool):
                    return (int(value),)
                if k == "float" and isinstance(value, (float,) + int_types) and not isinstance(value, bool):
                    return (float(value),)
                if k == "string" and isinstance(value, text_types):
                    return (value.encode("utf-8") if PY2 and isinstance(old, str) else value,)
                return None

            import re
            ident = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
            budget = [5000]

            def label(item):
                # A list item's own name, such as a gallery entry's, to show beside its values.
                try:
                    if hasattr(item, "keys"):
                        for key in ("name", "title", "label", "id"):
                            if key in item and isinstance(item[key], text_types):
                                return describe(item[key])
                except Exception:
                    pass
                return None

            def walk(path, v, depth, out, note):
                # Lists and dictionaries of plain values are opened, so each value inside can change:
                # renders[3].unlocked. Tuples, sets and objects stay whole and read-only.
                is_list = isinstance(v, list)
                is_dict = hasattr(v, "keys") and hasattr(v, "__setitem__") and not isinstance(v, type)
                if depth < 3 and budget[0] > 0 and (is_list or is_dict) and len(v) > 0:
                    if is_list:
                        for i, item in enumerate(v):
                            walk("%s[%d]" % (path, i), item, depth + 1, out, label(item) or note)
                        return
                    keys = list(v.keys())
                    if all(isinstance(k, text_types) for k in keys):
                        for k in sorted(keys):
                            step = ("." + k) if ident.match(k) else "[%s]" % json.dumps(k)
                            walk(path + step, v[k], depth + 1, out, label(v) or note)
                        return
                budget[0] -= 1
                row = {"name": path, "kind": kind(v), "value": describe(v)}
                if note:
                    row["note"] = note
                out.append(row)

            step_re = re.compile(r'\[(\d+)\]|\.([A-Za-z_][A-Za-z0-9_]*)|\[("(?:[^"\\]|\\.)*")\]')

            def split_path(path):
                # "renders[3].unlocked" -> ("renders", [3, "unlocked"])
                head = re.match(r"^[A-Za-z_][A-Za-z0-9_]*", path)
                if head is None:
                    raise KeyError(path)
                steps, at = [], head.end()
                while at < len(path):
                    m = step_re.match(path, at)
                    if m is None:
                        raise KeyError(path)
                    if m.group(1) is not None:
                        steps.append(int(m.group(1)))
                    elif m.group(2) is not None:
                        steps.append(m.group(2))
                    else:
                        steps.append(json.loads(m.group(3)))
                    at = m.end()
                return head.group(0), steps

            def read_changes():
                with io.open(args.files[0], "r", encoding="utf-8") as f:
                    return json.load(f)

            try:
                def story_labels():
                    # The game's labels; Ren'Py's own start with _.
                    return [l for l in renpy.get_all_labels() if isinstance(l, text_types) and not l.startswith("_")]

                if args.action == "pictures":
                    # Every picture of the game for RenChan's gallery: loose files by path (Ren'Py prefers them),
                    # then archived ones by where their bytes sit, so RenChan reads them without Ren'Py.
                    import base64
                    exts = (".png", ".jpg", ".jpeg", ".webp", ".avif", ".bmp", ".gif")

                    def b64(data):
                        return base64.b64encode(data).decode("ascii")

                    pictures, seen = [], set()
                    archived = set()
                    for _afn, index in renpy.loader.archives:
                        archived.update(index.keys())
                    for name in renpy.list_files():
                        if name in seen or not name.lower().endswith(exts):
                            continue
                        try:
                            fn = renpy.loader.transfn(name)
                        except Exception:
                            continue
                        if fn and os.path.isfile(fn):
                            seen.add(name)
                            pictures.append({"path": name, "file": fn})
                    for afn, index in renpy.loader.archives:
                        try:
                            path = afn if os.path.isabs(afn) else renpy.loader.transfn(afn)
                        except Exception:
                            continue
                        for name, entries in index.items():
                            if name in seen or not name.lower().endswith(exts):
                                continue
                            parts = []
                            for t in entries:
                                if len(t) == 1:
                                    parts.append({"bytes": b64(t[0])})
                                    continue
                                # 7.x keeps a few leading bytes beside the offset (RPA-3.0 "start").
                                if len(t) == 3 and t[2]:
                                    parts.append({"bytes": b64(t[2])})
                                parts.append({"offset": int(t[0]), "length": int(t[1])})
                            seen.add(name)
                            pictures.append({"path": name, "archive": path, "parts": parts})
                    report["pictures"] = sorted(pictures, key=lambda p: p["path"])
                    raise _RenChanDone()

                elif args.action in ("pdump", "pset", "unlock", "replays"):
                    # Persistent data: Ren'Py loaded it before running this command, and saving it the
                    # usual way signs it with this Mac's key, so the game reads it without asking.
                    p = renpy.game.persistent
                    fields = p.__dict__
                    if args.action == "pdump":
                        found = []
                        for name in sorted(fields):
                            v = fields[name]
                            if name.startswith("_") or callable(v) or isinstance(v, type(os)):
                                continue
                            walk(name, v, 0, found, None)
                        report["variables"] = found
                        report["images"] = len(renpy.list_images())
                        labels = story_labels()
                        report["labels"] = len(labels)
                        report["seenLabels"] = len([l for l in labels if renpy.seen_label(l)])
                    elif args.action == "pset":
                        changed, refused = [], []
                        for name, value in read_changes().items():
                            try:
                                root, steps = split_path(name)
                                if root.startswith("_") or root not in fields:
                                    raise KeyError(name)
                                if not steps:
                                    new = convert(fields[root], value)
                                    if new is None:
                                        raise TypeError(name)
                                    setattr(p, root, new[0])
                                else:
                                    target = fields[root]
                                    for step in steps[:-1]:
                                        target = target[step]
                                    new = convert(target[steps[-1]], value)
                                    if new is None or isinstance(target, tuple):
                                        raise TypeError(name)
                                    target[steps[-1]] = new[0]
                                changed.append(name)
                            except Exception:
                                refused.append(name)
                        if changed:
                            renpy.save_persistent()
                        report["changed"] = sorted(changed)
                        report["refused"] = sorted(refused)
                    elif args.action == "replays":
                        # Seen labels are kept apart from seen lines of dialogue, so Skip still stops at unread text.
                        mark = getattr(renpy, "mark_label_seen", None)
                        count = 0
                        labels = story_labels()
                        for l in labels:
                            if renpy.seen_label(l):
                                continue
                            if mark is not None:
                                mark(l)
                            else:
                                p._seen_ever[l] = True
                            count += 1
                        if count:
                            renpy.save_persistent()
                        report["unlocked"] = count
                        report["labels"] = len(labels)
                    else:
                        seen = getattr(p, "_seen_images", None)
                        if seen is None:
                            seen = p._seen_images = {}
                        count = 0
                        for image in renpy.list_images():
                            key = tuple(str(i) for i in image.split())
                            if key not in seen:
                                seen[key] = True
                                count += 1
                        if count:
                            renpy.save_persistent()
                        report["unlocked"] = count
                        report["images"] = len(renpy.list_images())
                    raise _RenChanDone()

                def one(slot):
                    location = renpy.loadsave.location.newest(slot)
                    if location is None:
                        raise Exception("No save in slot %s" % slot)
                    path = location.filename(slot)
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
                        return found

                    elif args.action == "set":
                        changed, refused = [], []
                        for name, value in read_changes().items():
                            key = "store." + name
                            new = convert(effective(name, roots[key]), value) if key in roots else None
                            if new is None:
                                refused.append(name)
                                continue
                            new = new[0]
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
                        return changed, refused

                slots = [s for s in args.slot.split(",") if s]
                if args.action == "dump":
                    report["variables"] = one(slots[0])
                elif args.action == "set":
                    # One or several saves, such as every save of the game; each keeps its own values otherwise.
                    changed, refused, written = set(), set(), 0
                    for slot in slots:
                        c, r = one(slot)
                        changed.update(c)
                        refused.update(r)
                        written += 1 if c else 0
                    report["changed"] = sorted(changed)
                    report["refused"] = sorted(refused - changed)
                    report["saves"] = written
                else:
                    raise Exception("Unknown action %s" % args.action)
            except _RenChanDone:
                pass
            except Exception as e:
                report["error"] = "%s: %s" % (type(e).__name__, e)

            data = json.dumps(report, ensure_ascii=True)
            with open(out, "wb") as f:
                f.write(data.encode("ascii"))
            return False

        renpy.arguments.register_command("renchan_saves", _renchan_saves)

    """#
}
