import AppKit

/// A crosshair measurement: the point it was taken at and the flat-color region around it, in points.
struct Crosshair: Equatable {
    var point: CGPoint
    /// Horizontal extent is the measured width; vertical extent is the measured height.
    var span: CGRect
}

struct Guide: Equatable {
    enum Axis { case horizontal, vertical }
    var axis: Axis
    var position: CGFloat
}

/// An axis-aligned distance line, drawn with end caps and its length.
struct Gap: Equatable {
    var from: CGPoint
    var to: CGPoint
    var length: CGFloat { abs(to.x - from.x) + abs(to.y - from.y) }
    var isHorizontal: Bool { from.y == to.y }
}

struct Loupe {
    var image: CGImage
    /// The pixel under the cursor.
    var pixel: (x: Int, y: Int)
    var hex: String
}

/// Everything one screen's overlay shows, in points with a top-left origin.
struct OverlayScene {
    var size: CGSize
    var scale: CGFloat
    var accent: NSColor
    var unit: MeasureUnit

    var guides: [Guide] = []
    var boxes: [CGRect] = []
    var hoveredBox: Int?
    var pins: [Crosshair] = []
    var live: Crosshair?
    var dragRaw: CGRect?
    var dragSnapped: CGRect?
    var gaps: [Gap] = []
    var loupe: Loupe?

    /// A length in the chosen unit, e.g. "320", "160.5".
    func format(_ length: CGFloat) -> String {
        Self.format(length, scale: scale, unit: unit)
    }

    static func format(_ length: CGFloat, scale: CGFloat, unit: MeasureUnit) -> String {
        switch unit {
        case .pixels:
            return "\(Int((length * scale).rounded()))"
        case .points:
            let rounded = (length * 2).rounded() / 2
            return rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
        }
    }

    func dimensions(_ size: CGSize) -> String {
        "\(format(size.width)) × \(format(size.height))"
    }
}

enum OverlayRenderer {
    static let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
    static let smallFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)

    /// Draws into the current NSGraphicsContext, which must be flipped (top-left origin, points).
    static func draw(_ scene: OverlayScene) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let accent = scene.accent

        drawAlignment(scene, ctx: ctx)
        drawGuides(scene, ctx: ctx)

        for (index, box) in scene.boxes.enumerated() {
            let hovered = index == scene.hoveredBox
            // While showing spacing, the gaps are the story; the box's own size label would collide with them.
            drawBox(box, scene: scene, ctx: ctx, emphasized: hovered, showsLabel: !(hovered && !scene.gaps.isEmpty))
        }
        for pin in scene.pins {
            drawCrosshair(pin, scene: scene, ctx: ctx, labelNear: pin.point)
        }

        if let raw = scene.dragRaw {
            ctx.saveGState()
            ctx.setStrokeColor(accent.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(raw.insetBy(dx: 0.5, dy: 0.5))
            ctx.restoreGState()
        }
        if let snapped = scene.dragSnapped {
            drawBox(snapped, scene: scene, ctx: ctx, emphasized: true)
        }

        for gap in scene.gaps {
            drawGap(gap, scene: scene, ctx: ctx)
        }

        if let live = scene.live {
            drawCrosshair(live, scene: scene, ctx: ctx, labelNear: live.point, isLive: true)
        }
        if let loupe = scene.loupe, let point = scene.live?.point {
            drawLoupe(loupe, at: point, scene: scene, ctx: ctx)
        }
    }

    // MARK: - Pieces

    /// Center of the device pixel line closest to `value`, so 1 pt lines land on whole pixels.
    private static func crisp(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        scale >= 2 ? (value * scale).rounded() / scale : (value * scale).rounded(.down) / scale + 0.5
    }

    private static func drawCrosshair(_ mark: Crosshair, scene: OverlayScene, ctx: CGContext, labelNear point: CGPoint, isLive: Bool = false) {
        let span = mark.span
        let scale = scene.scale
        let y = crisp(point.y, scale: scale)
        let x = crisp(point.x, scale: scale)
        let cap: CGFloat = 4.5

        ctx.saveGState()
        ctx.setStrokeColor(scene.accent.cgColor)
        ctx.setLineWidth(1)
        ctx.setShadow(offset: .zero, blur: 2, color: NSColor.black.withAlphaComponent(0.35).cgColor)

        // Horizontal run with end caps.
        ctx.move(to: CGPoint(x: span.minX, y: y)); ctx.addLine(to: CGPoint(x: span.maxX, y: y))
        ctx.move(to: CGPoint(x: span.minX + 0.5, y: y - cap)); ctx.addLine(to: CGPoint(x: span.minX + 0.5, y: y + cap))
        ctx.move(to: CGPoint(x: span.maxX - 0.5, y: y - cap)); ctx.addLine(to: CGPoint(x: span.maxX - 0.5, y: y + cap))
        // Vertical run with end caps.
        ctx.move(to: CGPoint(x: x, y: span.minY)); ctx.addLine(to: CGPoint(x: x, y: span.maxY))
        ctx.move(to: CGPoint(x: x - cap, y: span.minY + 0.5)); ctx.addLine(to: CGPoint(x: x + cap, y: span.minY + 0.5))
        ctx.move(to: CGPoint(x: x - cap, y: span.maxY - 0.5)); ctx.addLine(to: CGPoint(x: x + cap, y: span.maxY - 0.5))
        ctx.strokePath()
        ctx.restoreGState()

        if !isLive {
            // A dot marks where a pinned measurement was taken.
            ctx.setFillColor(scene.accent.cgColor)
            ctx.fillEllipse(in: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5))
        }

        let text = scene.dimensions(span.size)
        var origin = CGPoint(x: point.x + 14, y: point.y + 16)
        let size = pillSize(text, font: labelFont)
        if origin.x + size.width > scene.size.width - 6 { origin.x = point.x - 14 - size.width }
        if origin.y + size.height > scene.size.height - 6 { origin.y = point.y - 16 - size.height }
        drawPill(text, at: origin, font: labelFont, scene: scene)
    }

    private static func drawBox(_ rect: CGRect, scene: OverlayScene, ctx: CGContext, emphasized: Bool, showsLabel: Bool = true) {
        let accent = scene.accent
        ctx.saveGState()
        ctx.setFillColor(accent.withAlphaComponent(emphasized ? 0.2 : 0.12).cgColor)
        ctx.fill(rect)
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
        guard showsLabel else { return }

        let text = scene.dimensions(rect.size)
        let size = pillSize(text, font: labelFont)
        var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.maxY + 6)
        if origin.y + size.height > scene.size.height - 6 {
            origin.y = rect.minY - 6 - size.height
            if origin.y < 6 { origin.y = rect.maxY - size.height - 6 }
        }
        origin.x = min(max(origin.x, 6), scene.size.width - size.width - 6)
        drawPill(text, at: origin, font: labelFont, scene: scene)
    }

    private static func drawGap(_ gap: Gap, scene: OverlayScene, ctx: CGContext) {
        guard gap.length >= 1 / scene.scale else { return }
        let cap: CGFloat = 3.5
        ctx.saveGState()
        ctx.setStrokeColor(scene.accent.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [3, 2])
        ctx.move(to: gap.from); ctx.addLine(to: gap.to)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
        for end in [gap.from, gap.to] {
            if gap.isHorizontal {
                ctx.move(to: CGPoint(x: end.x, y: end.y - cap)); ctx.addLine(to: CGPoint(x: end.x, y: end.y + cap))
            } else {
                ctx.move(to: CGPoint(x: end.x - cap, y: end.y)); ctx.addLine(to: CGPoint(x: end.x + cap, y: end.y))
            }
        }
        ctx.strokePath()
        ctx.restoreGState()

        let text = scene.format(gap.length)
        let size = pillSize(text, font: smallFont)
        let mid = CGPoint(x: (gap.from.x + gap.to.x) / 2, y: (gap.from.y + gap.to.y) / 2)
        let origin = gap.isHorizontal
            ? CGPoint(x: mid.x - size.width / 2, y: mid.y - size.height - 5)
            : CGPoint(x: mid.x + 6, y: mid.y - size.height / 2)
        drawPill(text, at: origin, font: smallFont, scene: scene)
    }

    private static func drawGuides(_ scene: OverlayScene, ctx: CGContext) {
        guard !scene.guides.isEmpty else { return }
        let color = scene.accent.withAlphaComponent(0.85)
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        for guide in scene.guides {
            let p = crisp(guide.position, scale: scene.scale)
            if guide.axis == .horizontal {
                ctx.move(to: CGPoint(x: 0, y: p)); ctx.addLine(to: CGPoint(x: scene.size.width, y: p))
            } else {
                ctx.move(to: CGPoint(x: p, y: 0)); ctx.addLine(to: CGPoint(x: p, y: scene.size.height))
            }
        }
        ctx.strokePath()
        ctx.restoreGState()

        // Position labels at the leading edge, and the distance between neighboring guides.
        for guide in scene.guides {
            let text = scene.format(guide.position)
            let size = pillSize(text, font: smallFont)
            let origin = guide.axis == .horizontal
                ? CGPoint(x: 8, y: guide.position - size.height - 4)
                : CGPoint(x: guide.position + 5, y: 34)
            drawPill(text, at: origin, font: smallFont, scene: scene, muted: true)
        }
        for axis in [Guide.Axis.horizontal, .vertical] {
            let positions = scene.guides.filter { $0.axis == axis }.map(\.position).sorted()
            for (a, b) in zip(positions, positions.dropFirst()) where b - a > 0 {
                let gap = axis == .horizontal
                    ? Gap(from: CGPoint(x: 64, y: a), to: CGPoint(x: 64, y: b))
                    : Gap(from: CGPoint(x: a, y: 64), to: CGPoint(x: b, y: 64))
                drawGap(gap, scene: scene, ctx: ctx)
            }
        }
    }

    /// Dashed lines through box edges and centers that line up exactly.
    private static func drawAlignment(_ scene: OverlayScene, ctx: CGContext) {
        let boxes = scene.boxes
        guard boxes.count > 1 else { return }
        let tolerance = 0.5 / scene.scale
        ctx.saveGState()
        ctx.setStrokeColor(scene.accent.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [2, 3])
        for i in boxes.indices {
            for j in boxes.indices where j > i {
                let a = boxes[i], b = boxes[j]
                for (va, vb) in [(a.minX, b.minX), (a.midX, b.midX), (a.maxX, b.maxX)] where abs(va - vb) < tolerance {
                    let x = crisp(va, scale: scene.scale)
                    ctx.move(to: CGPoint(x: x, y: min(a.minY, b.minY))); ctx.addLine(to: CGPoint(x: x, y: max(a.maxY, b.maxY)))
                }
                for (va, vb) in [(a.minY, b.minY), (a.midY, b.midY), (a.maxY, b.maxY)] where abs(va - vb) < tolerance {
                    let y = crisp(va, scale: scene.scale)
                    ctx.move(to: CGPoint(x: min(a.minX, b.minX), y: y)); ctx.addLine(to: CGPoint(x: max(a.maxX, b.maxX), y: y))
                }
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawLoupe(_ loupe: Loupe, at point: CGPoint, scene: OverlayScene, ctx: CGContext) {
        let diameter: CGFloat = 124
        let cells = 15
        let cell = diameter / CGFloat(cells)

        var rect = CGRect(x: point.x + 22, y: point.y - 22 - diameter, width: diameter, height: diameter)
        if rect.maxX > scene.size.width - 8 { rect.origin.x = point.x - 22 - diameter }
        if rect.minY < 8 { rect.origin.y = point.y + 48 }

        let half = cells / 2
        let source = CGRect(x: loupe.pixel.x - half, y: loupe.pixel.y - half, width: cells, height: cells)
        let bounds = CGRect(x: 0, y: 0, width: loupe.image.width, height: loupe.image.height)
        let visible = source.intersection(bounds)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillEllipse(in: rect)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()
        if !visible.isNull, let crop = loupe.image.cropping(to: visible) {
            let dest = CGRect(
                x: rect.minX + (visible.minX - source.minX) * cell,
                y: rect.minY + (visible.minY - source.minY) * cell,
                width: visible.width * cell,
                height: visible.height * cell
            )
            ctx.interpolationQuality = .none
            // The context is flipped; flip the image back so it draws upright.
            ctx.saveGState()
            ctx.translateBy(x: dest.minX, y: dest.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(crop, in: CGRect(origin: .zero, size: dest.size))
            ctx.restoreGState()
        }
        // Pixel grid.
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.1).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1..<cells {
            let offset = CGFloat(i) * cell
            ctx.move(to: CGPoint(x: rect.minX + offset, y: rect.minY)); ctx.addLine(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            ctx.move(to: CGPoint(x: rect.minX, y: rect.minY + offset)); ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + offset))
        }
        ctx.strokePath()
        ctx.restoreGState()

        // Center pixel.
        let center = CGRect(x: rect.minX + CGFloat(half) * cell, y: rect.minY + CGFloat(half) * cell, width: cell, height: cell)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(center.insetBy(dx: -0.75, dy: -0.75))
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(0.75)
        ctx.stroke(center.insetBy(dx: -1.9, dy: -1.9))

        // Rim.
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))

        let text = loupe.hex
        let size = pillSize(text, font: smallFont)
        drawPill(text, at: CGPoint(x: rect.midX - size.width / 2, y: rect.maxY + 6), font: smallFont, scene: scene, muted: true)
    }

    // MARK: - Labels

    private static let pillPadding = CGSize(width: 7, height: 3.5)

    static func pillSize(_ text: String, font: NSFont) -> CGSize {
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(size.width) + pillPadding.width * 2, height: ceil(size.height) + pillPadding.height * 2)
    }

    private static func drawPill(_ text: String, at origin: CGPoint, font: NSFont, scene: OverlayScene, muted: Bool = false) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size = pillSize(text, font: font)
        let rect = CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
        let fill = muted ? NSColor(white: 0.08, alpha: 0.86) : scene.accent
        let path = CGPath(roundedRect: rect, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 5, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(fill.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        let textColor: NSColor = muted || !fill.prefersDarkText ? .white : NSColor(white: 0.08, alpha: 1)
        (text as NSString).draw(
            at: CGPoint(x: rect.minX + pillPadding.width, y: rect.minY + pillPadding.height),
            withAttributes: [.font: font, .foregroundColor: textColor]
        )
    }
}

extension NSColor {
    /// Bright colors (lime, cyan) read better with dark text.
    var prefersDarkText: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return false }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.55
    }
}
