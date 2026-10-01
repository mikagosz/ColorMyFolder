import AppKit

/// Puts the right icon on every coloured folder and keeps it right as folders fill up and empty.
///
/// One icon takes about 0.1 s and tens of megabytes to draw, so drawing runs on a queue of its own,
/// one folder at a time, each in its own autorelease pool. Measured on 300 folders before this:
/// 30 s with the app frozen and 14 GB of memory, because the whole loop ran on the main thread
/// and nothing was released until the last folder. Now the window and Finder's quick action
/// answer meanwhile, icons appear one by one, and memory goes back after every folder.
final class Colorizer {
    private let store: Store
    /// What we last drew, per absolute path — main thread only.
    private var drawn: [String: (full: Bool, color: RGB)] = [:]
    /// Jobs waiting or running on the queue, per path, and the color the newest one draws —
    /// main thread only.
    private var pending: [String: Int] = [:]
    private var queuedColor: [String: RGB] = [:]
    /// One folder at a time, in the order asked: a newer color always lands after an older one,
    /// and "Restore System Look" after any drawing queued before it.
    private let queue = DispatchQueue(label: "com.mikagosz.ColorMyFolder.drawing", qos: .utility)

    /// Icons still waiting to be drawn — an update would cut them off.
    var isWorking: Bool { !pending.isEmpty }

    init(store: Store) { self.store = store }

    func apply(_ color: RGB, to urls: [URL]) {
        store.setColor(color, for: urls)
        urls.forEach { draw($0, color: color, forced: true) }
    }

    func clear(_ urls: [URL]) {
        store.removeColor(for: urls)
        for url in urls { enqueue(url.path, color: nil) }
    }

    /// Checks every folder on the list and redraws only those that need it.
    func refreshAll() {
        for folder in store.data.folders {
            draw(store.absoluteURL(folder), color: folder.color, forced: false)
        }
    }

    private func draw(_ url: URL, color: RGB, forced: Bool) {
        // A folder from the other Mac may not exist here — keep it on the list, skip it. A package
        // (an .app) is skipped too: an icon written into it breaks its code signature.
        guard Logic.isPlainFolder(url) else { return }
        let path = url.path
        // Already waiting for this very color; the job reads empty/full when it runs.
        if !forced, queuedColor[path] == color { return }
        let full = Logic.hasVisibleContent((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
        let last = drawn[path]
        // The list changed on the other Mac: same folder, another color.
        let recolored = last.map { $0.color != color } ?? false
        guard Logic.needsApply(forced: forced || recolored, lastFull: last?.full, full: full,
                               hasCustomIcon: Self.hasCustomIcon(url)) else { return }
        enqueue(path, color: color)
    }

    /// `color` nil: take the custom icon off.
    private func enqueue(_ path: String, color: RGB?) {
        pending[path, default: 0] += 1
        queuedColor[path] = color
        queue.async { [weak self] in
            let (full, ok) = autoreleasepool { Self.paint(path, color: color) }
            DispatchQueue.main.async { self?.finished(path, color: color, full: full, ok: ok) }
        }
    }

    /// Runs on the drawing queue. Empty/full is read here, not when the job was queued, so a
    /// folder that filled up while it waited gets the right paper sheet.
    private static func paint(_ path: String, color: RGB?) -> (full: Bool, ok: Bool) {
        guard let color else {
            let ok = NSWorkspace.shared.setIcon(nil, forFile: path, options: [])
            if !ok { log.error("Cannot remove icon from \(path, privacy: .public)") }
            return (false, ok)
        }
        let full = Logic.hasVisibleContent((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
        guard let icon = FolderRenderer.icon(for: color, full: full) else {
            log.error("Cannot render icon for \(path, privacy: .public)")
            return (full, false)
        }
        let ok = NSWorkspace.shared.setIcon(icon, forFile: path, options: [])
        if !ok { log.error("Cannot set icon on \(path, privacy: .public)") }
        return (full, ok)
    }

    private func finished(_ path: String, color: RGB?, full: Bool, ok: Bool) {
        if let count = pending[path], count > 1 {
            pending[path] = count - 1
        } else {
            pending[path] = nil
            queuedColor[path] = nil
        }
        // Jobs finish in the order they were queued, so the newest one has the last word.
        if let color, ok { drawn[path] = (full, color) } else { drawn[path] = nil }
    }

    /// A custom icon ColorMyFolder did not put there (the folder is not on the list) — for example one
    /// the user pasted in Finder's Get Info. Coloring or restoring such a folder loses that icon.
    func hasForeignIcon(_ url: URL) -> Bool {
        store.color(of: url) == nil && Self.hasCustomIcon(url)
    }

    /// Finder's kHasCustomIcon flag (0x0400 in the big-endian finderFlags at offset 8 of FinderInfo).
    private static func hasCustomIcon(_ url: URL) -> Bool {
        var info = [UInt8](repeating: 0, count: 32)
        let read = getxattr(url.path, "com.apple.FinderInfo", &info, info.count, 0, 0)
        return read >= 10 && info[8] & 0x04 != 0
    }
}
