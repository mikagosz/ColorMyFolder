import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private lazy var colorizer = Colorizer(store: store)
    private lazy var watcher = Watcher { [weak self] in self?.somethingChanged() }
    private var panel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if store.directory == nil { askForDirectory() }
        store.reload()

        QuickAction.install()
        registerLoginItem()

        colorizer.refreshAll()
        rewatch()
    }

    // MARK: - Finder quick action

    /// Finder → right click → Quick Actions (or Services) → ColorMyFolder runs
    /// `open -b com.mikagosz.ColorMyFolder <folders>`, which lands here.
    func application(_ application: NSApplication, open urls: [URL]) {
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        guard !folders.isEmpty else { return }
        if store.directory == nil { askForDirectory() }
        store.reload()
        showPicker(for: folders)
    }

    private func showPicker(for urls: [URL]) {
        panel?.close()
        let view = PickerView(
            folders: urls,
            palette: store.data.palette,
            onPick: { [weak self] rgb in
                guard let self else { return }
                urls.forEach { self.colorizer.apply(rgb, to: $0) }
                self.rewatch()
                self.panel?.close()
            },
            onSave: { [weak self] rgb in self?.store.addToPalette(rgb) },
            onForget: { [weak self] rgb in self?.store.removeFromPalette(rgb) },
            onRestore: { [weak self] in
                guard let self else { return }
                urls.forEach { self.colorizer.clear($0) }
                self.rewatch()
                self.panel?.close()
            })
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "ColorMyFolder"
        panel.contentViewController = NSHostingController(rootView: view)
        panel.isReleasedWhenClosed = false
        // Panels hide when the app loses focus; a stray click on the desktop would close the picker.
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.center()
        self.panel = panel
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Watching

    private func somethingChanged() {
        store.reload()
        colorizer.refreshAll()
        rewatch()
    }

    private func rewatch() {
        var paths = store.data.folders.map { store.absoluteURL($0).path }
        if let directory = store.directory?.path { paths.append(directory) }
        watcher.watch(paths)
    }

    // MARK: - Setup

    /// First launch on each Mac: the user decides where the list lives.
    private func askForDirectory() {
        let open = NSOpenPanel()
        open.title = "ColorMyFolder"
        open.message = String(localized: "Where should ColorMyFolder keep its list of colors and colored folders? It creates a hidden .ColorMyFolder folder in the place you choose. Choose a folder you sync between your Macs, and both will have the same colors.")
        open.prompt = String(localized: "Choose")
        open.canChooseFiles = false
        open.canChooseDirectories = true
        open.canCreateDirectories = true
        NSApp.activate()
        guard open.runModal() == .OK, let url = open.url else { return }
        let directory = URL(fileURLWithPath: Logic.storeDirectory(forChosen: url.path))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            store.directory = directory
        } catch {
            log.error("Cannot create \(directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func registerLoginItem() {
        // The app has to run in the background to switch the paper sheet when folders fill up.
        guard SMAppService.mainApp.status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            log.error("Cannot register login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Opening the app again (Finder, Spotlight) lets the user move the list.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        askForDirectory()
        store.reload()
        colorizer.refreshAll()
        rewatch()
        return false
    }
}
