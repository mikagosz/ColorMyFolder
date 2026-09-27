import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private lazy var colorizer = Colorizer(store: store)
    private lazy var watcher = Watcher { [weak self] in self?.somethingChanged() }
    private var panel: NSPanel?
    /// How this launch started — decides whether a window opens on its own.
    private enum Launch { case normal, atLogin, withFolders }
    private var launch = Launch.normal

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return }
        if event.eventID == AEEventID(kAEOpenDocuments) {
            launch = .withFolders
        } else if event.eventID == AEEventID(kAEOpenApplication),
                  event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem) {
            launch = .atLogin
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if store.directory == nil && launch != .atLogin { setUpList() }
        store.reload()

        QuickAction.install()
        registerLoginItem()

        colorizer.refreshAll()
        rewatch()

        // Started from the app icon (not at login, not from Finder with folders): open the window.
        if launch == .normal {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.panel?.isVisible != true else { return }
                self.showPicker(for: [])
            }
        }
    }

    // MARK: - Finder quick action

    /// Finder → right click → Quick Actions (or Services) → ColorMyFolder runs
    /// `open -b com.mikagosz.ColorMyFolder <folders>`, which lands here.
    func application(_ application: NSApplication, open urls: [URL]) {
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        guard !folders.isEmpty else { return }
        if store.directory == nil { setUpList() }
        store.reload()
        showPicker(for: folders)
    }

    /// Opening the app again (Finder, Spotlight, Dock) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store.reload()
        showPicker(for: [])
        return false
    }

    private func showPicker(for urls: [URL]) {
        panel?.close()
        let view = PickerView(
            folders: urls,
            palette: store.data.palette,
            storePath: store.directory?.path ?? "",
            onPick: { [weak self] folders, rgb in
                guard let self else { return }
                folders.forEach { self.colorizer.apply(rgb, to: $0) }
                self.rewatch()
                self.panel?.close()
            },
            onSave: { [weak self] rgb in self?.store.addToPalette(rgb) },
            onForget: { [weak self] rgb in self?.store.removeFromPalette(rgb) },
            onRestore: { [weak self] folders in
                guard let self else { return }
                folders.forEach { self.colorizer.clear($0) }
                self.rewatch()
                self.panel?.close()
            },
            onChooseFolders: { Self.chooseFolders() },
            onChangeStore: { [weak self] in
                guard let self, self.askForDirectory() else { return nil }
                self.store.reload()
                self.colorizer.refreshAll()
                self.rewatch()
                // The list in the new place may hold other dots — rebuild the window with them.
                DispatchQueue.main.async { self.showPicker(for: urls) }
                return self.store.directory?.path
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

    private static func chooseFolders() -> [URL] {
        let open = NSOpenPanel()
        open.title = "ColorMyFolder"
        open.message = String(localized: "Choose the folders to color.")
        open.prompt = String(localized: "Choose")
        open.canChooseFiles = false
        open.canChooseDirectories = true
        open.allowsMultipleSelection = true
        NSApp.activate()
        return open.runModal() == .OK ? open.urls : []
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

    /// First launch on this Mac. A list made on another Mac may already be here through a synced
    /// folder — offer it before asking for a place.
    private func setUpList() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = [home, home.appendingPathComponent("Desktop"), home.appendingPathComponent("Documents"),
                     home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")].map(\.path)
        if let found = Logic.existingLists(in: roots).first {
            let directory = URL(fileURLWithPath: found)
            let alert = NSAlert()
            alert.messageText = String(localized: "ColorMyFolder found an existing list")
            alert.informativeText = "\(found)\n\(Store.summary(of: directory) ?? "")\n\n"
                + String(localized: "Use it to share colors with your other Mac, or choose another place.")
            alert.addButton(withTitle: String(localized: "Use This List"))
            alert.addButton(withTitle: String(localized: "Choose Another Place…"))
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                store.directory = directory
                return
            }
        }
        askForDirectory()
    }

    /// The user decides where the list lives.
    @discardableResult
    private func askForDirectory() -> Bool {
        let open = NSOpenPanel()
        open.title = "ColorMyFolder"
        open.message = String(localized: "Where should ColorMyFolder keep its list of colors and colored folders? It creates a hidden .ColorMyFolder folder in the place you choose. Choose a folder you sync between your Macs, and both will have the same colors.")
        open.prompt = String(localized: "Choose")
        open.canChooseFiles = false
        open.canChooseDirectories = true
        open.canCreateDirectories = true
        NSApp.activate()
        guard open.runModal() == .OK, let url = open.url else { return false }
        let directory = URL(fileURLWithPath: Logic.storeDirectory(forChosen: url.path))
        let file = directory.appendingPathComponent(Store.fileName)
        if FileManager.default.fileExists(atPath: file.path) {
            let alert = NSAlert()
            alert.messageText = String(localized: "This place already has a ColorMyFolder list")
            alert.informativeText = (Store.summary(of: directory) ?? "") + "\n\n"
                + String(localized: "A new list sets the old one aside in the same folder. Another Mac using this place will switch to the new list too.")
            alert.addButton(withTitle: String(localized: "Use It"))
            alert.addButton(withTitle: String(localized: "Start a New List"))
            if alert.runModal() != .alertFirstButtonReturn {
                let aside = directory.appendingPathComponent(Logic.setAsideName(date: Date()))
                do {
                    try FileManager.default.moveItem(at: file, to: aside)
                } catch {
                    log.error("Cannot set old list aside: \(error.localizedDescription, privacy: .public)")
                    return false
                }
            }
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            store.directory = directory
            return true
        } catch {
            log.error("Cannot create \(directory.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
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
}
