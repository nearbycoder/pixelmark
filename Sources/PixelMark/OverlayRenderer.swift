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

/// A point-to-point measurement, drawn with ⌘-drag.
struct RulerLine: Equatable {
    var from: CGPoint
    var to: CGPoint
    var length: CGFloat { hypot(to.x - from.x, to.y - from.y) }
    /// Degrees from horizontal, 0–90, whichever way it slopes.
    var angle: Int {
        let degrees = abs(atan2(to.y - from.y, to.x - from.x) * 180 / .pi)
        return Int(min(degrees, 180 - degrees).rounded())
    }
}

struct Loupe {
    var image: CGImage
    /// The pixel under the cursor.
    var pixel: (x: Int, y: Int)
    /// How many pixels across it shows.
    var cells: Int
    var label: String
    var color: UInt32
    /// The color picked with K, to check contrast against.
    var reference: UInt32?
}

/// The space between a box's edges and the content inside it.
struct Padding: Equatable {
    var box: CGRect
    var content: CGRect
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
    var lines: [RulerLine] = []
    var dragLine: RulerLine?
    var padding: Padding?
    /// Layout grid spacing and where it starts.
    var grid: (size: CGFloat, origin: CGPoint)?
    var showsRulers = false
    var showsAspectRatio = false
    var showsPositions = false
    /// The pointer, marked on the rulers.
    var pointer: CGPoint?

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

    /// A box's size label, with its aspect ratio when that's turned on.
    func boxLabel(_ size: CGSize) -> String {
        guard showsAspectRatio,
              let ratio = Self.aspectRatio(width: Int((size.width * scale).rounded()), height: Int((size.height * scale).rounded()))
        else { return dimensions(size) }
        return "\(dimensions(size))  \(ratio)"
    }

    /// "16:9" when the sides reduce to small numbers, "≈16:9" when close to a common ratio, else "1.85:1".
    static func aspectRatio(width: Int, height: Int) -> String? {
        guard width > 0, height > 0 else { return nil }
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let divisor = gcd(width, height)
        let (a, b) = (width / divisor, height / divisor)
        if a <= 32 && b <= 32 { return "\(a):\(b)" }
        let ratio = Double(width) / Double(height)
        let common = [(1, 1), (5, 4), (4, 3), (3, 2), (16, 10), (16, 9), (2, 1), (21, 9)]
        for (x, y) in common + common.map({ ($1, $0) }) where abs(ratio - Double(x) / Double(y)) / ratio < 0.01 {
            return "≈\(x):\(y)"
        }
        return ratio >= 1 ? String(format: "%.2f:1", ratio) : String(format: "1:%.2f", 1 / ratio)
    }

    /// WCAG rating for a contrast ratio.
    static func contrastRating(_ ratio: Double) -> String {
        switch ratio {
        case 7...: "AAA"
        case 4.5...: "AA"
        case 3...: "AA Large"
        default: "Fail"
        }
    }
}

enum OverlayRenderer {
    static let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
    static let smallFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)

    /// Draws into the current NSGraphicsContext, which must be flipped (top-left origin, points).
    static func draw(_ scene: OverlayScene) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let accent = scene.accent

        if let grid = scene.grid { drawGrid(grid.size, origin: grid.origin, scene: scene, ctx: ctx) }
        drawAlignment(scene, ctx: ctx)
        drawGuides(scene, ctx: ctx)

        let tolerance = 0.5 / scene.scale
        for (index, box) in scene.boxes.enumerated() {
            let hovered = index == scene.hoveredBox
            let matches = scene.boxes.indices.contains { other in
                other != index && abs(scene.boxes[other].width - box.width) < tolerance && abs(scene.boxes[other].height - box.height) < tolerance
            }
            // While showing spacing or padding, the gaps are the story; the box's own size label would collide with them.
            let busy = hovered && (!scene.gaps.isEmpty || scene.padding != nil)
            drawBox(box, scene: scene, ctx: ctx, emphasized: hovered, showsLabel: !busy, matches: matches)
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
        if let padding = scene.padding {
            drawPadding(padding, scene: scene, ctx: ctx)
        }
        for line in scene.lines {
            drawLine(line, scene: scene, ctx: ctx)
        }
        if let line = scene.dragLine {
            drawLine(line, scene: scene, ctx: ctx)
        }

        if let live = scene.live {
            drawCrosshair(live, scene: scene, ctx: ctx, labelNear: live.point, isLive: true)
        }
        if scene.showsRulers {
            drawRulers(scene, ctx: ctx)
        }
        if let loupe = scene.loupe, let live = scene.live {
            let label = crosshairLabelRect(scene.dimensions(live.span.size), near: live.point, scene: scene)
            drawLoupe(loupe, at: live.point, avoiding: label, scene: scene, ctx: ctx)
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
        drawPill(text, at: crosshairLabelRect(text, near: point, scene: scene).origin, font: labelFont, scene: scene)
    }

    /// Below and to the right of the point, flipped to whichever side keeps it on screen.
    private static func crosshairLabelRect(_ text: String, near point: CGPoint, scene: OverlayScene) -> CGRect {
        let size = pillSize(text, font: labelFont)
        var origin = CGPoint(x: point.x + 14, y: point.y + 16)
        if origin.x + size.width > scene.size.width - 6 { origin.x = point.x - 14 - size.width }
        if origin.y + size.height > scene.size.height - 6 { origin.y = point.y - 16 - size.height }
        return CGRect(origin: origin, size: size)
    }

    private static func drawBox(_ rect: CGRect, scene: OverlayScene, ctx: CGContext, emphasized: Bool, showsLabel: Bool = true, matches: Bool = false) {
        let accent = scene.accent
        ctx.saveGState()
        ctx.setFillColor(accent.withAlphaComponent(emphasized ? 0.2 : 0.12).cgColor)
        ctx.fill(rect)
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
        guard showsLabel else { return }
        if scene.showsPositions {
            let text = "\(scene.format(rect.minX)), \(scene.format(rect.minY))"
            let size = pillSize(text, font: smallFont)
            var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - 5)
            if origin.y < 6 { origin.y = rect.minY + 5; origin.x += 5 }
            drawPill(text, at: origin, font: smallFont, scene: scene, muted: true)
        }

        // Boxes that are exactly the same size as another get an = mark.
        let text = (matches ? "= " : "") + scene.boxLabel(rect.size)
        let size = pillSize(text, font: labelFont)
        var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.maxY + 6)
        if origin.y + size.height > scene.size.height - 6 {
            origin.y = rect.minY - 6 - size.height
            if origin.y < 6 { origin.y = rect.maxY - size.height - 6 }
        }
        origin.x = min(max(origin.x, 6), scene.size.width - size.width - 6)
        drawPill(text, at: origin, font: labelFont, scene: scene)
    }

    private static func drawGap(_ gap: Gap, scene: OverlayScene, ctx: CGContext, labeled: Bool = true) {
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
        guard labeled else { return }

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
                ? CGPoint(x: scene.showsRulers ? 28 : 8, y: guide.position - size.height - 4)
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

    /// The loupe with its color label below and the contrast check above, kept clear of the crosshair's label and the screen edges.
    private static func drawLoupe(_ loupe: Loupe, at point: CGPoint, avoiding sizeLabel: CGRect, scene: OverlayScene, ctx: CGContext) {
        let diameter: CGFloat = 124
        let cells = loupe.cells
        let cell = diameter / CGFloat(cells)
        let spacing: CGFloat = 6
        let labelSize = pillSize(loupe.label, font: smallFont)
        let above = loupe.reference == nil ? 0 : labelSize.height + spacing
        let group = CGSize(width: max(diameter, labelSize.width), height: above + diameter + spacing + labelSize.height)

        // Above and to the right of the pointer first, then whichever corner fits.
        let reach: CGFloat = 22
        let left = point.x - reach - group.width, right = point.x + reach
        let top = point.y - reach - group.height
        let candidates = [
            CGPoint(x: right, y: top), CGPoint(x: left, y: top),
            CGPoint(x: right, y: point.y + reach), CGPoint(x: left, y: point.y + reach),
            CGPoint(x: right, y: sizeLabel.maxY + spacing), CGPoint(x: left, y: sizeLabel.maxY + spacing),
            CGPoint(x: right, y: sizeLabel.minY - spacing - group.height), CGPoint(x: left, y: sizeLabel.minY - spacing - group.height),
        ].map { CGRect(origin: $0, size: group) }
        let screen = CGRect(origin: .zero, size: scene.size).insetBy(dx: 8, dy: 8)
        let frame = candidates.first { screen.contains($0) && !$0.intersects(sizeLabel) } ?? candidates[0].offsetBy(
            dx: min(max(screen.minX - candidates[0].minX, 0), screen.maxX - candidates[0].maxX),
            dy: max(screen.minY - candidates[0].minY, 0)
        )
        let rect = CGRect(x: frame.midX - diameter / 2, y: frame.minY + above, width: diameter, height: diameter)

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
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(cells > 20 ? 0.06 : 0.1).cgColor)
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

        drawPill(loupe.label, at: CGPoint(x: rect.midX - labelSize.width / 2, y: rect.maxY + spacing), font: smallFont, scene: scene, muted: true)

        if let reference = loupe.reference {
            let ratio = PixelBuffer.contrastRatio(reference, loupe.color)
            drawContrast(ratio, colors: (reference, loupe.color), centeredAt: rect.midX, top: frame.minY, ctx: ctx)
        }
    }

    /// Two swatches and the WCAG ratio between them: "4.6:1  AA".
    private static func drawContrast(_ ratio: Double, colors: (UInt32, UInt32), centeredAt midX: CGFloat, top: CGFloat, ctx: CGContext) {
        let text = String(format: "%.1f:1  ", ratio) + OverlayScene.contrastRating(ratio)
        let textSize = (text as NSString).size(withAttributes: [.font: smallFont])
        let swatch: CGFloat = 11
        let height = ceil(textSize.height) + pillPadding.height * 2
        let width = pillPadding.width + swatch * 2 + 2 + 6 + ceil(textSize.width) + pillPadding.width
        let rect = CGRect(x: (midX - width / 2).rounded(), y: top.rounded(), width: width, height: height)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 5, color: NSColor.black.withAlphaComponent(0.3).cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil))
        ctx.setFillColor(NSColor(white: 0.08, alpha: 0.86).cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        for (index, color) in [colors.0, colors.1].enumerated() {
            let box = CGRect(x: rect.minX + pillPadding.width + CGFloat(index) * (swatch + 2), y: rect.midY - swatch / 2, width: swatch, height: swatch)
            let path = CGPath(roundedRect: box, cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(NSColor(color: color).cgColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(0.75)
            ctx.strokePath()
        }
        let passes = ratio >= 4.5
        (text as NSString).draw(
            at: CGPoint(x: rect.minX + pillPadding.width + swatch * 2 + 2 + 6, y: rect.minY + pillPadding.height),
            withAttributes: [.font: smallFont, .foregroundColor: passes ? NSColor.white : NSColor(srgbRed: 1, green: 0.62, blue: 0.55, alpha: 1)]
        )
    }

    private static func drawGrid(_ size: CGFloat, origin: CGPoint, scene: OverlayScene, ctx: CGContext) {
        guard size >= 2 else { return }
        ctx.saveGState()
        ctx.setLineWidth(1 / scene.scale)
        // Every eighth line is stronger, like a column grid.
        for strong in [false, true] {
            ctx.setStrokeColor(scene.accent.withAlphaComponent(strong ? 0.32 : 0.14).cgColor)
            let firstX = Int(((0 - origin.x) / size).rounded(.down)), lastX = Int(((scene.size.width - origin.x) / size).rounded(.up))
            for i in firstX...lastX where (i % 8 == 0) == strong {
                let x = crisp(origin.x + CGFloat(i) * size, scale: scene.scale)
                ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: scene.size.height))
            }
            let firstY = Int(((0 - origin.y) / size).rounded(.down)), lastY = Int(((scene.size.height - origin.y) / size).rounded(.up))
            for i in firstY...lastY where (i % 8 == 0) == strong {
                let y = crisp(origin.y + CGFloat(i) * size, scale: scene.scale)
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: scene.size.width, y: y))
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func drawLine(_ line: RulerLine, scene: OverlayScene, ctx: CGContext) {
        guard line.length > 0 else { return }
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 2, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.setStrokeColor(scene.accent.cgColor)
        ctx.setLineWidth(1.25)
        ctx.move(to: line.from); ctx.addLine(to: line.to)
        ctx.strokePath()
        ctx.setFillColor(scene.accent.cgColor)
        for end in [line.from, line.to] {
            ctx.fillEllipse(in: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6))
        }
        ctx.restoreGState()

        let text = "\(scene.format(line.length))  \(line.angle)°"
        let size = pillSize(text, font: labelFont)
        let mid = CGPoint(x: (line.from.x + line.to.x) / 2, y: (line.from.y + line.to.y) / 2)
        // Beside the line rather than on it: offset along its normal.
        let dx = (line.to.x - line.from.x) / line.length, dy = (line.to.y - line.from.y) / line.length
        var normal = CGPoint(x: dy, y: -dx)
        if normal.y > 0 { normal = CGPoint(x: -normal.x, y: -normal.y) }
        let reach = abs(normal.x) * size.width / 2 + abs(normal.y) * size.height / 2 + 6
        let center = CGPoint(x: mid.x + normal.x * reach, y: mid.y + normal.y * reach)
        drawPill(text, at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), font: labelFont, scene: scene)
    }

    private static func drawPadding(_ padding: Padding, scene: OverlayScene, ctx: CGContext) {
        let box = padding.box, content = padding.content
        ctx.saveGState()
        ctx.setStrokeColor(scene.accent.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        ctx.setFillColor(scene.accent.withAlphaComponent(0.16).cgColor)
        ctx.fill(content)
        ctx.setLineDash(phase: 0, lengths: [3, 2])
        ctx.stroke(content.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
        let left = Gap(from: CGPoint(x: box.minX, y: content.midY), to: CGPoint(x: content.minX, y: content.midY))
        let right = Gap(from: CGPoint(x: content.maxX, y: content.midY), to: CGPoint(x: box.maxX, y: content.midY))
        let top = Gap(from: CGPoint(x: content.midX, y: box.minY), to: CGPoint(x: content.midX, y: content.minY))
        let bottom = Gap(from: CGPoint(x: content.midX, y: content.maxY), to: CGPoint(x: content.midX, y: box.maxY))
        for gap in [left, right, top, bottom] {
            drawGap(gap, scene: scene, ctx: ctx, labeled: false)
        }
        // Labels sit outside the box, so they stay readable on small buttons.
        func label(_ gap: Gap, _ place: (CGSize) -> CGPoint) {
            let text = scene.format(gap.length)
            drawPill(text, at: place(pillSize(text, font: smallFont)), font: smallFont, scene: scene)
        }
        label(left) { CGPoint(x: box.minX - 6 - $0.width, y: content.midY - $0.height / 2) }
        label(right) { CGPoint(x: box.maxX + 6, y: content.midY - $0.height / 2) }
        label(top) { CGPoint(x: content.midX - $0.width / 2, y: box.minY - 6 - $0.height) }
        label(bottom) { CGPoint(x: content.midX - $0.width / 2, y: box.maxY + 6) }
    }

    static let rulerThickness: CGFloat = 20

    /// Rulers along the top and left edges, with the pointer and every box marked on them.
    private static func drawRulers(_ scene: OverlayScene, ctx: CGContext) {
        let t = rulerThickness
        let unitScale = scene.unit == .pixels ? scene.scale : 1
        let band = NSColor(white: 0.09, alpha: 0.86)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.65)]

        ctx.saveGState()
        ctx.setFillColor(band.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: scene.size.width, height: t))
        ctx.fill(CGRect(x: 0, y: t, width: t, height: scene.size.height - t))

        // Boxes, projected onto each ruler.
        ctx.setFillColor(scene.accent.withAlphaComponent(0.4).cgColor)
        for box in scene.boxes {
            ctx.fill(CGRect(x: max(box.minX, t), y: 0, width: box.maxX - max(box.minX, t), height: t))
            ctx.fill(CGRect(x: 0, y: max(box.minY, t), width: t, height: box.maxY - max(box.minY, t)))
        }

        // Ticks every 10 units, longer every 50, labeled every 100.
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(1 / scene.scale)
        for axis in 0..<2 {
            let length = axis == 0 ? scene.size.width : scene.size.height
            var value = 0
            while CGFloat(value) / unitScale <= length {
                let p = crisp(CGFloat(value) / unitScale, scale: scene.scale)
                let tick: CGFloat = value % 100 == 0 ? t : value % 50 == 0 ? 8 : 4
                if p >= t {
                    if axis == 0 {
                        ctx.move(to: CGPoint(x: p, y: t - tick)); ctx.addLine(to: CGPoint(x: p, y: t))
                    } else {
                        ctx.move(to: CGPoint(x: t - tick, y: p)); ctx.addLine(to: CGPoint(x: t, y: p))
                    }
                }
                value += 10
            }
        }
        ctx.strokePath()
        ctx.restoreGState()

        for axis in 0..<2 {
            let length = axis == 0 ? scene.size.width : scene.size.height
            var value = 100
            while CGFloat(value) / unitScale < length - 20 {
                let p = CGFloat(value) / unitScale
                let text = "\(value)" as NSString
                if axis == 0 {
                    text.draw(at: CGPoint(x: p + 3, y: 2), withAttributes: labelAttributes)
                } else {
                    ctx.saveGState()
                    ctx.translateBy(x: 2, y: p - 3)
                    ctx.rotate(by: -.pi / 2)
                    text.draw(at: .zero, withAttributes: labelAttributes)
                    ctx.restoreGState()
                }
                value += 100
            }
        }

        // The pointer's position on each ruler.
        if let pointer = scene.pointer {
            ctx.saveGState()
            ctx.setStrokeColor(scene.accent.cgColor)
            ctx.setLineWidth(1)
            let x = crisp(pointer.x, scale: scene.scale), y = crisp(pointer.y, scale: scene.scale)
            ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: t))
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: t, y: y))
            ctx.strokePath()
            ctx.restoreGState()

            let xText = scene.format(pointer.x)
            let xSize = pillSize(xText, font: smallFont)
            drawPill(xText, at: CGPoint(x: min(max(x - xSize.width / 2, t + 2), scene.size.width - xSize.width - 2), y: t + 3), font: smallFont, scene: scene)
            let yText = scene.format(pointer.y)
            let ySize = pillSize(yText, font: smallFont)
            drawPill(yText, at: CGPoint(x: t + 3, y: min(max(y - ySize.height / 2, t + 2), scene.size.height - ySize.height - 2)), font: smallFont, scene: scene)
        }

        // Corner square.
        ctx.setFillColor(band.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: t, height: t))
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
    /// From packed 0x__RRGGBB.
    convenience init(color: UInt32) {
        self.init(srgbRed: CGFloat((color >> 16) & 0xFF) / 255, green: CGFloat((color >> 8) & 0xFF) / 255, blue: CGFloat(color & 0xFF) / 255, alpha: 1)
    }

    /// Bright colors (lime, cyan) read better with dark text.
    var prefersDarkText: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return false }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.55
    }
}
