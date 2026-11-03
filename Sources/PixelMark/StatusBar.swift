import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let menu = NSMenu()

    static let repositoryURL = URL(string: "https://github.com/nearbycoder/pixelmark")!

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarIcon()
        item.button?.toolTip = "PixelMark"
        menu.delegate = self
        item.menu = menu
        self.item = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = AppSettings.shared

        let measure = NSMenuItem(title: "Measure", action: #selector(measure), keyEquivalent: "")
        measure.image = NSImage(systemSymbolName: "ruler", accessibilityDescription: nil)
        if let shortcut = settings.measureShortcut {
            // Shown for reference; the global hot key does the work.
            measure.keyEquivalent = KeyNames.name(for: shortcut.keyCode).lowercased()
            measure.keyEquivalentModifierMask = shortcut.modifierFlags
        }
        add(measure)

        if !ScreenPermission.isGranted {
            let permission = NSMenuItem(title: "Allow Screen Recording…", action: #selector(welcome), keyEquivalent: "")
            permission.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            add(permission)
        }
        menu.addItem(.separator())

        let units = NSMenuItem(title: "Units", action: nil, keyEquivalent: "")
        let unitsMenu = NSMenu()
        for unit in MeasureUnit.allCases {
            let option = NSMenuItem(title: unit.title, action: #selector(setUnit(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = unit.rawValue
            option.state = settings.unit == unit ? .on : .off
            unitsMenu.addItem(option)
        }
        units.submenu = unitsMenu
        menu.addItem(units)

        let loupe = NSMenuItem(title: "Show Loupe", action: #selector(toggleLoupe), keyEquivalent: "")
        loupe.state = settings.showLoupe ? .on : .off
        add(loupe)

        let snap = NSMenuItem(title: "Snap Boxes to Content", action: #selector(toggleSnap), keyEquivalent: "")
        snap.state = settings.snapToContent ? .on : .off
        add(snap)

        menu.addItem(.separator())
        add(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        add(NSMenuItem(title: "Welcome Tour", action: #selector(welcome), keyEquivalent: ""))
        add(NSMenuItem(title: "PixelMark on GitHub", action: #selector(openGitHub), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit PixelMark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func add(_ item: NSMenuItem) {
        item.target = self
        menu.addItem(item)
    }

    @objc private func measure() {
        // Let the menu close before the screen is captured.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            AppCoordinator.shared?.startMeasuring()
        }
    }

    @objc private func setUnit(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let unit = MeasureUnit(rawValue: raw) {
            AppSettings.shared.unit = unit
        }
    }

    @objc private func toggleLoupe() { AppSettings.shared.showLoupe.toggle() }
    @objc private func toggleSnap() { AppSettings.shared.snapToContent.toggle() }
    @objc private func openSettings() { AppCoordinator.shared?.showSettings() }
    @objc private func welcome() { AppCoordinator.shared?.showWelcome() }
    @objc private func openGitHub() { NSWorkspace.shared.open(Self.repositoryURL) }

    /// Selection corners around a dimension line, matching the app icon.
    static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            let corners = NSBezierPath()
            corners.lineWidth = 1.6
            corners.lineCapStyle = .round
            corners.lineJoinStyle = .round
            let (lo, hi, arm): (CGFloat, CGFloat, CGFloat) = (2.5, 15.5, 4.2)
            corners.move(to: NSPoint(x: lo, y: lo + arm)); corners.line(to: NSPoint(x: lo, y: lo)); corners.line(to: NSPoint(x: lo + arm, y: lo))
            corners.move(to: NSPoint(x: hi - arm, y: lo)); corners.line(to: NSPoint(x: hi, y: lo)); corners.line(to: NSPoint(x: hi, y: lo + arm))
            corners.move(to: NSPoint(x: hi, y: hi - arm)); corners.line(to: NSPoint(x: hi, y: hi)); corners.line(to: NSPoint(x: hi - arm, y: hi))
            corners.move(to: NSPoint(x: lo + arm, y: hi)); corners.line(to: NSPoint(x: lo, y: hi)); corners.line(to: NSPoint(x: lo, y: hi - arm))
            corners.stroke()

            let ruler = NSBezierPath()
            ruler.lineWidth = 1.6
            ruler.lineCapStyle = .round
            ruler.move(to: NSPoint(x: 6, y: 9)); ruler.line(to: NSPoint(x: 12, y: 9))
            ruler.move(to: NSPoint(x: 6, y: 6.6)); ruler.line(to: NSPoint(x: 6, y: 11.4))
            ruler.move(to: NSPoint(x: 12, y: 6.6)); ruler.line(to: NSPoint(x: 12, y: 11.4))
            ruler.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
