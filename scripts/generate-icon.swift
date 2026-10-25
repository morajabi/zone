import AppKit
import Foundation

// Original artwork matching Resources/Brand/zone-icon.svg, in its 1024-unit
// coordinate space. This tiny renderer uses only Apple's frameworks and iconutil.
// Usage: swift scripts/generate-icon.swift [repository-root] [--preview output.png]
let arguments = Array(CommandLine.arguments.dropFirst())
let previewIndex = arguments.firstIndex(of: "--preview")
let previewPath = previewIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
let rootArgument = arguments.first { !$0.hasPrefix("--") && $0 != previewPath }
let root = URL(fileURLWithPath: rootArgument ?? FileManager.default.currentDirectoryPath)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha).cgColor
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
// Dawn sky: soft periwinkle above, rose in the middle, warm apricot at the horizon.
let sky = CGGradient(colorsSpace: colorSpace,
    colors: [color(0x8f9dfb), color(0xd9a4d6), color(0xffb8a1), color(0xffd59a)] as CFArray,
    locations: [0, 0.38, 0.72, 1])!
let glow = CGGradient(colorsSpace: colorSpace,
    colors: [color(0xfff1d6, alpha: 0.7), color(0xfff1d6, alpha: 0)] as CFArray, locations: [0, 1])!
let sun = CGGradient(colorsSpace: colorSpace,
    colors: [color(0xfffdf6), color(0xffdd94), color(0xffb766)] as CFArray, locations: [0, 0.55, 1])!
let extend: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
let center = CGPoint(x: 512, y: 540)

func draw(in context: CGContext) {
    // Apple's macOS icon grid: an 824-point rounded square with 100-point margins.
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 186, cornerHeight: 186, transform: nil)
    context.saveGState()
    context.addPath(tile)
    context.clip()
    context.drawLinearGradient(sky, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: extend)
    context.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 360, options: [])

    // The open ring keeps Zone's identity: a gentle opening toward the upper right.
    context.setLineCap(.round)
    context.setStrokeColor(color(0xffffff, alpha: 0.92))
    context.setLineWidth(40)
    context.addArc(center: center, radius: 228, startAngle: -.pi / 9, endAngle: -7 * .pi / 18, clockwise: false)
    context.strokePath()
    context.setStrokeColor(color(0xffffff, alpha: 0.24))
    context.setLineWidth(12)
    context.strokeEllipse(in: CGRect(x: center.x - 314, y: center.y - 314, width: 628, height: 628))

    // The still point becomes a warm, rising sun.
    context.saveGState()
    context.setShadow(offset: .zero, blur: 70, color: color(0xffe7b0, alpha: 0.9))
    context.setFillColor(color(0xffd48a))
    context.fillEllipse(in: CGRect(x: center.x - 118, y: center.y - 118, width: 236, height: 236))
    context.restoreGState()
    context.addEllipse(in: CGRect(x: center.x - 118, y: center.y - 118, width: 236, height: 236))
    context.clip()
    context.drawRadialGradient(sun, startCenter: CGPoint(x: center.x - 30, y: center.y - 40), startRadius: 0,
                               endCenter: center, endRadius: 118, options: extend)
    context.restoreGState()

    context.addPath(CGPath(roundedRect: CGRect(x: 100.5, y: 100.5, width: 823, height: 823),
                           cornerWidth: 185.5, cornerHeight: 185.5, transform: nil))
    context.setStrokeColor(color(0xffffff, alpha: 0.28))
    context.setLineWidth(1)
    context.strokePath()
}

func render(pixels: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1) // Match SVG's top-left origin.
    draw(in: context)
    return bitmap
}

if let previewPath {
    try render(pixels: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: previewPath))
    print("Wrote \(previewPath)")
    exit(0)
}

let iconset = root.appendingPathComponent("build/Zone.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
                       ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                       ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512),
                       ("icon_512x512@2x", 1024)] {
    try render(pixels: pixels).representation(using: .png, properties: [:])!
        .write(to: iconset.appendingPathComponent(name + ".png"))
}

let output = root.appendingPathComponent("Resources/Zone.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    throw NSError(domain: "ZoneIconGenerator", code: Int(iconutil.terminationStatus),
                  userInfo: [NSLocalizedDescriptionKey: "iconutil could not create \(output.path)"])
}
print("Generated 10 PNG representations and \(output.path)")
