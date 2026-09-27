import AppKit

/// Puts the right icon on every coloured folder and keeps it right as folders fill up and empty.
final class Colorizer {
    private let store: Store
    /// Last empty/full state we drew, per absolute path.
    private var drawnFull: [String: Bool] = [:]

    init(store: Store) { self.store = store }

    func apply(_ color: RGB, to url: URL) {
        store.setColor(color, for: url)
        draw(url, color: color, forced: true)
    }

    func clear(_ url: URL) {
        store.removeColor(for: url)
        drawnFull[url.path] = nil
        if !NSWorkspace.shared.setIcon(nil, forFile: url.path, options: []) {
            log.error("Cannot remove icon from \(url.path, privacy: .public)")
        }
    }

    /// Checks every folder on the list and redraws only those that need it.
    func refreshAll() {
        for folder in store.data.folders {
            draw(store.absoluteURL(folder), color: folder.color, forced: false)
        }
    }

    private func draw(_ url: URL, color: RGB, forced: Bool) {
        var isDirectory: ObjCBool = false
        // A folder from the other Mac may not exist here — keep it on the list, skip it.
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        let full = Logic.hasVisibleContent(names)
        guard Logic.needsApply(forced: forced, lastFull: drawnFull[url.path], full: full,
                               hasCustomIcon: Self.hasCustomIcon(url)) else { return }
        guard let icon = FolderRenderer.icon(for: color, full: full) else {
            log.error("Cannot render icon for \(url.path, privacy: .public)")
            return
        }
        if NSWorkspace.shared.setIcon(icon, forFile: url.path, options: []) {
            drawnFull[url.path] = full
        } else {
            log.error("Cannot set icon on \(url.path, privacy: .public)")
        }
    }

    /// Finder's kHasCustomIcon flag (0x0400 in the big-endian finderFlags at offset 8 of FinderInfo).
    private static func hasCustomIcon(_ url: URL) -> Bool {
        var info = [UInt8](repeating: 0, count: 32)
        let read = getxattr(url.path, "com.apple.FinderInfo", &info, info.count, 0, 0)
        return read >= 10 && info[8] & 0x04 != 0
    }
}
