import CoreServices
import Foundation

/// FSEvents on the coloured folders and on the list's own folder (the other Mac edits the list).
final class Watcher {
    private var stream: FSEventStreamRef?
    private var colored: Set<String> = []
    private var listDirectory: String?
    /// What the running stream watches. Asked to watch the same again, it keeps that stream:
    /// a new one starts "from now", and a change made in between would be lost.
    private var watched: [String] = []
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    func watch(colored folders: [String], listDirectory: String?) {
        let paths = folders + (listDirectory.map { [$0] } ?? [])
        if stream != nil && paths == watched { return }
        stop()
        colored = Set(folders.map(Self.real))
        self.listDirectory = listDirectory.map(Self.real)
        guard !paths.isEmpty else { return }
        watched = paths
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<Watcher>.fromOpaque(info).takeUnretainedValue()
            let changed = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            // MustScanSubDirs: events were dropped, so the change could be anywhere.
            let dropped = (0..<count).contains { flags[$0] & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 }
            if dropped || changed.contains(where: {
                Logic.isRelevant(changedFolder: $0, coloredFolders: watcher.colored, listDirectory: watcher.listDirectory)
            }) {
                watcher.onChange()
            }
        }
        stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                     FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes))
        guard let stream else {
            log.error("Cannot create FSEvents stream")
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        watched = []
    }

    /// FSEvents reports paths with symlinks resolved; compare like with like.
    private static func real(_ path: String) -> String {
        Logic.trimmedSlash(URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
    }
}
