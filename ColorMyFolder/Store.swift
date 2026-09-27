import AppKit
import os

let log = Logger(subsystem: "com.mikagosz.ColorMyFolder", category: "app")

struct RGB: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    /// `Logic.chrome` for the metallic finish; nil for a plain color.
    var finish: String?

    init(r: Double, g: Double, b: Double, finish: String? = nil) { self.r = r; self.g = g; self.b = b; self.finish = finish }

    init?(_ color: NSColor) {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        r = Double(c.redComponent); g = Double(c.greenComponent); b = Double(c.blueComponent)
    }

    var color: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

struct ColoredFolder: Codable, Hashable {
    /// Relative to the home folder (`~/…`), see `Logic.storedPath`.
    var path: String
    var color: RGB
}

struct StoreData: Codable {
    var palette: [RGB] = []
    var folders: [ColoredFolder] = []
}

/// The list of saved colours and coloured folders. Lives in one JSON file in a folder the
/// user picks on first launch, so a synced folder shares it between Macs.
final class Store {
    static let fileName = Logic.storeFileName
    private static let directoryKey = "storeDirectory"

    private(set) var data = StoreData()
    let home = NSHomeDirectory()

    var directory: URL? {
        get { UserDefaults.standard.string(forKey: Self.directoryKey).map { URL(fileURLWithPath: $0) } }
        set { UserDefaults.standard.set(newValue?.path, forKey: Self.directoryKey) }
    }

    var fileURL: URL? { directory?.appendingPathComponent(Self.fileName) }

    func reload() {
        guard let url = fileURL else { return }
        guard let raw = try? Data(contentsOf: url) else { data = StoreData(); return }
        do {
            data = try JSONDecoder().decode(StoreData.self, from: raw)
        } catch {
            // Keep what is in memory rather than wiping the list over one bad read.
            log.error("Cannot read \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// "N colors, M folders" for the list in `directory`, nil when it cannot be read.
    static func summary(of directory: URL) -> String? {
        guard let raw = try? Data(contentsOf: directory.appendingPathComponent(fileName)),
              let data = try? JSONDecoder().decode(StoreData.self, from: raw) else { return nil }
        return String(localized: "\(data.palette.count) colors, \(data.folders.count) colored folders")
    }

    func save() {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(data).write(to: url, options: .atomic)
        } catch {
            log.error("Cannot write \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func absoluteURL(_ folder: ColoredFolder) -> URL {
        URL(fileURLWithPath: Logic.absolutePath(folder.path, home: home))
    }

    func color(of url: URL) -> RGB? {
        let key = Logic.storedPath(url.path, home: home)
        return data.folders.first { $0.path == key }?.color
    }

    func setColor(_ color: RGB, for url: URL) {
        let key = Logic.storedPath(url.path, home: home)
        data.folders.removeAll { $0.path == key }
        data.folders.append(ColoredFolder(path: key, color: color))
        save()
    }

    func removeColor(for url: URL) {
        let key = Logic.storedPath(url.path, home: home)
        data.folders.removeAll { $0.path == key }
        save()
    }

    func addToPalette(_ color: RGB) {
        guard !data.palette.contains(color) else { return }
        data.palette.append(color)
        save()
    }

    func removeFromPalette(_ color: RGB) {
        data.palette.removeAll { $0 == color }
        save()
    }
}
