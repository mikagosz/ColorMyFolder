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

    static func icon(for rgb: RGB, full: Bool) -> NSImage? {
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
            let alpha = CGFloat(data[o + 3]) / 255
            if alpha == 0 { continue }
            let source = NSColor(deviceRed: CGFloat(data[o]) / 255 / alpha,
                                 green: CGFloat(data[o + 1]) / 255 / alpha,
                                 blue: CGFloat(data[o + 2]) / 255 / alpha, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            source.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            let painted = Logic.paint(source: Logic.Shade(h: Double(h), s: Double(s), b: Double(b)), target: target,
                                      finish: finish, y: Double(i / width) / Double(height))
            let result = NSColor(deviceHue: painted.h, saturation: painted.s, brightness: painted.b, alpha: 1)
            data[o] = byte(result.redComponent * alpha)
            data[o + 1] = byte(result.greenComponent * alpha)
            data[o + 2] = byte(result.blueComponent * alpha)
        }
    }

    private static func byte(_ value: CGFloat) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }
}
