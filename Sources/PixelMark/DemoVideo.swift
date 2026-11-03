#if DEBUG
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

/// Records the feature walkthrough for the website (Debug builds only):
///   PIXELMARK_DEMO_IMAGE=backdrop.png PIXELMARK_HARNESS=video:/path/to/out.mov PixelMark
/// The overlay runs behind other windows and ScreenCaptureKit records just that window,
/// so the screen stays usable while it plays.
@MainActor
final class DemoVideo {
    private let session: MeasureSession
    private let overlay: OverlayView
    private let recorder = WindowRecorder()
    private var cursor = CGPoint(x: 960, y: 760)
    private var activity: NSObjectProtocol?

    init(session: MeasureSession, overlay: OverlayView) {
        self.session = session
        self.overlay = overlay
    }

    func run(to url: URL) {
        // Keep timers precise even though the window is out of sight.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Recording demo")
        Task {
            do {
                guard let window = overlay.window else { return }
                AppSettings.shared.resetToDefaults() // each take starts the same way
                AppSettings.shared.showHelperBar = false
                overlay.showsDemoCursor = true
                overlay.demoHidesMarks = true
                overlay.simulateMove(to: cursor)
                try await recorder.start(window: window, url: url)
                startedAt = Date()
                try await script()
                try await recorder.stop()
                print("VIDEO_DONE \(url.path)")
            } catch {
                print("VIDEO_FAILED \(error)")
            }
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    // MARK: - The walkthrough

    private func script() async throws {
        let settings = AppSettings.shared
        try await move(to: CGPoint(x: 880, y: 640), duration: 1.0)
        try await wait(0.3)

        caption(["⇧⌘2"], "Start measuring from any app")
        try await wait(1.0)
        overlay.demoHidesMarks = false
        settings.showHelperBar = true
        try await wait(1.6)

        caption(["Move"], "Hover to see the distance to the nearest edges")
        try await move(to: CGPoint(x: 780, y: 304), duration: 1.1)
        try await wait(0.7)
        try await move(to: CGPoint(x: 850, y: 404), duration: 0.9)
        try await wait(0.7)
        try await move(to: CGPoint(x: 1078, y: 640), duration: 1.0)
        try await wait(0.8)
        try await move(to: CGPoint(x: 1300, y: 600), duration: 0.9)
        try await wait(0.7)

        caption(["C"], "Copy the color under the pointer")
        try await move(to: CGPoint(x: 1078, y: 660), duration: 0.7)
        try await wait(0.3)
        press("c")
        try await wait(1.8)

        caption(["Drag"], "Drag a box and it snaps to what's inside")
        try await move(to: CGPoint(x: 1352, y: 230), duration: 0.9)
        try await drag(to: CGPoint(x: 1540, y: 310), duration: 1.1)
        try await wait(1.0)
        try await move(to: CGPoint(x: 652, y: 342), duration: 0.8)
        try await drag(to: CGPoint(x: 905, y: 458), duration: 1.0)
        try await wait(1.2)

        caption(["⌘C"], "Copy a size as text, CSS or SwiftUI")
        try await move(to: CGPoint(x: 1444, y: 272), duration: 0.8)
        try await wait(0.3)
        press("c", flags: .command)
        try await wait(1.8)

        caption(["Click"], "Click to pin a measurement")
        try await move(to: CGPoint(x: 1300, y: 830), duration: 0.9)
        click()
        try await wait(0.6)
        try await move(to: CGPoint(x: 940, y: 560), duration: 0.8)
        click()
        try await wait(1.2)

        caption(["X"], "Clear everything")
        press("x")
        try await wait(1.0)

        caption(["[", "]"], "Adjust edge tolerance")
        try await move(to: CGPoint(x: 1078, y: 860), duration: 0.6)
        for _ in 0..<4 {
            press("[")
            try await wait(0.3)
        }
        try await wait(0.8)

        caption(["⌥"], "Hold Option to see the spacing around a box")
        for (start, end) in [(CGPoint(x: 630, y: 320), CGPoint(x: 930, y: 478)), (CGPoint(x: 930, y: 320), CGPoint(x: 1228, y: 478)), (CGPoint(x: 1228, y: 320), CGPoint(x: 1526, y: 478))] {
            try await move(to: start, duration: 0.45)
            try await drag(to: end, duration: 0.55)
        }
        try await move(to: CGPoint(x: 1078, y: 420), duration: 0.6)
        try await move(to: CGPoint(x: 1082, y: 418), duration: 0.2, flags: .option)
        try await wait(2.0)
        try await move(to: CGPoint(x: 1376, y: 420), duration: 0.8, flags: .option)
        try await wait(1.6)
        try await move(to: CGPoint(x: 1376, y: 420), duration: 0.1)

        caption(["H", "V"], "Drop guides to check alignment")
        press("x")
        for (point, key) in [(CGPoint(x: 643, y: 600), "v"), (CGPoint(x: 1514, y: 600), "v"), (CGPoint(x: 1000, y: 333), "h"), (CGPoint(x: 1000, y: 465), "h")] {
            try await move(to: point, duration: 0.6)
            press(key)
            try await wait(0.35)
        }
        try await wait(1.0)

        caption(["U"], "Switch between points and pixels")
        press("x")
        try await move(to: CGPoint(x: 1078, y: 640), duration: 0.8)
        try await wait(0.6)
        press("u")
        try await wait(1.4)
        press("u")
        try await wait(0.8)

        caption(["←", "→"], "Nudge the pointer one pixel at a time")
        for _ in 0..<6 {
            press("", code: kVK_RightArrow)
            try await wait(0.22)
        }
        try await wait(0.6)

        caption(["⌘S"], "Save a screenshot with your measurements")
        try await move(to: CGPoint(x: 1352, y: 230), duration: 0.6)
        try await drag(to: CGPoint(x: 1540, y: 310), duration: 0.8)
        try await move(to: CGPoint(x: 1078, y: 640), duration: 0.7)
        press("s", flags: .command)
        try await wait(2.0)

        caption(["?"], "See every shortcut")
        press("?")
        try await wait(3.0)
        press("", code: kVK_Escape)
        try await wait(0.6)

        caption(["Esc"], "Done")
        try await wait(1.6)
    }

    // MARK: - Actions

    private var startedAt = Date()

    /// Also logs a chapter marker, which Scripts/record-demo.sh turns into the site's chapter list.
    private func caption(_ keys: [String], _ text: String) {
        session.hud.showCaption(keys: keys, text: text)
        print(String(format: "CHAPTER %.2f\t%@\t%@", Date().timeIntervalSince(startedAt), keys.joined(separator: " "), text))
    }

    private func wait(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    /// Eases the pointer to a point at 60 fps.
    private func move(to target: CGPoint, duration: Double, flags: NSEvent.ModifierFlags = []) async throws {
        let start = cursor
        let frames = max(1, Int(duration * 60))
        for frame in 1...frames {
            let t = Double(frame) / Double(frames)
            let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            cursor = CGPoint(x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased)
            overlay.simulateMove(to: cursor, flags: flags)
            try await Task.sleep(for: .milliseconds(16))
        }
    }

    private func drag(to target: CGPoint, duration: Double) async throws {
        let start = cursor
        overlay.showDemoPress(at: start)
        let frames = max(1, Int(duration * 60))
        for frame in 1...frames {
            let t = Double(frame) / Double(frames)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            cursor = CGPoint(x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased)
            overlay.simulateDrag(from: start, to: cursor, release: frame == frames)
            try await Task.sleep(for: .milliseconds(16))
        }
        overlay.simulateMove(to: cursor)
    }

    private func click() {
        overlay.showDemoPress(at: cursor)
        overlay.pinCrosshair()
    }

    private func press(_ characters: String, code: Int = 0, flags: NSEvent.ModifierFlags = []) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: overlay.window?.windowNumber ?? 0,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: UInt16(code)
        ) else { return }
        _ = session.handleKey(event)
    }

}

/// Records one window to a movie file with ScreenCaptureKit.
final class WindowRecorder: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var finished: CheckedContinuation<Void, Error>?

    enum Failure: Error { case windowNotFound }

    @MainActor
    func start(window: NSWindow, url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let target = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            throw Failure.windowNotFound
        }
        let scale = window.backingScaleFactor
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.sRGB

        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mov
        recording.videoCodecType = .h264

        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: target), configuration: config, delegate: nil)
        try stream.addRecordingOutput(SCRecordingOutput(configuration: recording, delegate: self))
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async throws {
        guard let stream else { return }
        try await withCheckedThrowingContinuation { continuation in
            finished = continuation
            Task { try? await stream.stopCapture() }
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finished?.resume()
        finished = nil
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finished?.resume(throwing: error)
        finished = nil
    }
}
#endif
