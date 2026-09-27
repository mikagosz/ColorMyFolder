// Renders ColorMyFolder's app icon into ColorMyFolder/Assets.xcassets/AppIcon.appiconset.
// The icon is built at build time from the folder parts macOS ships (CoreTypes.bundle),
// so no Apple artwork is stored in the repository: a system-blue folder with the paper
// sheet, and large "pixels" in ten ColorMyFolder colors spreading from the bottom-left corner.
// Run by build.sh; by hand: swift Tools/make-icon.swift
import AppKit

let core = Bundle(path: "/System/Library/CoreServices/CoreTypes.bundle")!
let output = URL(fileURLWithPath: "ColorMyFolder/Assets.xcassets/AppIcon.appiconset")

struct HSB { var h: CGFloat; var s: CGFloat; var b: CGFloat }

func hsb(_ hex: Int) -> HSB {
    let c = NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                    blue: CGFloat(hex & 255) / 255, alpha: 1).usingColorSpace(.deviceRGB)!
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    return HSB(h: h, s: s, b: b)
}

// Crimson, coral, amber, lime, emerald, turquoise, ice blue, indigo, lavender, raspberry — by hue.
let colors: [Int] = [0xA3152E, 0xF06449, 0xE89B0C, 0xA6D43A, 0x1E9E6A, 0x2BC4C4, 0x9BD3F2, 0x4B3FA8, 0xB39DE8, 0xD6246E]
func order(_ x: HSB) -> CGFloat { x.h > 0.95 ? x.h - 1 : x.h }
let palette = colors.map(hsb).sorted { order($0) < order($1) }

// 8×8 grid over the icon; colored cells reach out from the bottom-left corner with a ragged edge.
let grid = 8
func cellHash(_ x: Int, _ y: Int) -> Int { ((x * 73856093) ^ (y * 19349663) ^ 0x5bd1e995) & 0x7fffffff }
func pixelColor(_ fx: CGFloat, _ fyFromTop: CGFloat) -> HSB? {
    let cx = min(grid - 1, Int(fx * CGFloat(grid)))
    let cy = min(grid - 1, Int((1 - fyFromTop) * CGFloat(grid)))
    let h = cellHash(cx, cy)
    guard cx + cy + h % 3 <= 8 else { return nil }
    return palette[(h / 3) % palette.count]
}

func blank(_ px: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: px * 4, bitsPerPixel: 32)!
}

func part(_ name: String, _ px: Int) -> NSBitmapImageRep {
    let rep = blank(px)
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    core.image(forResource: name)!.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }

/// Recolors the cells that get a color, relative to the system blue, so the shading stays.
func paint(_ rep: NSBitmapImageRep) {
    let d = rep.bitmapData!
    let w = rep.pixelsWide
    for i in 0..<(w * rep.pixelsHigh) {
        let o = i * 4
        let a = CGFloat(d[o + 3]) / 255
        guard a > 0, let t = pixelColor(CGFloat(i % w) / CGFloat(w), CGFloat(i / w) / CGFloat(rep.pixelsHigh)) else { continue }
        let c = NSColor(deviceRed: CGFloat(d[o]) / 255 / a, green: CGFloat(d[o + 1]) / 255 / a,
                        blue: CGFloat(d[o + 2]) / 255 / a, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, x: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &x)
        let n = NSColor(deviceHue: t.h, saturation: min(1, s * t.s / 0.62), brightness: min(1, b * t.b / 0.90), alpha: 1)
        d[o] = byte(n.redComponent * a)
        d[o + 1] = byte(n.greenComponent * a)
        d[o + 2] = byte(n.blueComponent * a)
    }
}

func icon(points: Int, pixels: Int) -> NSBitmapImageRep {
    let back = part("FolderComponent_BackFlap/image_\(points)", pixels)
    let paper = part("FolderComponent_PaperSheet/image_\(points)", pixels)
    let front = part("FolderComponent_FrontFlap/image_\(points)", pixels)
    paint(back)
    paint(front)
    let out = blank(pixels)
    out.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    for layer in [back, paper, front] {
        layer.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    }
    NSGraphicsContext.restoreGraphicsState()
    return out
}

try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let file = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        // The system parts exist at 16, 32, 128, 256 and 512 pt; @2x uses the same part at double size.
        let png = icon(points: points, pixels: points * scale).representation(using: .png, properties: [:])!
        try! png.write(to: output.appendingPathComponent(file))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": file])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
let catalog: [String: Any] = ["info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted])
    .write(to: output.deletingLastPathComponent().appendingPathComponent("Contents.json"))
print("App icon written to \(output.path)")
