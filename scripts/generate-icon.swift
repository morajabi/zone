import AppKit
import Foundation

// Original geometric artwork, generated locally. No external assets or fonts.
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("build/Zone.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
                       ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                       ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512),
                       ("icon_512x512@2x", 1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = AffineTransform(scale: Double(pixels) / 1024)
    (transform as NSAffineTransform).concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    NSGradient(starting: NSColor(srgbRed: 0.06, green: 0.22, blue: 0.24, alpha: 1),
               ending: NSColor(srgbRed: 0.035, green: 0.10, blue: 0.13, alpha: 1))!.draw(in: background, angle: -90)
    let ring = NSBezierPath()
    ring.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 235, startAngle: 65, endAngle: 385)
    ring.lineWidth = 54
    ring.lineCapStyle = .round
    NSColor(srgbRed: 0.39, green: 0.91, blue: 0.79, alpha: 1).setStroke()
    ring.stroke()
    NSColor(srgbRed: 0.88, green: 1, blue: 0.96, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 456, y: 456, width: 112, height: 112)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name + ".png"))
}
