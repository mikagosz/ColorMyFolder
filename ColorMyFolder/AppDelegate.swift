import AppKit
import Darwin
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
    /// The first-launch question about the list's place is asked once per launch, even when
    /// Finder's folders and the launch itself both find the place unset.
    private var askedForList = false

    private let launchedAt = Date()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // No early return without an event: macOS 27's loginwindow can start the app with none,
        // and the login-time check below must still run.
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event?.eventID == AEEventID(kAEOpenDocuments) {
            launch = .withFolders
        } else if event?.eventID == AEEventID(kAEOpenApplication),
                  event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem) {
            launch = .atLogin
        }
        if launch == .normal && Logic.startedWithLogin(launch: launchedAt, login: Self.consoleLoginTime()) {
            launch = .atLogin
        }
        let eventName = event.map { String(format: "%08x", $0.eventID) } ?? "none"
        log.info("Launch: \(String(describing: self.launch), privacy: .public), event \(eventName, privacy: .public)")
    }

    /// When the user last logged in on this Mac's screen — the same record `last` reads.
    private static func consoleLoginTime() -> Date? {
        var latest: Date?
        setutxent()
        defer { endutxent() }
        while let entry = getutxent() {
            var record = entry.pointee
            guard record.ut_type == USER_PROCESS else { continue }
            let line = withUnsafeBytes(of: &record.ut_line) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let user = withUnsafeBytes(of: &record.ut_user) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            guard line == "console", user == NSUserName() else { continue }
            let time = Date(timeIntervalSince1970: TimeInterval(record.ut_tv.tv_sec))
            if latest.map({ time > $0 }) ?? true { latest = time }
        }
        return latest
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if store.directory == nil && launch != .atLogin && !askedForList { setUpList() }
        store.reload()

        QuickAction.install()
        registerLoginItem()

        Updates.shared.isBusy = { [weak self] in self?.colorizer.isWorking ?? false }
        Updates.shared.start()

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
        let folders = urls.filter(Logic.isPlainFolder)
        guard !folders.isEmpty else { return }
        if store.directory == nil && !askedForList { setUpList() }
        store.reload()
        showPicker(for: folders)
    }

    /// Opening the app again (Finder, Spotlight, Dock) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A start at login can be followed by a "reopen" from the system itself, not the user.
        if Logic.reopenFromLogin(atLogin: launch == .atLogin, since: Date().timeIntervalSince(launchedAt)) {
            log.info("Reopen right after a start at login — no window")
            return false
        }
        store.reload()
        showPicker(for: [])
        return false
    }

    private func showPicker(for urls: [URL]) {
        let view = PickerView(
            folders: urls,
            palette: store.data.palette,
            storePath: store.directory?.path ?? "",
            listUnreadable: store.directory != nil && !store.readable,
            onPick: { [weak self] folders, rgb in
                guard let self, self.confirmReplacingIcons(of: folders, restoring: false) else { return }
                self.colorizer.apply(rgb, to: folders)
                self.rewatch()
                self.panel?.close()
            },
            onSave: { [weak self] rgb in self?.store.addToPalette(rgb) },
            onForget: { [weak self] rgb in self?.store.removeFromPalette(rgb) },
            onRestore: { [weak self] folders in
                guard let self, self.confirmReplacingIcons(of: folders, restoring: true) else { return }
                self.colorizer.clear(folders)
                self.rewatch()
                self.panel?.close()
            },
            onChooseFolders: { Self.chooseFolders() },
            onChangeStore: { [weak self] in
                guard let self, self.askForDirectory() else { return nil }
                self.store.reload()
                self.colorizer.refreshAll()
                self.rewatch()
                // The list in the new place may hold other colors — rebuild the window with them.
                DispatchQueue.main.async { self.showPicker(for: urls) }
                return self.store.directory?.path
            })
        let panel = self.panel ?? makePanel(colors: store.data.palette.count)
        // A fresh identity each time: the window's state starts from these folders and colors.
        (panel.contentViewController as? NSHostingController<AnyView>)?.rootView = AnyView(view.id(UUID()))
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private static let windowFrameName = "ColorMyFolderWindow"

    /// One window for the whole run, reused on every open. It can be resized, and macOS keeps the
    /// size and place the user gave it (frame autosave) across opens and launches. The first time
    /// it is tall enough for the saved colors, up to a limit — beyond that the colors scroll.
    private func makePanel(colors: Int) -> NSPanel {
        let host = NSHostingController(rootView: AnyView(EmptyView()))
        host.sizingOptions = []
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                            backing: .buffered, defer: false)
        panel.title = "ColorMyFolder"
        panel.contentViewController = host
        panel.isReleasedWhenClosed = false
        // Panels hide when the app loses focus; a stray click on the desktop would close the picker.
        // The window stays on the normal level, so other apps' windows can cover it.
        panel.hidesOnDeactivate = false
        panel.contentMinSize = NSSize(width: 340, height: 280)
        panel.setContentSize(NSSize(width: 360, height: Logic.initialWindowHeight(colors: colors)))
        if !panel.setFrameUsingName(Self.windowFrameName) { panel.center() }
        panel.setFrameAutosaveName(Self.windowFrameName)
        self.panel = panel
        return panel
    }

    /// Folders with a custom icon of their own lose it for good — ask first.
    private func confirmReplacingIcons(of folders: [URL], restoring: Bool) -> Bool {
        let foreign = folders.filter { colorizer.hasForeignIcon($0) }
        guard !foreign.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = restoring
            ? String(localized: "Remove a custom icon ColorMyFolder did not set?")
            : String(localized: "Replace a custom icon ColorMyFolder did not set?")
        alert.informativeText = foreign.map(\.lastPathComponent).joined(separator: "\n") + "\n\n"
            + String(localized: "This folder already has its own icon. ColorMyFolder cannot bring it back afterwards.")
        alert.addButton(withTitle: restoring ? String(localized: "Remove Icon") : String(localized: "Replace Icon"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
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
        watcher.watch(colored: store.data.folders.map { store.absoluteURL($0).path },
                      listDirectory: store.directory?.path)
    }

    // MARK: - Setup

    /// First launch on this Mac. A list made on another Mac may already be here through a synced
    /// folder — offer it before asking for a place.
    private func setUpList() {
        askedForList = true
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

    /// The app has to run in the background to switch the paper sheet when folders fill up.
    /// It adds itself to Login Items once; if the user turns that off later, it stays off.
    private func registerLoginItem() {
        let key = "loginItemAdded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        do {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            log.error("Cannot register login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
