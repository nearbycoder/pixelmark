import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

/// One round of measuring: a frozen overlay on every screen, from the hotkey until Escape.
@MainActor
final class MeasureSession {
    let hud = HUDModel()
    var lastMeasured: CGSize?
    /// The color picked with K; the loupe shows the contrast against it.
    var contrastReference: UInt32?
    var onEnd: (() -> Void)?

    private var windows: [OverlayWindow] = []
    private var overlays: [OverlayView] = []
    private(set) weak var active: OverlayView?
    private var previousApp: NSRunningApplication?
    private var settings: AppSettings { .shared }

    init(snapshots: [ScreenSnapshot]) {
        previousApp = NSWorkspace.shared.frontmostApplication
        for snapshot in snapshots {
            let window = OverlayWindow(screen: snapshot.screen)
            let overlay = OverlayView(snapshot: snapshot)
            overlay.session = self
            window.session = self
            window.install(snapshot: snapshot, overlay: overlay, hud: hud)
            windows.append(window)
            overlays.append(overlay)
        }
    }

    func show() {
        #if DEBUG
        if let script = Harness.script, let overlay = overlays.first {
            activate(overlay)
            Harness.run(script, session: self, overlay: overlay, windows: windows)
            return
        }
        #endif
        let mouse = NSEvent.mouseLocation
        let start = overlays.first { $0.snapshot.screen.frame.contains(mouse) } ?? overlays.first
        for window in windows { window.orderFrontRegardless() }
        NSApp.activate()
        if let start {
            start.window?.makeKeyAndOrderFront(nil)
            start.window?.makeFirstResponder(start)
            activate(start)
        }
        NSCursor.crosshair.set()
        // A nudge toward the shortcut sheet for the first few sessions.
        let sessions = UserDefaults.standard.integer(forKey: "sessionCount")
        UserDefaults.standard.set(sessions + 1, forKey: "sessionCount")
        if sessions < 3 {
            hud.showToast("Press ? for every shortcut", symbol: "keyboard")
        }
    }

    func end() {
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
        overlays.removeAll()
        NSCursor.arrow.set()
        if let previousApp, previousApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp.activate()
        }
        onEnd?()
    }

    func activate(_ overlay: OverlayView) {
        guard active !== overlay else { return }
        active = overlay
        hud.activeScreen = overlay.snapshot.screen.displayID
        for other in overlays where other !== overlay {
            other.needsDisplay = true
        }
    }

    /// Moves the helper bar out of the way when the pointer gets close to it.
    func pointerMoved(in overlay: OverlayView) {
        guard let cursor = overlay.cursor else { return }
        let height = overlay.bounds.height
        if hud.atTop {
            if cursor.y > 220 && cursor.y < height - 220 { hud.moveBar(toTop: false) }
        } else if cursor.y > height - 150 {
            hud.moveBar(toTop: true)
        }
    }

    var isPointerOverHUD: Bool {
        guard let active, let cursor = active.cursor,
              let window = active.window as? OverlayWindow else { return false }
        return window.hudRegions.contains(cursor)
    }

    // MARK: - Keyboard

    func handleKey(_ event: NSEvent) -> Bool {
        guard let overlay = active ?? overlays.first else { return false }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let step = flags.contains(.shift) ? 10 : 1

        switch Int(event.keyCode) {
        case kVK_Escape:
            if hud.showHelp { withAnimation(.snappy) { hud.showHelp = false } } else { end() }
            return true
        case kVK_LeftArrow: overlay.nudge(dx: -step, dy: 0); return true
        case kVK_RightArrow: overlay.nudge(dx: step, dy: 0); return true
        case kVK_UpArrow: overlay.nudge(dx: 0, dy: -step); return true
        case kVK_DownArrow: overlay.nudge(dx: 0, dy: step); return true
        case kVK_Delete, kVK_ForwardDelete: overlay.removeHoveredOrLast(); return true
        case kVK_Space, kVK_Return: overlay.pinCrosshair(); return true
        default: break
        }

        if flags.contains(.command) {
            switch key {
            case "c" where flags.contains(.option): copyAll()
            case "c": copyDimensions(from: overlay)
            case "s": saveScreenshot(of: overlay, cropped: flags.contains(.shift))
            case "z" where flags.contains(.shift):
                if !overlay.restoreRemoved() { NSSound.beep() }
            case "z": overlay.removeHoveredOrLast()
            case "w", "q", ".": end()
            case ",": end(); AppCoordinator.shared?.showSettings()
            default: return false
            }
            return true
        }

        let shift = flags.contains(.shift)
        switch key {
        case "h": shift ? overlay.addCenterGuide(.horizontal) : overlay.addGuide(.horizontal)
        case "v": shift ? overlay.addCenterGuide(.vertical) : overlay.addGuide(.vertical)
        case "c" where shift:
            settings.colorFormat = settings.colorFormat.next
            let sample = overlay.colorUnderCursor.map(settings.colorFormat.format) ?? settings.colorFormat.title
            hud.showToast("Colors copy as \(sample)", symbol: "eyedropper.halffull")
        case "c": copyColor(from: overlay)
        case "x":
            overlay.clearAll()
            contrastReference = nil
        case "l":
            settings.showLoupe.toggle()
            hud.showToast(settings.showLoupe ? "Loupe on" : "Loupe off", symbol: "magnifyingglass")
        case "z":
            settings.loupeZoom = (settings.loupeZoom + 1) % AppSettings.loupeZooms.count
            settings.showLoupe = true
            hud.showToast("Loupe shows \(settings.loupeCells) × \(settings.loupeCells) pixels", symbol: "plus.magnifyingglass")
        case "r":
            settings.showRulers.toggle()
            hud.showToast(settings.showRulers ? "Rulers on" : "Rulers off", symbol: "ruler")
        case "g":
            let grid = overlay.toggleGrid()
            let from = grid.anchored ? " from the box" : ""
            hud.showToast(grid.shown ? "\(settings.gridSize) pt grid\(from)" : "Grid off", symbol: "grid")
        case "a":
            settings.showAspectRatio.toggle()
            hud.showToast(settings.showAspectRatio ? "Aspect ratios on" : "Aspect ratios off", symbol: "aspectratio")
        case "p":
            settings.showPositions.toggle()
            hud.showToast(settings.showPositions ? "Positions on" : "Positions off", symbol: "location")
        case "k" where shift:
            contrastReference = nil
            hud.showToast("Contrast check off", symbol: "circle.lefthalf.filled")
        case "k":
            guard let color = overlay.colorUnderCursor else { return true }
            contrastReference = color
            hud.showToast("Checking contrast against \(PixelBuffer.hex(color))", symbol: "circle.lefthalf.filled")
        case "m":
            settings.markColor = settings.markColor.next
            hud.showToast("Marks in \(settings.markColor.title.lowercased())", symbol: "paintpalette")
        case "u":
            toggleUnit()
        case "[", "-": adjustTolerance(-(flags.contains(.shift) ? 8 : 2))
        case "]", "=", "+": adjustTolerance(flags.contains(.shift) ? 8 : 2)
        case "?", "/":
            withAnimation(.snappy) { hud.showHelp.toggle() }
        default:
            return false
        }
        redrawAll()
        return true
    }

    func flagsChanged(_ event: NSEvent) {
        active?.modifiersChanged(event.modifierFlags)
    }

    // MARK: - Actions

    func toggleUnit() {
        settings.unit = settings.unit == .points ? .pixels : .points
        hud.showToast("Measuring in \(settings.unit.title.lowercased())", symbol: "ruler")
        redrawAll()
    }

    func adjustTolerance(_ delta: Int) {
        let range = AppSettings.toleranceRange
        settings.tolerance = min(max(settings.tolerance + delta, range.lowerBound), range.upperBound)
        hud.showToast("Edge tolerance \(settings.tolerance)", symbol: "slider.horizontal.3")
        redrawAll()
    }

    private func redrawAll() {
        overlays.forEach { $0.needsDisplay = true }
    }

    private func copyDimensions(from overlay: OverlayView) {
        guard let size = overlay.sizeToCopy else {
            NSSound.beep()
            return
        }
        let scale = overlay.snapshot.scale
        let width = OverlayScene.format(size.width, scale: scale, unit: settings.unit)
        let height = OverlayScene.format(size.height, scale: scale, unit: settings.unit)
        let text = settings.copyFormat.format(width: width, height: height)
        Self.copy(text)
        hud.showToast("Copied \(width) × \(height) \(settings.unit.suffix)", symbol: "doc.on.doc.fill")
    }

    private func copyColor(from overlay: OverlayView) {
        guard let color = overlay.colorUnderCursor else { return }
        let text = settings.colorFormat.format(color)
        Self.copy(text)
        hud.showToast("Copied \(text)", symbol: "eyedropper.halffull")
    }

    /// Every measurement on every screen, one per line.
    private func copyAll() {
        let list = overlays.flatMap { $0.measurementList() }
        guard !list.isEmpty else {
            NSSound.beep()
            return
        }
        Self.copy(list.joined(separator: "\n"))
        hud.showToast("Copied \(list.count) measurement\(list.count == 1 ? "" : "s")", symbol: "list.bullet.clipboard")
    }

    private func saveScreenshot(of overlay: OverlayView, cropped: Bool) {
        guard let image = overlay.renderImage(croppedToMarks: cropped) else {
            NSSound.beep()
            return
        }
        let scale = overlay.snapshot.scale
        var done: [String] = []

        // Scripted runs show the feedback without touching the clipboard or the disk.
        let isRehearsal = AppCoordinator.isHarness
        if settings.copyScreenshot {
            if !isRehearsal {
                let nsImage = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([nsImage])
            }
            done.append("copied")
        }
        if settings.saveScreenshot {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let url = settings.saveFolder.appendingPathComponent("PixelMark \(formatter.string(from: Date())).png")
            if isRehearsal || Self.writePNG(image, to: url, scale: scale) {
                done.append("saved to \(settings.saveFolder.lastPathComponent)")
            }
        }
        guard !done.isEmpty else {
            hud.showToast("Turn on copying or saving in Settings", symbol: "exclamationmark.triangle.fill")
            return
        }
        if !isRehearsal { NSSound(named: "Tink")?.play() }
        hud.showToast("Screenshot " + done.joined(separator: " and "), symbol: "camera.fill")
    }

    private static func copy(_ text: String) {
        guard !AppCoordinator.isHarness else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Writes a PNG tagged with the display's DPI so it opens at its real size.
    private static func writePNG(_ image: CGImage, to url: URL, scale: CGFloat) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        let dpi = 72 * scale
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}

/// Borderless full-screen window that sits above everything, including the menu bar and the Dock.
final class OverlayWindow: NSWindow {
    weak var session: MeasureSession?
    let hudRegions = HitRegions()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .black
        isOpaque = true
        hasShadow = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        setFrame(screen.frame, display: false)
    }

    func install(snapshot: ScreenSnapshot, overlay: OverlayView, hud: HUDModel) {
        let bounds = NSRect(origin: .zero, size: frame.size)
        let root = NSView(frame: bounds)
        root.wantsLayer = true

        // The frozen screenshot. It's identical to what was on screen, so the overlay appears instantly.
        let background = NSView(frame: bounds)
        background.wantsLayer = true
        background.layer?.contents = snapshot.image
        background.layer?.contentsGravity = .resize
        background.autoresizingMask = [.width, .height]
        root.addSubview(background)

        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        root.addSubview(overlay)

        let hosting = PassthroughHostingView(
            rootView: HUDView(model: hud, screenID: snapshot.screen.displayID, topInset: snapshot.screen.safeAreaInsets.top, regions: hudRegions),
            regions: hudRegions
        )
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        root.addSubview(hosting)

        contentView = root
        initialFirstResponder = overlay
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func keyDown(with event: NSEvent) {
        if session?.handleKey(event) != true {
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        session?.flagsChanged(event)
        super.flagsChanged(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        session?.end()
    }
}

/// Where the SwiftUI HUD actually has content, in top-left-origin window points.
final class HitRegions {
    private var rects: [String: CGRect] = [:]

    func set(_ key: String, _ rect: CGRect?) { rects[key] = rect }
    func contains(_ point: CGPoint) -> Bool { rects.values.contains { $0.contains(point) } }
}

/// A full-size hosting view that only takes clicks where the HUD draws something.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    private let regions: HitRegions

    init(rootView: Content, regions: HitRegions) {
        self.regions = regions
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init(rootView: Content) { fatalError() }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        var local = convert(point, from: superview)
        if !isFlipped { local.y = bounds.height - local.y }
        return regions.contains(local) ? super.hitTest(point) : nil
    }
}
