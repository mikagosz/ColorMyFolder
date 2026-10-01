import AppKit
import os

let log = Logger(subsystem: "com.mikagosz.ColorMyFolder", category: "app")

/// Any JSON value — keeps fields this version does not know, so an older copy of the app on
/// another Mac never strips what a newer one wrote.
enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private extension Decoder {
    /// Every field of this object except `known`.
    func unknownFields(except known: Set<String>) throws -> [String: JSONValue] {
        let c = try container(keyedBy: AnyKey.self)
        var extra: [String: JSONValue] = [:]
        for key in c.allKeys where !known.contains(key.stringValue) {
            extra[key.stringValue] = try c.decode(JSONValue.self, forKey: key)
        }
        return extra
    }
}

private extension Encoder {
    func encodeUnknown(_ extra: [String: JSONValue]) throws {
        var c = container(keyedBy: AnyKey.self)
        for (key, value) in extra { try c.encode(value, forKey: AnyKey(key)) }
    }
}

struct RGB: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    /// `Logic.chrome` for the metallic finish; nil for a plain color.
    var finish: String?
    /// Fields written by a newer version, kept as they are.
    var extra: [String: JSONValue] = [:]

    init(r: Double, g: Double, b: Double, finish: String? = nil) { self.r = r; self.g = g; self.b = b; self.finish = finish }

    init?(_ color: NSColor) {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        r = Double(c.redComponent); g = Double(c.greenComponent); b = Double(c.blueComponent)
    }

    var color: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    private enum Keys: String, CodingKey { case r, g, b, finish }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        r = try c.decode(Double.self, forKey: .r)
        g = try c.decode(Double.self, forKey: .g)
        b = try c.decode(Double.self, forKey: .b)
        finish = try c.decodeIfPresent(String.self, forKey: .finish)
        extra = try decoder.unknownFields(except: ["r", "g", "b", "finish"])
    }

    func encode(to encoder: Encoder) throws {
        try encoder.encodeUnknown(extra)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(r, forKey: .r); try c.encode(g, forKey: .g); try c.encode(b, forKey: .b)
        try c.encodeIfPresent(finish, forKey: .finish)
    }

    /// The same color is the same color, whatever else a newer version stored with it.
    static func == (lhs: RGB, rhs: RGB) -> Bool {
        lhs.r == rhs.r && lhs.g == rhs.g && lhs.b == rhs.b && lhs.finish == rhs.finish
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(r); hasher.combine(g); hasher.combine(b); hasher.combine(finish)
    }
}

struct ColoredFolder: Codable, Hashable {
    /// Relative to the home folder (`~/…`), see `Logic.storedPath`.
    var path: String
    var color: RGB
    var extra: [String: JSONValue] = [:]

    init(path: String, color: RGB) { self.path = path; self.color = color }

    private enum Keys: String, CodingKey { case path, color }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        path = try c.decode(String.self, forKey: .path)
        color = try c.decode(RGB.self, forKey: .color)
        extra = try decoder.unknownFields(except: ["path", "color"])
    }

    func encode(to encoder: Encoder) throws {
        try encoder.encodeUnknown(extra)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(path, forKey: .path); try c.encode(color, forKey: .color)
    }
}

struct StoreData: Codable {
    var palette: [RGB] = []
    var folders: [ColoredFolder] = []
    var extra: [String: JSONValue] = [:]

    init() {}

    private enum Keys: String, CodingKey { case palette, folders }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        palette = try c.decodeIfPresent([RGB].self, forKey: .palette) ?? []
        folders = try c.decodeIfPresent([ColoredFolder].self, forKey: .folders) ?? []
        extra = try decoder.unknownFields(except: ["palette", "folders"])
    }

    func encode(to encoder: Encoder) throws {
        try encoder.encodeUnknown(extra)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(palette, forKey: .palette); try c.encode(folders, forKey: .folders)
    }
}

/// The list of saved colours and coloured folders. Lives in one JSON file in a folder the
/// user picks on first launch, so a synced folder shares it between Macs.
final class Store {
    static let fileName = Logic.storeFileName
    private static let directoryKey = "storeDirectory"

    private(set) var data = StoreData()
    /// False while the list file exists but cannot be read (iCloud has not downloaded it, the disk
    /// is not mounted, no permission). Nothing is written then — a save would replace the real
    /// list with whatever happens to be in memory.
    private(set) var readable = true
    let home: String
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, home: String = NSHomeDirectory()) {
        self.defaults = defaults
        self.home = home
    }

    var directory: URL? {
        get { defaults.string(forKey: Self.directoryKey).map { URL(fileURLWithPath: $0) } }
        set { defaults.set(newValue?.path, forKey: Self.directoryKey) }
    }

    var fileURL: URL? { directory?.appendingPathComponent(Self.fileName) }

    func reload() {
        // No place chosen yet: nothing to read, and what is in memory is all there is.
        guard let directory, let url = fileURL else { return }
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            // The list's folder is gone for now (a disk that is not mounted) — not an empty list.
            unreadable("List folder missing: \(directory.path)")
            return
        }
        guard fm.fileExists(atPath: url.path) else {
            let placeholder = directory.appendingPathComponent(".\(Self.fileName).icloud")
            if fm.fileExists(atPath: placeholder.path) {
                // iCloud keeps only a stub on this Mac; ask for the file and wait for it.
                try? fm.startDownloadingUbiquitousItem(at: url)
                unreadable("List is still in iCloud: \(url.path)")
                return
            }
            // No list yet (new place, or "Start a New List" on another Mac).
            readable = true
            data = StoreData()
            return
        }
        do {
            data = try JSONDecoder().decode(StoreData.self, from: Data(contentsOf: url))
            readable = true
        } catch {
            // Keep what is in memory rather than wiping the list over one bad read.
            unreadable("Cannot read \(url.path): \(error.localizedDescription)")
        }
    }

    private func unreadable(_ why: String) {
        readable = false
        log.error("\(why, privacy: .public)")
    }

    /// "N colors, M folders" for the list in `directory`, nil when it cannot be read.
    static func summary(of directory: URL) -> String? {
        guard let raw = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let data = try? JSONDecoder().decode(StoreData.self, from: raw) else { return nil }
        return String(localized: "\(data.palette.count) colors, \(data.folders.count) colored folders")
    }

    /// Every change reads the file first and applies itself to what is there, so a change made on
    /// the other Mac a moment ago is not overwritten with an older copy from memory.
    @discardableResult
    private func change(_ edit: (inout StoreData) -> Void) -> Bool {
        reload()
        edit(&data)
        guard readable, let url = fileURL else {
            log.error("List not saved: its place is not set or the list cannot be read")
            return false
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(data).write(to: url, options: .atomic)
            return true
        } catch {
            log.error("Cannot write \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func absoluteURL(_ folder: ColoredFolder) -> URL {
        URL(fileURLWithPath: Logic.absolutePath(folder.path, home: home))
    }

    func color(of url: URL) -> RGB? {
        let key = Logic.storedPath(url.path, home: home)
        return data.folders.first { $0.path == key }?.color
    }

    /// Many folders at once are one read and one write of the list, not one per folder.
    func setColor(_ color: RGB, for urls: [URL]) {
        var keys: [String] = []
        for url in urls {
            let key = Logic.storedPath(url.path, home: home)
            if !keys.contains(key) { keys.append(key) }
        }
        change { data in
            data.folders.removeAll { keys.contains($0.path) }
            data.folders += keys.map { ColoredFolder(path: $0, color: color) }
        }
    }

    func setColor(_ color: RGB, for url: URL) { setColor(color, for: [url]) }

    func removeColor(for urls: [URL]) {
        let keys = Set(urls.map { Logic.storedPath($0.path, home: home) })
        change { data in data.folders.removeAll { keys.contains($0.path) } }
    }

    func removeColor(for url: URL) { removeColor(for: [url]) }

    func addToPalette(_ color: RGB) {
        change { data in if !data.palette.contains(color) { data.palette.append(color) } }
    }

    func removeFromPalette(_ color: RGB) {
        change { data in data.palette.removeAll { $0 == color } }
    }
}
