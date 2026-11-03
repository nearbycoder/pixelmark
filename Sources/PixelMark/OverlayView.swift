import AppKit
import Carbon.HIToolbox

/// One screen's measuring surface: shows the frozen screenshot and handles measuring input on it.
@MainActor
final class OverlayView: NSView {
    let snapshot: ScreenSnapshot
    weak var session: MeasureSession?

    private(set) var cursor: CGPoint?
    private var boxes: [CGRect] = []
    private var pins: [Crosshair] = []
    private var guides: [Guide] = []
    private var lines: [RulerLine] = []
    private var history: [Mark] = []
    /// What ⌫, ⌘Z and X took away, for ⇧⌘Z.
    private var removed: [Removed] = []
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var isDragging = false
    /// ⌘-drag draws a point-to-point line instead of a box.
    private var drawsLine = false
    private var showSpacing = false
    private var showPadding = false
    private var freeDrag = false
    /// Where the layout grid starts, while it's shown.
    private var gridOrigin: CGPoint?

    private enum Mark { case box, pin, guide, line }
    private enum Removed {
        case box(CGRect), pin(Crosshair), guide(Guide), line(RulerLine)
        case everything(boxes: [CGRect], pins: [Crosshair], guides: [Guide], lines: [RulerLine], history: [Mark])
    }

    #if DEBUG
    /// The demo video draws its own pointer, since recordings leave the real one out.
    var showsDemoCursor = false
    /// Shows just the desktop and pointer, as before the shortcut is pressed.
    var demoHidesMarks = false { didSet { needsDisplay = true } }
    fileprivate var demoPress: (point: CGPoint, time: Date)?
    #endif

    private var settings: AppSettings { .shared }
    private var scale: CGFloat { snapshot.scale }
    private var buffer: PixelBuffer { snapshot.buffer }

    init(snapshot: ScreenSnapshot) {
        self.snapshot = snapshot
        super.init(frame: NSRect(origin: .zero, size: snapshot.screen.frame.size))
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect, .cursorUpdate],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    // MARK: - Geometry

    /// The device pixel under a point.
    private func pixel(at point: CGPoint) -> (x: Int, y: Int) {
        (
            min(max(Int((point.x * scale).rounded(.down)), 0), buffer.width - 1),
            min(max(Int((point.y * scale).rounded(.down)), 0), buffer.height - 1)
        )
    }

    private func pixelCenter(_ p: (x: Int, y: Int)) -> CGPoint {
        CGPoint(x: (CGFloat(p.x) + 0.5) / scale, y: (CGFloat(p.y) + 0.5) / scale)
    }

    private func crosshair(at point: CGPoint) -> Crosshair? {
        let p = pixel(at: point)
        guard let span = buffer.span(x: p.x, y: p.y, tolerance: settings.tolerance) else { return nil }
        let rect = CGRect(
            x: CGFloat(span.left) / scale,
            y: CGFloat(span.top) / scale,
            width: CGFloat(span.width) / scale,
            height: CGFloat(span.height) / scale
        )
        return Crosshair(point: pixelCenter(p), span: rect)
    }

    private var dragRect: CGRect? {
        guard isDragging, !drawsLine, let start = dragStart, let current = dragCurrent else { return nil }
        // Whole pixels, so the box matches what's on screen exactly.
        let a = pixel(at: start), b = pixel(at: current)
        let minX = min(a.x, b.x), minY = min(a.y, b.y)
        let maxX = max(a.x, b.x) + 1, maxY = max(a.y, b.y) + 1
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale, width: CGFloat(maxX - minX) / scale, height: CGFloat(maxY - minY) / scale)
    }

    /// A ⌘-drag line between pixel centers; ⇧ keeps it to 45° steps.
    private var dragLine: RulerLine? {
        guard isDragging, drawsLine, let start = dragStart, let current = dragCurrent else { return nil }
        let from = pixelCenter(pixel(at: start))
        var to = pixelCenter(pixel(at: current))
        if freeDrag {
            let dx = to.x - from.x, dy = to.y - from.y
            let step = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            to = pixelCenter(pixel(at: CGPoint(x: from.x + cos(step) * length, y: from.y + sin(step) * length)))
        }
        return RulerLine(from: from, to: to)
    }

    /// The space between a box's edges and what's inside it, like a button's label.
    private func padding(in box: CGRect) -> Padding? {
        let pixels = PixelRect(
            minX: Int((box.minX * scale).rounded()), minY: Int((box.minY * scale).rounded()),
            maxX: Int((box.maxX * scale).rounded()), maxY: Int((box.maxY * scale).rounded())
        )
        let inset = max(2, Int((1.5 * scale).rounded()))
        guard let content = buffer.innerContentBounds(in: pixels, inset: inset, tolerance: settings.tolerance) else { return nil }
        return Padding(box: box, content: CGRect(
            x: CGFloat(content.minX) / scale, y: CGFloat(content.minY) / scale,
            width: CGFloat(content.width) / scale, height: CGFloat(content.height) / scale
        ))
    }

    /// The drag rectangle, shrunk to the content inside it unless snapping is off (⇧ flips it).
    private func snapped(_ rect: CGRect) -> CGRect {
        guard settings.snapToContent != freeDrag else { return rect }
        let pixels = PixelRect(
            minX: Int((rect.minX * scale).rounded()), minY: Int((rect.minY * scale).rounded()),
            maxX: Int((rect.maxX * scale).rounded()), maxY: Int((rect.maxY * scale).rounded())
        )
        guard let bounds = buffer.contentBounds(in: pixels, tolerance: settings.tolerance) else { return rect }
        return CGRect(
            x: CGFloat(bounds.minX) / scale, y: CGFloat(bounds.minY) / scale,
            width: CGFloat(bounds.width) / scale, height: CGFloat(bounds.height) / scale
        )
    }

    private var hoveredBoxIndex: Int? {
        guard let cursor, !isDragging else { return nil }
        // Smallest box under the cursor wins, so nested boxes can be picked.
        return boxes.indices
            .filter { boxes[$0].insetBy(dx: -1, dy: -1).contains(cursor) }
            .min { boxes[$0].width * boxes[$0].height < boxes[$1].width * boxes[$1].height }
    }

    /// Distances from a box to its neighbors: other boxes it faces, or else the next edge on screen.
    private func spacing(around box: CGRect, excluding index: Int) -> [Gap] {
        var gaps: [Gap] = []
        let others = boxes.enumerated().filter { $0.offset != index }.map(\.element)

        func overlapMid(_ a0: CGFloat, _ a1: CGFloat, _ b0: CGFloat, _ b1: CGFloat) -> CGFloat? {
            let lo = max(a0, b0), hi = min(a1, b1)
            return hi > lo ? (lo + hi) / 2 : nil
        }

        // Left / right.
        for direction in [-1, 1] {
            let facing = others.compactMap { other -> (CGFloat, CGFloat)? in
                guard let y = overlapMid(box.minY, box.maxY, other.minY, other.maxY) else { return nil }
                if direction < 0, other.maxX <= box.minX { return (box.minX - other.maxX, y) }
                if direction > 0, other.minX >= box.maxX { return (other.minX - box.maxX, y) }
                return nil
            }.min { $0.0 < $1.0 }
            let edge = direction < 0 ? box.minX : box.maxX
            if let (distance, y) = facing {
                gaps.append(Gap(from: CGPoint(x: edge, y: y), to: CGPoint(x: edge + CGFloat(direction) * distance, y: y)))
            } else {
                let p = pixel(at: CGPoint(x: edge + (direction < 0 ? -0.5 / scale : 0.5 / scale), y: box.midY))
                guard (direction < 0 ? box.minX > 0 : box.maxX < bounds.width) else { continue }
                let run = buffer.run(fromX: p.x, y: p.y, dx: direction, dy: 0, tolerance: settings.tolerance)
                let y = pixelCenter(p).y
                gaps.append(Gap(from: CGPoint(x: edge, y: y), to: CGPoint(x: edge + CGFloat(direction * run) / scale, y: y)))
            }
        }
        // Up / down.
        for direction in [-1, 1] {
            let facing = others.compactMap { other -> (CGFloat, CGFloat)? in
                guard let x = overlapMid(box.minX, box.maxX, other.minX, other.maxX) else { return nil }
                if direction < 0, other.maxY <= box.minY { return (box.minY - other.maxY, x) }
                if direction > 0, other.minY >= box.maxY { return (other.minY - box.maxY, x) }
                return nil
            }.min { $0.0 < $1.0 }
            let edge = direction < 0 ? box.minY : box.maxY
            if let (distance, x) = facing {
                gaps.append(Gap(from: CGPoint(x: x, y: edge), to: CGPoint(x: x, y: edge + CGFloat(direction) * distance)))
            } else {
                guard (direction < 0 ? box.minY > 0 : box.maxY < bounds.height) else { continue }
                let p = pixel(at: CGPoint(x: box.midX, y: edge + (direction < 0 ? -0.5 / scale : 0.5 / scale)))
                let run = buffer.run(fromX: p.x, y: p.y, dx: 0, dy: direction, tolerance: settings.tolerance)
                let x = pixelCenter(p).x
                gaps.append(Gap(from: CGPoint(x: x, y: edge), to: CGPoint(x: x, y: edge + CGFloat(direction * run) / scale)))
            }
        }
        return gaps
    }

    // MARK: - Scene

    /// - Parameter forExport: leaves out the loupe, which only makes sense while pointing.
    func scene(forExport: Bool = false) -> OverlayScene {
        var scene = OverlayScene(size: bounds.size, scale: scale, accent: settings.markColor.nsColor, unit: settings.unit)
        scene.guides = guides
        scene.boxes = boxes
        scene.pins = pins
        scene.lines = lines
        scene.grid = gridOrigin.map { (CGFloat(settings.gridSize), $0) }
        scene.showsRulers = settings.showRulers
        scene.showsAspectRatio = settings.showAspectRatio
        scene.showsPositions = settings.showPositions
        let hovered = hoveredBoxIndex
        scene.hoveredBox = hovered

        if let line = dragLine {
            scene.dragLine = line
            scene.pointer = cursor
        } else if let rect = dragRect {
            scene.dragRaw = rect
            scene.dragSnapped = snapped(rect)
            scene.pointer = cursor
        } else if let cursor, session?.isPointerOverHUD != true {
            scene.pointer = forExport ? nil : cursor
            if showSpacing, let hovered {
                scene.gaps = spacing(around: boxes[hovered], excluding: hovered)
            } else if showPadding, let hovered, let padding = padding(in: boxes[hovered]) {
                scene.padding = padding
            } else {
                scene.live = crosshair(at: cursor)
                if settings.showLoupe, !forExport {
                    let p = pixel(at: cursor)
                    let color = buffer.color(x: p.x, y: p.y)
                    let format = settings.colorFormat == .swiftUI ? .hex : settings.colorFormat
                    var label = format.format(color)
                    if settings.showPositions { label += "  \(scene.format(CGFloat(p.x) / scale)), \(scene.format(CGFloat(p.y) / scale))" }
                    scene.loupe = Loupe(image: snapshot.image, pixel: p, cells: settings.loupeCells, label: label, color: color, reference: session?.contrastReference)
                }
            }
        }
        return scene
    }

    override func draw(_ dirtyRect: NSRect) {
        #if DEBUG
        if !demoHidesMarks { OverlayRenderer.draw(scene()) }
        drawDemoCursor()
        #else
        OverlayRenderer.draw(scene())
        #endif
    }

    /// The screenshot with every measurement drawn on it, optionally cropped to the measured area.
    func renderImage(croppedToMarks: Bool) -> CGImage? {
        let width = snapshot.image.width, height = snapshot.image.height
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        ctx.draw(snapshot.image, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: scale, y: -scale)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        OverlayRenderer.draw(scene(forExport: true))
        NSGraphicsContext.restoreGraphicsState()

        guard let full = ctx.makeImage() else { return nil }
        guard croppedToMarks, let area = markedArea else { return full }
        let crop = area.insetBy(dx: -40, dy: -40).intersection(bounds)
        return full.cropping(to: CGRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale).integral)
    }

    private var markedArea: CGRect? {
        var rects = boxes + pins.map(\.span) + lines.map { CGRect(x: min($0.from.x, $0.to.x), y: min($0.from.y, $0.to.y), width: abs($0.to.x - $0.from.x), height: abs($0.to.y - $0.from.y)) }
        if let cursor, let live = crosshair(at: cursor) { rects.append(live.span) }
        return rects.reduce(nil) { $0?.union($1) ?? $1 }
    }

    var hasMarks: Bool { !boxes.isEmpty || !pins.isEmpty || !guides.isEmpty || !lines.isEmpty }
    var showsGrid: Bool { gridOrigin != nil }

    // MARK: - Mouse

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        session?.activate(self)
        updateCursor(event)
    }

    override func mouseExited(with event: NSEvent) {
        cursor = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(event)
    }

    private func updateCursor(_ event: NSEvent) {
        cursor = convert(event.locationInWindow, from: nil)
        freeDrag = event.modifierFlags.contains(.shift)
        showSpacing = event.modifierFlags.contains(.option)
        showPadding = event.modifierFlags.contains(.control)
        if window?.isKeyWindow == false { window?.makeKey() }
        session?.activate(self)
        session?.pointerMoved(in: self)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        isDragging = false
        drawsLine = event.modifierFlags.contains(.command)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        dragCurrent = point
        freeDrag = event.modifierFlags.contains(.shift)
        if let start = dragStart, !isDragging, hypot(point.x - start.x, point.y - start.y) > 3 {
            isDragging = true
        }
        session?.pointerMoved(in: self)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragCurrent = nil
            isDragging = false
            drawsLine = false
            needsDisplay = true
        }
        if let line = dragLine {
            addLine(line)
        } else if let rect = dragRect {
            addBox(snapped(rect))
        } else if !drawsLine {
            pinCrosshair()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        cursor = convert(event.locationInWindow, from: nil)
        removeHoveredOrLast()
    }

    // MARK: - Actions

    func pinCrosshair() {
        guard let cursor, let mark = crosshair(at: cursor) else { return }
        pins.append(mark)
        history.append(.pin)
        removed.removeAll()
        session?.lastMeasured = mark.span.size
        needsDisplay = true
    }

    private func addBox(_ box: CGRect) {
        boxes.append(box)
        history.append(.box)
        removed.removeAll()
        session?.lastMeasured = box.size
    }

    private func addLine(_ line: RulerLine) {
        guard line.length > 0 else { return }
        lines.append(line)
        history.append(.line)
        removed.removeAll()
    }

    func addGuide(_ axis: Guide.Axis) {
        guard let cursor else { return }
        // On the pixel's leading edge, so guide positions and the distances between them are whole pixels.
        let p = pixel(at: cursor)
        addGuide(Guide(axis: axis, position: axis == .horizontal ? CGFloat(p.y) / scale : CGFloat(p.x) / scale))
    }

    /// A guide through the middle of the hovered box, or of the screen.
    func addCenterGuide(_ axis: Guide.Axis) {
        let area = hoveredBoxIndex.map { boxes[$0] } ?? bounds
        addGuide(Guide(axis: axis, position: axis == .horizontal ? area.midY : area.midX))
    }

    private func addGuide(_ guide: Guide) {
        guides.append(guide)
        history.append(.guide)
        removed.removeAll()
        needsDisplay = true
    }

    func removeHoveredOrLast() {
        if let index = hoveredBoxIndex {
            removed.append(.box(boxes.remove(at: index)))
            if let h = history.lastIndex(of: .box) { history.remove(at: h) }
        } else if let mark = history.popLast() {
            switch mark {
            case .box: removed.append(.box(boxes.removeLast()))
            case .pin: removed.append(.pin(pins.removeLast()))
            case .guide: removed.append(.guide(guides.removeLast()))
            case .line: removed.append(.line(lines.removeLast()))
            }
        } else {
            NSSound.beep()
        }
        needsDisplay = true
    }

    /// Puts back the last mark ⌫ or ⌘Z removed, or everything X cleared.
    func restoreRemoved() -> Bool {
        guard let mark = removed.popLast() else { return false }
        switch mark {
        case .box(let box): boxes.append(box); history.append(.box)
        case .pin(let pin): pins.append(pin); history.append(.pin)
        case .guide(let guide): guides.append(guide); history.append(.guide)
        case .line(let line): lines.append(line); history.append(.line)
        case .everything(let boxes, let pins, let guides, let lines, let history):
            (self.boxes, self.pins, self.guides, self.lines, self.history) = (boxes, pins, guides, lines, history)
        }
        needsDisplay = true
        return true
    }

    /// Removes every mark and the grid; ⇧⌘Z puts the marks back.
    func clearAll() {
        gridOrigin = nil
        needsDisplay = true
        guard hasMarks else { return }
        removed.append(.everything(boxes: boxes, pins: pins, guides: guides, lines: lines, history: history))
        boxes.removeAll()
        pins.removeAll()
        guides.removeAll()
        lines.removeAll()
        history.removeAll()
    }

    /// Shows or hides the layout grid, starting at the hovered box's corner if there is one.
    /// Returns whether it's now shown, and whether it's anchored to a box.
    func toggleGrid() -> (shown: Bool, anchored: Bool) {
        if gridOrigin != nil {
            gridOrigin = nil
            needsDisplay = true
            return (false, false)
        }
        let box = hoveredBoxIndex.map { boxes[$0] }
        gridOrigin = box?.origin ?? .zero
        needsDisplay = true
        return (true, box != nil)
    }

    /// Every measurement on this screen as text, one per line, for ⌥⌘C.
    func measurementList() -> [String] {
        let s = settings.unit.suffix
        func f(_ value: CGFloat) -> String { OverlayScene.format(value, scale: scale, unit: settings.unit) }
        var list: [String] = []
        for (i, box) in boxes.enumerated() {
            list.append("Box \(i + 1): \(f(box.width)) × \(f(box.height)) \(s) at \(f(box.minX)), \(f(box.minY))")
        }
        for (i, pin) in pins.enumerated() {
            list.append("Distance \(i + 1): \(f(pin.span.width)) × \(f(pin.span.height)) \(s) at \(f(pin.point.x)), \(f(pin.point.y))")
        }
        for (i, line) in lines.enumerated() {
            list.append("Line \(i + 1): \(f(line.length)) \(s) at \(line.angle)°")
        }
        for guide in guides {
            list.append("Guide: \(guide.axis == .horizontal ? "y" : "x") = \(f(guide.position)) \(s)")
        }
        return list
    }

    /// What ⌘C copies: the hovered box, else the live crosshair, else the most recent measurement.
    var sizeToCopy: CGSize? {
        if let index = hoveredBoxIndex { return boxes[index].size }
        if let cursor, let mark = crosshair(at: cursor) { return mark.span.size }
        return session?.lastMeasured
    }

    var colorUnderCursor: UInt32? {
        guard let cursor else { return nil }
        let p = pixel(at: cursor)
        return buffer.color(x: p.x, y: p.y)
    }

    func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        showSpacing = flags.contains(.option)
        showPadding = flags.contains(.control)
        freeDrag = flags.contains(.shift)
        needsDisplay = true
    }

    /// Moves the pointer by whole pixels for precise placement.
    func nudge(dx: Int, dy: Int) {
        guard let cursor, let screen = window?.screen ?? NSScreen.screens.first else { return }
        let p = pixel(at: cursor)
        let target = pixelCenter((min(max(p.x + dx, 0), buffer.width - 1), min(max(p.y + dy, 0), buffer.height - 1)))
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let global = CGPoint(x: screen.frame.minX + target.x, y: primaryHeight - (screen.frame.maxY - target.y))
        if !AppCoordinator.isHarness {
            CGWarpMouseCursorPosition(global)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        self.cursor = target
        session?.pointerMoved(in: self)
        needsDisplay = true
    }
}

#if DEBUG
/// Drives the overlay from a script for screenshots and visual checks (see `Harness`).
extension OverlayView {
    /// A ring that fades out where the demo clicks.
    func showDemoPress(at point: CGPoint) {
        demoPress = (point, Date())
        needsDisplay = true
    }

    fileprivate func drawDemoCursor() {
        guard showsDemoCursor, let cursor, let ctx = NSGraphicsContext.current?.cgContext else { return }
        if let press = demoPress {
            let t = Date().timeIntervalSince(press.time) / 0.45
            if t < 1 {
                let radius = 8 + 16 * t
                ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9 * (1 - t)).cgColor)
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: press.point.x - radius, y: press.point.y - radius, width: radius * 2, height: radius * 2))
            }
        }
        // Before measuring starts it's the arrow; afterwards the crosshair. Drawn larger so it reads on video.
        let pointer: NSCursor = demoHidesMarks ? .arrow : .crosshair
        let zoom: CGFloat = 1.5
        let size = CGSize(width: pointer.image.size.width * zoom, height: pointer.image.size.height * zoom)
        let origin = CGPoint(x: cursor.x - pointer.hotSpot.x * zoom, y: cursor.y - pointer.hotSpot.y * zoom)
        pointer.image.draw(in: CGRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    func simulateMove(to point: CGPoint, flags: NSEvent.ModifierFlags = []) {
        cursor = point
        showSpacing = flags.contains(.option)
        showPadding = flags.contains(.control)
        freeDrag = flags.contains(.shift)
        session?.pointerMoved(in: self)
        needsDisplay = true
    }

    func simulateDrag(from start: CGPoint, to end: CGPoint, release: Bool, line: Bool = false, constrained: Bool = false) {
        dragStart = start
        dragCurrent = end
        isDragging = true
        drawsLine = line
        freeDrag = constrained
        cursor = end
        if release {
            if let line = dragLine { addLine(line) } else if let rect = dragRect { addBox(snapped(rect)) }
            dragStart = nil
            dragCurrent = nil
            isDragging = false
            drawsLine = false
        }
        needsDisplay = true
    }
}
#endif
