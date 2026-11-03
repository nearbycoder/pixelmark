// Renders the installer window background: Resources/dmg/background.tiff (1x + 2x).
// Usage: swift Scripts/make-dmg-background.swift
// Icon centers must match icon_locations in Resources/dmg/settings.py: (160, 186) and (480, 186).
import AppKit

let size = NSSize(width: 640, height: 400)
let appCenter = NSPoint(x: 160, y: size.height - 186)
let applicationsCenter = NSPoint(x: 480, y: size.height - 186)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func glow(_ center: NSPoint, _ radius: CGFloat, _ c: NSColor) {
    NSGradient(colors: [c, c.withAlphaComponent(0)])!.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

func draw() {
    let bounds = NSRect(origin: .zero, size: size)
    NSGradient(colors: [color(0x1A1446), color(0x0E0C24)])!.draw(in: bounds, angle: -90)
    glow(appCenter, 170, color(0x5646EB, 0.55))
    glow(applicationsCenter, 150, color(0xFF3D7F, 0.28))

    color(0xFFFFFF, 0.05).setFill()
    for x in stride(from: CGFloat(16), to: size.width, by: 24) {
        for y in stride(from: CGFloat(16), to: size.height, by: 24) {
            NSBezierPath(ovalIn: NSRect(x: x - 0.9, y: y - 0.9, width: 1.8, height: 1.8)).fill()
        }
    }

    // A dimension line between the two icons, in the measuring style.
    let y = appCenter.y
    let from = appCenter.x + 92, to = applicationsCenter.x - 92
    color(0xFF3D7F).setStroke()
    let line = NSBezierPath()
    line.lineWidth = 2
    line.lineCapStyle = .round
    line.move(to: NSPoint(x: from, y: y)); line.line(to: NSPoint(x: to - 4, y: y))
    line.move(to: NSPoint(x: from, y: y - 8)); line.line(to: NSPoint(x: from, y: y + 8))
    line.move(to: NSPoint(x: to - 12, y: y + 8)); line.line(to: NSPoint(x: to - 3, y: y)); line.line(to: NSPoint(x: to - 12, y: y - 8))
    line.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let rounded = NSFont.systemFont(ofSize: 15, weight: .semibold).fontDescriptor.withDesign(.rounded)!
    NSAttributedString(string: "Drag PixelMark into Applications", attributes: [
        .font: NSFont(descriptor: rounded, size: 15)!,
        .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        .paragraphStyle: paragraph,
    ]).draw(in: NSRect(x: 0, y: 64, width: size.width, height: 24))
    NSAttributedString(string: "Then press ⇧⌘2 anywhere to measure", attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.5),
        .paragraphStyle: paragraph,
    ]).draw(in: NSRect(x: 0, y: 44, width: size.width, height: 20))
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let image = NSImage(size: size)
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
let output = URL(fileURLWithPath: "Resources/dmg/background.tiff")
try! FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try! image.tiffRepresentation(using: .lzw, factor: 0)!.write(to: output)
print("Wrote \(output.path)")
