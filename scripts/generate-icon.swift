import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let iconsetPath = (outputDir as NSString).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = size / 1024

    let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 225 * scale, yRadius: 225 * scale)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.18, alpha: 1),
        NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.08, alpha: 1)
    ])!
    gradient.draw(in: bgPath, angle: -90)

    let center = NSPoint(x: size / 2, y: size / 2)
    let radii: [(CGFloat, NSColor)] = [
        (390, NSColor(calibratedRed: 0.16, green: 0.65, blue: 0.60, alpha: 0.35)),
        (300, NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.66, alpha: 0.6)),
        (210, NSColor(calibratedRed: 0.22, green: 0.82, blue: 0.74, alpha: 0.9))
    ]
    for (r, color) in radii {
        let radius = r * scale
        color.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))
        ring.lineWidth = 26 * scale
        ring.stroke()
    }

    NSColor(calibratedRed: 0.85, green: 0.98, blue: 0.95, alpha: 1).setFill()
    let dot = 110 * scale
    NSBezierPath(ovalIn: NSRect(
        x: center.x - dot / 2, y: center.y - dot / 2,
        width: dot, height: dot
    )).fill()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, size: Int, name: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .calibratedRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: (iconsetPath as NSString).appendingPathComponent(name)))
}

let base = draw(size: 1024)
let sizes = [16, 32, 128, 256, 512]
for s in sizes {
    savePNG(base, size: s, name: "icon_\(s)x\(s).png")
    savePNG(base, size: s * 2, name: "icon_\(s)x\(s)@2x.png")
}

print("iconset created at \(iconsetPath)")
