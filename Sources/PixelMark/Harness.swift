#if DEBUG
import AppKit

/// Debug-only scripted overlay for screenshots, without covering the screen:
///   PIXELMARK_DEMO_IMAGE=backdrop.png PIXELMARK_HARNESS="move 900 400; drag 10 10 200 80; option 600 300" PixelMark
/// The overlay window is ordered to the back and its window number printed, for `screencapture -l`.
@MainActor
enum Harness {
    static var script: String? { ProcessInfo.processInfo.environment["PIXELMARK_HARNESS"] }

    /// Shows a window behind everything else and prints its number: `PIXELMARK_HARNESS=window:settings`.
    static func showWindow(_ name: String, coordinator: AppCoordinator) {
        let before = Set(NSApp.windows.map(\.windowNumber))
        if name.hasPrefix("settings") {
            if let tab = SettingsTab(rawValue: String(name.dropFirst("settings".count + 1))) { AppState.shared.settingsTab = tab }
            coordinator.showSettings()
        } else {
            coordinator.showWelcome()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard let window = NSApp.windows.first(where: { !before.contains($0.windowNumber) && $0.isVisible && $0.frame.width > 300 }) else { return }
            print("HARNESS_WINDOW \(window.windowNumber)")
            fflush(stdout)
        }
    }

    private static var video: DemoVideo?

    static func run(_ script: String, session: MeasureSession, overlay: OverlayView, windows: [NSWindow]) {
        for window in windows {
            window.level = .normal
            window.orderBack(nil)
        }
        if script.hasPrefix("video:") {
            let video = DemoVideo(session: session, overlay: overlay)
            video.run(to: URL(fileURLWithPath: String(script.dropFirst("video:".count))))
            self.video = video
            return
        }
        for command in script.split(separator: ";") {
            let parts = command.split(separator: " ").map(String.init)
            guard let name = parts.first else { continue }
            let numbers = parts.dropFirst().compactMap(Double.init).map { CGFloat($0) }
            switch name {
            case "move" where numbers.count == 2:
                overlay.simulateMove(to: CGPoint(x: numbers[0], y: numbers[1]))
            case "option" where numbers.count == 2:
                overlay.simulateMove(to: CGPoint(x: numbers[0], y: numbers[1]), flags: .option)
            case "click" where numbers.count == 2:
                overlay.simulateMove(to: CGPoint(x: numbers[0], y: numbers[1]))
                overlay.pinCrosshair()
            case "drag" where numbers.count == 4:
                overlay.simulateDrag(from: CGPoint(x: numbers[0], y: numbers[1]), to: CGPoint(x: numbers[2], y: numbers[3]), release: true)
            case "dragging" where numbers.count == 4:
                overlay.simulateDrag(from: CGPoint(x: numbers[0], y: numbers[1]), to: CGPoint(x: numbers[2], y: numbers[3]), release: false)
            case "control" where numbers.count == 2:
                overlay.simulateMove(to: CGPoint(x: numbers[0], y: numbers[1]), flags: .control)
            case "line" where numbers.count == 4:
                overlay.simulateDrag(from: CGPoint(x: numbers[0], y: numbers[1]), to: CGPoint(x: numbers[2], y: numbers[3]), release: true, line: true)
            case "key" where parts.count == 2:
                // A key as typed while measuring; a leading ^ adds ⇧, e.g. "key ^h".
                let shifted = parts[1].hasPrefix("^")
                let character = shifted ? String(parts[1].dropFirst()) : parts[1]
                if let event = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: shifted ? .shift : [], timestamp: 0,
                    windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character,
                    isARepeat: false, keyCode: 0
                ) { _ = session.handleKey(event) }
            case "hguide": overlay.addGuide(.horizontal)
            case "vguide": overlay.addGuide(.vertical)
            case "help": session.hud.showHelp = true
            case "top": session.hud.atTop = true
            case "toast": session.hud.showToast(parts.dropFirst().joined(separator: " "), symbol: "doc.on.doc.fill")
            case "tolerance" where numbers.count == 1: AppSettings.shared.tolerance = Int(numbers[0])
            case "pixels": AppSettings.shared.unit = .pixels
            case "points": AppSettings.shared.unit = .points
            case "noloupe": AppSettings.shared.showLoupe = false
            case "loupe": AppSettings.shared.showLoupe = true
            case "color": if let c = parts.dropFirst().first, let color = MarkColor(rawValue: c) { AppSettings.shared.markColor = color }
            default: print("Harness: skipped \(command)")
            }
        }
        if let window = overlay.window {
            print("HARNESS_WINDOW \(window.windowNumber)")
            fflush(stdout)
        }
    }
}
#endif
