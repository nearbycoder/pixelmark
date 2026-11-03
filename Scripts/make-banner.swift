// Renders the social card / README banner (1200 × 630) from the app icon and an overlay screenshot.
// Usage: swift Scripts/make-banner.swift <icon.png> <screenshot.png> <output.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let icon = NSImage(contentsOfFile: args[1]), let shot = NSImage(contentsOfFile: args[2]) else {
    print("usage: make-banner.swift <icon.png> <screenshot.png> <output.png>")
    exit(1)
}
let size = NSSize(width: 1200, height: 630)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func draw() {
    color(0x161618).setFill()
    NSRect(origin: .zero, size: size).fill()

    // Screenshot card on the right, cropped to the app window with the loupe.
    let card = NSRect(x: 590, y: 80, width: 560, height: 462)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.5)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    color(0x000000).setFill()
    NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12).addClip()
    // Source rect in the 1920 × 1080 screenshot (bottom-left origin).
    let source = NSRect(x: 870, y: 1080 - 790, width: 650, height: 536)
    let scale = shot.size.width / 1920
    shot.draw(in: card, from: NSRect(x: source.minX * scale, y: source.minY * scale, width: source.width * scale, height: source.height * scale), operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFFFFF, 0.12).setStroke()
    let rim = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
    rim.lineWidth = 1
    rim.stroke()

    icon.draw(in: NSRect(x: 60, y: 380, width: 128, height: 128), from: .zero, operation: .sourceOver, fraction: 1)

    NSAttributedString(string: "PixelMark", attributes: [
        .font: NSFont.systemFont(ofSize: 64, weight: .semibold), .foregroundColor: NSColor.white, .kern: -1.5,
    ]).draw(at: NSPoint(x: 68, y: 272))
    NSAttributedString(string: "A screen ruler for macOS.\nFree and open source.", attributes: [
        .font: NSFont.systemFont(ofSize: 28, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.6),
    ]).draw(in: NSRect(x: 70, y: 168, width: 500, height: 90))
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
draw()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
print("Wrote \(args[3])")
