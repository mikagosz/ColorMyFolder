import AppKit

// `--export-help <folder>`: the Help page as PNG files, without the app's normal start (HelpWindow.swift).
HelpExport.runIfRequested()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
