import AppKit
import Foundation

// Original artwork matching Resources/Brand/zone-icon.svg, in its 1024-unit
// coordinate space. This tiny renderer uses only Apple's frameworks and iconutil.
// Usage: swift scripts/generate-icon.swift [repository-root]
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/Zone.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha).cgColor
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let backgroundGradient = CGGradient(colorsSpace: colorSpace,
    colors: [color(0x294940), color(0x162f2a)] as CFArray, locations: [0, 1])!
let ringGradient = CGGradient(colorsSpace: colorSpace,
    colors: [color(0xedf7ef), color(0xc5e3d5)] as CFArray, locations: [0, 1])!
let extendGradient: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]

for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32),
                       ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                       ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512),
                       ("icon_512x512@2x", 1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    context.translateBy(x: 0, y: 1024)
    context.scaleBy(x: 1, y: -1) // Match SVG's top-left origin.

    context.saveGState()
    context.addPath(CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
                           cornerWidth: 200, cornerHeight: 200, transform: nil))
    context.clip()
    context.drawLinearGradient(backgroundGradient, start: CGPoint(x: 512, y: 64),
                               end: CGPoint(x: 512, y: 960), options: extendGradient)
    context.restoreGState()

    context.addPath(CGPath(roundedRect: CGRect(x: 64.5, y: 64.5, width: 895, height: 895),
                           cornerWidth: 199.5, cornerHeight: 199.5, transform: nil))
    context.setStrokeColor(color(0xffffff, alpha: 0.13))
    context.setLineWidth(1)
    context.strokePath()

    context.saveGState()
    context.setLineWidth(64)
    context.setLineCap(.round)
    context.addArc(center: CGPoint(x: 512, y: 512), radius: 251,
                   startAngle: -.pi / 9, endAngle: -7 * .pi / 18, clockwise: false)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(ringGradient, start: CGPoint(x: 512, y: 224),
                               end: CGPoint(x: 512, y: 800), options: extendGradient)
    context.restoreGState()

    context.setFillColor(color(0x9bddc0))
    context.fillEllipse(in: CGRect(x: 464, y: 464, width: 96, height: 96))
    try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name + ".png"))
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
