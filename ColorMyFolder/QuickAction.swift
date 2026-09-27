import AppKit

/// Keeps `~/Library/Services/ColorMyFolder.workflow` in step with the copy inside the app.
/// An Automator quick action is the only way to get an icon next to the item in Finder's menu —
/// plain app services have none, and action extensions need the sandbox. `NSIconName` takes an
/// image name, not an SF Symbol, so the `paintpalette` symbol is rendered into the installed
/// workflow as a template PNG (the symbol itself stays Apple's and is not shipped in the repo).
enum QuickAction {
    private static let name = "ColorMyFolder.workflow"
    private static let iconName = "ColorMyFolderTemplate"
    private static let symbol = "paintpalette"

    static func install() {
        guard let source = Bundle.main.url(forResource: "ColorMyFolder", withExtension: "workflow") else {
            log.error("Quick action missing from the app bundle")
            return
        }
        let services = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Services")
        let target = services.appendingPathComponent(name)
        let resources = target.appendingPathComponent("Contents/Resources")
        let icons = [(1, resources.appendingPathComponent("\(iconName).png")),
                     (2, resources.appendingPathComponent("\(iconName)@2x.png"))]
        let iconsPresent = icons.allSatisfy { FileManager.default.fileExists(atPath: $0.1.path) }
        guard !(sameContents(source, target) && iconsPresent) else { return }
        do {
            try FileManager.default.createDirectory(at: services, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: source, to: target)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            for (scale, url) in icons {
                guard let png = renderSymbol(scale: scale) else { throw CocoaError(.fileWriteUnknown) }
                try png.write(to: url)
            }
            NSUpdateDynamicServices()
        } catch {
            log.error("Cannot install quick action: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 16 pt template image: black symbol on transparent background.
    private static func renderSymbol(scale: Int) -> Data? {
        let pixels = 16 * scale
        let config = NSImage.SymbolConfiguration(pointSize: CGFloat(pixels) * 0.8, weight: .regular)
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config),
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let size = image.size
        let rect = NSRect(x: (CGFloat(pixels) - size.width) / 2, y: (CGFloat(pixels) - size.height) / 2,
                          width: size.width, height: size.height)
        image.draw(in: rect)
        NSColor.black.set()
        rect.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private static func sameContents(_ a: URL, _ b: URL) -> Bool {
        ["Contents/Info.plist", "Contents/document.wflow"].allSatisfy { file in
            let left = try? Data(contentsOf: a.appendingPathComponent(file))
            let right = try? Data(contentsOf: b.appendingPathComponent(file))
            return left != nil && left == right
        }
    }
}
