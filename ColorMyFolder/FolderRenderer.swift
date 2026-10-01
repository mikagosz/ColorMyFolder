import AppKit

/// Builds a folder icon from the same parts Finder uses (CoreTypes.bundle:
/// back flap, paper sheet, front flap), recoloured so the system gradient and shading stay.
enum FolderRenderer {
    private static let core = Bundle(path: "/System/Library/CoreServices/CoreTypes.bundle")

    /// (point size of the asset, pixel size of the representation)
    private static let sizes: [(Int, Int)] = [
        (16, 16), (16, 32), (32, 32), (32, 64), (128, 128),
        (128, 256), (256, 256), (256, 512), (512, 512), (512, 1024),
    ]

    /// Finished icons by color and empty/full — the same color on many folders is drawn once.
    /// One icon holds about 6 MB of bitmaps, so only a few are kept. Used only from Colorizer's
    /// drawing queue, one folder at a time, so it needs no lock.
    private static var cache: [String: NSImage] = [:]
    private static let cacheLimit = 6

    static func icon(for rgb: RGB, full: Bool) -> NSImage? {
        let key = "\(rgb.r) \(rgb.g) \(rgb.b) \(rgb.finish ?? "") \(full)"
        if let cached = cache[key] { return cached }
        guard let icon = render(rgb, full: full) else { return nil }
        if cache.count >= cacheLimit { cache.removeAll() }
        cache[key] = icon
        return icon
    }

    private static func render(_ rgb: RGB, full: Bool) -> NSImage? {
        guard let target = rgb.color.usingColorSpace(.deviceRGB) else { return nil }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        target.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let shade = Logic.Shade(h: Double(hue), s: Double(saturation), b: Double(brightness))

        let icon = NSImage(size: NSSize(width: 512, height: 512))
        for (points, pixels) in sizes {
            guard let back = bitmap("FolderComponent_BackFlap/image_\(points)", pixels),
                  let front = bitmap("FolderComponent_FrontFlap/image_\(points)", pixels),
                  let out = emptyBitmap(pixels) else { return nil }
            recolor(back, target: shade, finish: rgb.finish)
            recolor(front, target: shade, finish: rgb.finish)
            out.size = NSSize(width: points, height: points)

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
            let rect = NSRect(x: 0, y: 0, width: points, height: points)
            // Bitmap reps draw with .copy by default, which would wipe the layer below.
            draw(back, in: rect)
            if full, let paper = bitmap("FolderComponent_PaperSheet/image_\(points)", pixels) {
                draw(paper, in: rect)
            }
            draw(front, in: rect)
            NSGraphicsContext.restoreGraphicsState()
            icon.addRepresentation(out)
        }
        return icon
    }

    private static func draw(_ rep: NSBitmapImageRep, in rect: NSRect) {
        rep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    }

    private static func emptyBitmap(_ pixels: Int) -> NSBitmapImageRep? {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                         colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32)
    }

    private static func bitmap(_ name: String, _ pixels: Int) -> NSBitmapImageRep? {
        guard let image = core?.image(forResource: name), let rep = emptyBitmap(pixels) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func recolor(_ rep: NSBitmapImageRep, target: Logic.Shade, finish: String?) {
        guard let data = rep.bitmapData else { return }
        let width = rep.pixelsWide, height = rep.pixelsHigh
        for i in 0..<(width * height) {
            let o = i * 4
            let alpha = Double(data[o + 3]) / 255
            if alpha == 0 { continue }
            let source = Logic.hsb(r: min(1, Double(data[o]) / 255 / alpha),
                                   g: min(1, Double(data[o + 1]) / 255 / alpha),
                                   b: min(1, Double(data[o + 2]) / 255 / alpha))
            let painted = Logic.paint(source: source, target: target, finish: finish,
                                      y: Double(i / width) / Double(height))
            let result = Logic.rgb(painted)
            data[o] = byte(result.r * alpha)
            data[o + 1] = byte(result.g * alpha)
            data[o + 2] = byte(result.b * alpha)
        }
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }
}
