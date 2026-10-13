import AppKit
import SwiftUI

// The Help window: a big title, then sections with a picture of the app on one side and the steps on the
// other, sides taking turns. Numbered points on a picture match the numbered steps.
//
// The pictures are drawn by ColorMyFolder itself, on sample data: the folder icons by FolderRenderer, the
// window and the gear's popover rendered off screen from the very same SwiftUI views, fed with a made-up
// folder ("Projects"), saved colors and list location. Finder's menu is drawn from the words macOS shows
// there. Nothing of the user's folders, colors or list gets in, and every picture follows the app's language.

final class HelpWindow {
    static let shared = HelpWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = L("ColorMyFolder Help")
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HelpPage(pictures: HelpPictures.make()))
            // A fixed height: an `idealHeight` alone gave the window 432 pt (measured in DeskMount 0.1.50).
            w.setContentSize(NSSize(width: HelpPage.width, height: HelpPage.height))
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// A text of the Help window in the app's language (Localizable.xcstrings; the key is the English text).
func L(_ english: String) -> String { Bundle.main.localizedString(forKey: english, value: english, table: nil) }

// MARK: - Sample data

enum HelpSample {
    static var folder: URL { URL(fileURLWithPath: "/Users/demo/" + L("Projects")) }
    static let listPath = "~/Library/Mobile Documents/com~apple~CloudDocs/.ColorMyFolder"

    static let palette: [RGB] = [
        RGB(r: 0.95, g: 0.33, b: 0.33), RGB(r: 0.98, g: 0.58, b: 0.20), RGB(r: 0.98, g: 0.80, b: 0.22),
        RGB(r: 0.36, g: 0.78, b: 0.36), RGB(r: 0.20, g: 0.72, b: 0.70), RGB(r: 0.27, g: 0.55, b: 0.95),
        RGB(r: 0.55, g: 0.40, b: 0.90), RGB(r: 0.92, g: 0.40, b: 0.70), RGB(r: 0.55, g: 0.40, b: 0.30),
        RGB(r: 0.12, g: 0.12, b: 0.13), RGB(r: 0.97, g: 0.97, b: 0.97), RGB(r: 0.75, g: 0.76, b: 0.80, finish: Logic.chrome),
    ]

    static func picker(folders: [URL]) -> PickerView {
        PickerView(folders: folders, palette: palette, storePath: listPath, listUnreadable: false,
                   onPick: { _, _ in }, onSave: { _ in }, onForget: { _ in }, onRestore: { _ in },
                   onChooseFolders: { [] }, onChangeStore: { nil })
    }
}

/// Bitmaps of the app's own windows on sample data, made when the Help window opens.
struct HelpPictures {
    let picker: NSImage
    let empty: NSImage
    let settings: NSImage

    static let windowSize = NSSize(width: 360, height: 360)

    static func make() -> HelpPictures {
        HelpPictures(picker: Render.window(HelpSample.picker(folders: [HelpSample.folder]), size: windowSize),
                     empty: Render.window(HelpSample.picker(folders: []), size: windowSize),
                     settings: Render.window(PickerSettings(storePath: .constant(HelpSample.listPath), shown: .constant(true),
                                                            onChangeStore: { nil })))
    }
}

enum Render {
    /// A view drawn into a bitmap at twice its size, so it stays sharp on a Retina screen.
    static func bitmap(_ v: NSView) -> NSImage {
        let b = v.bounds
        guard b.width >= 1, b.height >= 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(b.width * 2), pixelsHigh: Int(b.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return NSImage() }
        rep.size = b.size
        v.cacheDisplay(in: b, to: rep)
        let image = NSImage(size: b.size)
        image.addRepresentation(rep)
        return image
    }

    /// A window's content rendered off screen: the same controls and texts the user sees.
    /// NSHostingView, not ImageRenderer — ImageRenderer draws forms empty and segmented pickers as a "no" sign.
    static func window<V: View>(_ view: V, size: NSSize? = nil) -> NSImage {
        let host = NSHostingView(rootView: view)
        let s = size ?? host.fittingSize
        let w = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: s.width, height: s.height),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.appearance = NSApp.effectiveAppearance
        // In a plain view with the window's own background, so no strip of the form is left transparent.
        let back = NSView(frame: NSRect(origin: .zero, size: s))
        back.wantsLayer = true
        host.frame = back.bounds
        back.addSubview(host)
        w.contentView = back
        back.layoutSubtreeIfNeeded()
        // Lazy grids and tables (the saved colors) load their cells only when drawn — one turn of the run loop
        // after a first display, so the bitmap has them (Change-Boot 0.2.29: empty pictures in the app).
        back.display()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        back.layoutSubtreeIfNeeded()
        var image = NSImage()
        w.effectiveAppearance.performAsCurrentDrawingAppearance {
            back.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            image = bitmap(back)
        }
        w.contentView = nil
        return image
    }
}

extension NSImage {
    /// A piece of the picture, in points from its top-left corner — like a cut-out screenshot.
    func cutOut(_ r: CGRect) -> NSImage {
        if r == CGRect(origin: .zero, size: size) { return self }
        return NSImage(size: r.size, flipped: false) { _ in
            self.draw(in: NSRect(x: -r.minX, y: r.maxY - self.size.height, width: self.size.width, height: self.size.height),
                      from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }
}

// MARK: - The page

struct HelpPage: View {
    static let width: CGFloat = 960
    static var height: CGFloat { min(900, (NSScreen.main?.visibleFrame.height ?? 900) - 80) }

    let pictures: HelpPictures
    /// For the bitmap of the whole page (`--export-help`): no scrolling, every section unfolded.
    var wholePage = false

    var body: some View {
        if wholePage {
            content.frame(width: Self.width).background(Color(nsColor: .windowBackgroundColor))
        } else {
            // Opens at the title: without the anchor the window came up scrolled a little way down.
            ScrollView { content }
                .defaultScrollAnchor(.top)
                .frame(width: Self.width, height: Self.height)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            ForEach(Array(HelpContent.sections.enumerated()), id: \.offset) { i, s in
                Divider().padding(.horizontal, 60)
                HelpSection(section: s, pictureLeft: i % 2 == 0, pictures: pictures, expanded: wholePage)
            }
            Divider().padding(.horizontal, 60)
            goodToKnow
            FractalSignature()
        }
        .padding(.bottom, 40)
    }

    private var header: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().interpolation(.high).frame(width: 96, height: 96)
            Text(verbatim: L(HelpContent.title)).font(.system(size: 40, weight: .semibold))
            Text(verbatim: L(HelpContent.intro))
                .font(.system(size: 17)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineSpacing(4)
                .frame(maxWidth: 640)
                .fixedSize(horizontal: false, vertical: true)
            HeaderPicture().padding(.top, 8)
        }
        .padding(.top, 44).padding(.bottom, 48).padding(.horizontal, 60)
    }

    private var goodToKnow: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: L(HelpContent.goodToKnow)).font(.system(size: 30, weight: .semibold))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20, alignment: .top), GridItem(.flexible(), spacing: 20, alignment: .top)],
                      spacing: 20) {
                ForEach(HelpContent.cards, id: \.title) { c in
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: c.symbol).font(.system(size: 22)).foregroundStyle(Color.accentColor)
                        Text(verbatim: L(c.title)).font(.headline)
                        Text(verbatim: L(c.text)).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
                }
            }
        }
        .padding(.top, 40).padding(.horizontal, 60)
    }
}

private struct HelpSection: View {
    let section: HelpContent.Section
    let pictureLeft: Bool
    let pictures: HelpPictures
    @State var expanded: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 44) {
            if pictureLeft { picture }
            text
            if !pictureLeft { picture }
        }
        .padding(.vertical, 44).padding(.horizontal, 60)
    }

    private var picture: some View {
        Group {
            switch section.picture {
            case .finder: FinderPicture()
            case .pick: WindowPicture(image: pictures.picker, crop: HelpCrops.pick)
            case .save: WindowPicture(image: pictures.picker, crop: HelpCrops.save)
            case .restore: WindowPicture(image: pictures.picker, crop: HelpCrops.restore)
            case .choose: WindowPicture(image: pictures.empty, crop: HelpCrops.choose)
            case .list: SettingsPicture(window: pictures.picker, settings: pictures.settings)
            }
        }
        .frame(width: 440)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: L(section.title)).font(.system(size: 30, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: L(section.lead)).font(.system(size: 15)).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(section.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Marker(number: i + 1, small: true)
                        Text(verbatim: L(step)).font(.system(size: 14)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let more = section.more {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Label(L(expanded ? HelpContent.less : HelpContent.more), systemImage: expanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.link)
                if expanded {
                    Text(verbatim: L(more)).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Cut-outs and points

/// Where to cut a window and where its numbered points stand, in points of the window.
/// x < 0: the point stands in the margin on the left, level with the row — it covers no text.
struct Crop {
    let rect: CGRect
    let points: [CGPoint?]

    static func m(_ y: CGFloat) -> CGPoint { CGPoint(x: -1, y: y) }
}

/// Measured on `--export-help`.
enum HelpCrops {
    private static func m(_ y: CGFloat) -> CGPoint { Crop.m(y) }
    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    static let full = CGRect(origin: .zero, size: HelpPictures.windowSize)

    static let pick = Crop(rect: full, points: [p(90, 24), m(97), p(146, 332)])
    static let save = Crop(rect: full, points: [p(112, 270), m(97)])
    static let restore = Crop(rect: full, points: [p(194, 34), nil])
    static let choose = Crop(rect: full, points: [m(24), m(58)])
}

/// A window picture in a section: the cut-out, its frame and the numbered points.
/// Never enlarged beyond 1:1 — bigger than the window it would look like a screenshot under a magnifier.
struct WindowPicture: View {
    let image: NSImage
    let crop: Crop
    var maxWidth: CGFloat = 440
    private let margin: CGFloat = 36

    var body: some View {
        let r = crop.rect
        let left: CGFloat = crop.points.contains { ($0?.x ?? 0) < 0 } ? margin : 0
        let w = min(maxWidth - left, r.width)
        let scale = w / r.width
        let h = r.height * scale
        Frame {
            HStack(spacing: 0) {
                Color.clear.frame(width: left, height: h)
                Image(nsImage: image.cutOut(r)).resizable().interpolation(.high).frame(width: w, height: h)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(crop.points.enumerated()), id: \.offset) { i, p in
                        if let p {
                            Marker(number: i + 1).position(x: p.x < 0 ? margin / 2 + 2 : left + p.x * scale, y: p.y * scale)
                        }
                    }
                }
                .frame(width: left + w, height: h, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Pictures drawn for Help

/// A calm desktop background.
private struct Desktop: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.42), Color(red: 0.42, green: 0.30, blue: 0.52),
                                Color(red: 0.78, green: 0.52, blue: 0.48)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The title picture: folders colored by ColorMyFolder's own renderer — empty ones and ones with the paper sheet.
private struct HeaderPicture: View {
    private let colors = [HelpSample.palette[0], HelpSample.palette[1], HelpSample.palette[3], HelpSample.palette[5],
                          HelpSample.palette[6], HelpSample.palette[11]]

    var body: some View {
        Frame {
            ZStack {
                Desktop()
                HStack(spacing: 18) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { i, c in
                        if let icon = FolderRenderer.icon(for: c, full: i % 2 == 1) {
                            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 84, height: 84)
                        }
                    }
                }
            }
            .frame(width: 660, height: 200)
        }
    }
}

/// Finder's menu on a folder, with Quick Actions open at ColorMyFolder — drawn from the words macOS shows there.
private struct FinderPicture: View {
    var body: some View {
        Frame {
            ZStack(alignment: .topLeading) {
                Desktop()
                VStack(spacing: 6) {
                    if let icon = FolderRenderer.icon(for: HelpSample.palette[5], full: true) {
                        Image(nsImage: icon).resizable().frame(width: 72, height: 72)
                    }
                    Text(verbatim: L("Projects")).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
                }
                .position(x: 70, y: 70)
                menu.position(x: 205, y: 140)
                submenu.position(x: 365, y: 186)
            }
            .frame(width: 440, height: 290)
        }
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Marker(number: 1).position(x: 30, y: 30)
                Marker(number: 2).position(x: 100, y: 170)
                Marker(number: 3).position(x: 284, y: 186)
            }
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            item(L("Open"))
            divider
            item(L("Get Info"))
            item(L("Rename"))
            divider
            item(L("Quick Actions"), chevron: true, selected: true)
            item(L("Services"), chevron: true)
        }
        .padding(.vertical, 5)
        .frame(width: 180)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.17).opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }

    private var submenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            item("ColorMyFolder", selected: true)
        }
        .padding(.vertical, 5)
        .frame(width: 150)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.17).opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 10)
    }

    private func item(_ text: String, chevron: Bool = false, selected: Bool = false) -> some View {
        HStack {
            Text(verbatim: text).font(.system(size: 13)).foregroundStyle(.white).lineLimit(1).fixedSize()
            Spacer(minLength: 8)
            if chevron { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.7)) }
        }
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Color.accentColor : .clear).padding(.horizontal, 5))
    }
}

/// The gear's popover over the top of the window, as it opens there.
private struct SettingsPicture: View {
    let window: NSImage
    let settings: NSImage

    var body: some View {
        let s = settings.size
        WindowPicture(image: window, crop: Crop(rect: CGRect(x: 0, y: 0, width: 360, height: 360), points: []))
            .overlay(alignment: .topTrailing) {
                Image(nsImage: settings).resizable().interpolation(.high).frame(width: s.width * 0.8, height: s.height * 0.8)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    .padding(.top, 34).padding(.trailing, 12)
            }
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Marker(number: 1).position(x: 286, y: 22)
                    Marker(number: 2).position(x: 96, y: 70)
                    Marker(number: 3).position(x: 96, y: 159)
                }
            }
    }
}

/// The numbered point on a picture, and the same number in front of a step.
struct Marker: View {
    let number: Int
    var small = false

    var body: some View {
        Text(verbatim: "\(number)")
            .font(.system(size: small ? 11 : 13, weight: .bold)).monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: small ? 20 : 26, height: small ? 20 : 26)
            .background(Circle().fill(Color.accentColor))
            .overlay(Circle().stroke(.white, lineWidth: small ? 0 : 2))
            .shadow(color: .black.opacity(small ? 0 : 0.35), radius: 3, y: 1)
    }
}

/// Rounded card with a soft shadow — the frame every picture sits in.
struct Frame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

/// The Fractal 8 Dev signature at the end of Help, set like the hero of fractal8.eu: the logo large behind,
/// under the same veil as the site's video (darker at the edges and towards the bottom), and the text over
/// its lower part — "ENDLESS RECURSION" spaced 0.42 em in the accent (#7ee8f2 dark, #0a8796 light), then
/// "Fractal 8 Dev" in SF Pro Bold drawn together by −0.045 em with the site's gradient, then the site's line.
private struct FractalSignature: View {
    @Environment(\.colorScheme) private var scheme
    private static let logo: NSImage? = Bundle.main.url(forResource: "studio-logo", withExtension: "png").flatMap(NSImage.init(contentsOf:))

    var body: some View {
        let dark = scheme == .dark
        let back = Color(nsColor: .windowBackgroundColor)
        let accent = dark ? Color(red: 126 / 255, green: 232 / 255, blue: 242 / 255) : Color(red: 10 / 255, green: 135 / 255, blue: 150 / 255)
        let gradient = LinearGradient(stops: [
            .init(color: dark ? .white : Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255), location: 0.4),
            .init(color: dark ? Color(red: 159 / 255, green: 163 / 255, blue: 171 / 255) : Color(red: 91 / 255, green: 95 / 255, blue: 102 / 255), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        ZStack(alignment: .bottom) {
            if let logo = Self.logo {
                Image(nsImage: logo).resizable().interpolation(.high).frame(width: 560, height: 560)
                    .opacity(dark ? 0.75 : 0.55)
                    .frame(height: 440, alignment: .top)
                    .clipped()
                    // The site's veil (styles.css, .hero-sticky::after): edges and the bottom sink into the background.
                    .overlay(RadialGradient(stops: [.init(color: .clear, location: 0.35), .init(color: back.opacity(0.75), location: 1)],
                                            center: .center, startRadius: 0, endRadius: 300))
                    .overlay(LinearGradient(stops: [.init(color: back.opacity(0.35), location: 0), .init(color: .clear, location: 0.3),
                                                    .init(color: back.opacity(0.55), location: 0.62), .init(color: back, location: 0.92)],
                                            startPoint: .top, endPoint: .bottom))
            }
            VStack(spacing: 0) {
                Text(verbatim: "ENDLESS RECURSION")
                    .font(.system(size: 12)).tracking(12 * 0.42).foregroundStyle(accent)
                    .padding(.bottom, 16)
                Text(verbatim: "Fractal 8 Dev")
                    .font(.system(size: 76, weight: .bold)).tracking(-76 * 0.045)
                    .foregroundStyle(gradient)
                Text(verbatim: L(HelpContent.signatureLine))
                    .font(.system(size: 17)).foregroundStyle(.secondary)
                    .padding(.top, 18)
            }
            .padding(.bottom, 30)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 440)
        .padding(.top, 40)
    }
}

// MARK: - Bitmap of the Help page, for checking it without opening a window

/// `ColorMyFolder --export-help <folder>` (language from `-AppleLanguages '(pl)'`): draws the Help page and the
/// window pictures into PNG files and quits. The app's normal start never runs: no list, no watching, no
/// login item, no window on screen.
enum HelpExport {
    static func runIfRequested() {
        let a = CommandLine.arguments
        // `--export-help-window <folder>`: the Help window as the app shows it (pictures made the way `show()`
        // makes them, the page in a scroll view), to check what the user sees, not only the export.
        if let i = a.firstIndex(of: "--export-help-window"), i + 1 < a.count {
            NSApplication.shared.setActivationPolicy(.prohibited)
            let folder = URL(fileURLWithPath: a[i + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let size = NSSize(width: HelpPage.width, height: 900)
            let host = NSHostingView(rootView: HelpPage(pictures: HelpPictures.make()))
            let w = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height),
                             styleMask: [.borderless], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            host.frame = NSRect(origin: .zero, size: size)
            w.contentView = host
            w.orderFrontRegardless()
            RunLoop.current.run(until: Date().addingTimeInterval(2))
            let lang = Bundle.main.preferredLocalizations.first ?? "en"
            save(Render.bitmap(host), folder.appendingPathComponent("help-window-\(lang).png"))
            exit(0)
        }
        guard let i = a.firstIndex(of: "--export-help"), i + 1 < a.count else { return }
        let folder = URL(fileURLWithPath: a[i + 1], isDirectory: true)
        NSApplication.shared.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        let p = HelpPictures.make()
        for (name, image) in [("picker", p.picker), ("empty", p.empty), ("settings", p.settings)] {
            save(image, folder.appendingPathComponent("window-\(name)-\(lang).png"))
        }
        let page = HelpPage(pictures: p, wholePage: true)
        // The height measured at the fixed width — `fittingSize` measures without it and cuts the top and bottom off.
        let h = NSHostingController(rootView: page)
            .sizeThatFits(in: CGSize(width: HelpPage.width, height: CGFloat.greatestFiniteMagnitude)).height
        save(Render.window(page, size: NSSize(width: HelpPage.width, height: ceil(h))), folder.appendingPathComponent("help-\(lang).png"))
        exit(0)
    }

    private static func save(_ image: NSImage, _ url: URL) {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        FileHandle.standardOutput.write(Data("\(url.path) \(Int(image.size.width))×\(Int(image.size.height))\n".utf8))
    }
}
