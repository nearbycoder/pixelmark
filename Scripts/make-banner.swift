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

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: size) ?? base
}

func glow(_ center: NSPoint, _ radius: CGFloat, _ c: NSColor) {
    NSGradient(colors: [c, c.withAlphaComponent(0)])!.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

func draw() {
    let bounds = NSRect(origin: .zero, size: size)
    NSGradient(colors: [color(0x1A1446), color(0x0B0A1F)])!.draw(in: bounds, angle: -60)
    glow(NSPoint(x: 160, y: 560), 520, color(0xFF3D7F, 0.30))
    glow(NSPoint(x: 1080, y: 60), 600, color(0x5646EB, 0.45))

    color(0xFFFFFF, 0.05).setFill()
    for x in stride(from: CGFloat(18), to: size.width, by: 28) {
        for y in stride(from: CGFloat(18), to: size.height, by: 28) {
            NSBezierPath(ovalIn: NSRect(x: x - 1, y: y - 1, width: 2, height: 2)).fill()
        }
    }

    // Screenshot card on the right, cropped to the app window with the loupe.
    let card = NSRect(x: 590, y: 80, width: 560, height: 462)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.5)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    color(0x000000).setFill()
    NSBezierPath(roundedRect: card, xRadius: 22, yRadius: 22).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: card, xRadius: 22, yRadius: 22).addClip()
    // Source rect in the 1920 × 1080 screenshot (bottom-left origin).
    let source = NSRect(x: 870, y: 1080 - 790, width: 650, height: 536)
    let scale = shot.size.width / 1920
    shot.draw(in: card, from: NSRect(x: source.minX * scale, y: source.minY * scale, width: source.width * scale, height: source.height * scale), operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFFFFF, 0.18).setStroke()
    let rim = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 22, yRadius: 22)
    rim.lineWidth = 1
    rim.stroke()

    icon.draw(in: NSRect(x: 64, y: 372, width: 150, height: 150), from: .zero, operation: .sourceOver, fraction: 1)

    NSAttributedString(string: "PixelMark", attributes: [
        .font: rounded(78, .bold), .foregroundColor: NSColor.white, .kern: -1.5,
    ]).draw(at: NSPoint(x: 70, y: 262))
    NSAttributedString(string: "Measure anything\non your screen.", attributes: [
        .font: rounded(32, .semibold), .foregroundColor: NSColor.white.withAlphaComponent(0.72),
    ]).draw(in: NSRect(x: 72, y: 150, width: 500, height: 100))

    var x: CGFloat = 72
    for chip in ["⇧⌘2", "Free & open source", "macOS"] {
        let text = NSAttributedString(string: chip, attributes: [.font: rounded(19, .semibold), .foregroundColor: NSColor.white])
        let w = text.size().width + 30
        let r = NSRect(x: x, y: 82, width: w, height: 40)
        color(0xFFFFFF, 0.1).setFill()
        NSBezierPath(roundedRect: r, xRadius: 20, yRadius: 20).fill()
        color(0xFFFFFF, 0.2).setStroke()
        NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 20, yRadius: 20).stroke()
        text.draw(at: NSPoint(x: r.minX + 15, y: r.minY + 9))
        x += w + 10
    }
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
draw()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
print("Wrote \(args[3])")
