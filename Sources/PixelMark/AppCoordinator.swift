import AppKit
import Combine

@main
@MainActor
enum PixelMarkMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests load the app as their host; keep it inert.
        guard NSClassFromString("XCTestCase") == nil else { return }
        let coordinator = AppCoordinator()
        coordinator.start()
        self.coordinator = coordinator
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.showSettings()
        return false
    }
}

@MainActor
final class AppCoordinator {
    private(set) static weak var shared: AppCoordinator?

    private(set) var session: MeasureSession?
    private var isStarting = false
    private let statusBar = StatusBarController()
    private let settingsWindow = SettingsWindowController()
    private let welcomeWindow = WelcomeWindowController()
    private var cancellables: Set<AnyCancellable> = []

    private static let measureHotKey: UInt32 = 1

    /// True when a debug screenshot script is driving the app.
    static var isHarness: Bool { ProcessInfo.processInfo.environment["PIXELMARK_HARNESS"] != nil }

    func start() {
        Self.shared = self
        statusBar.install()

        AppSettings.shared.$measureShortcut
            .sink { [weak self] shortcut in self?.registerHotKey(shortcut) }
            .store(in: &cancellables)

        #if DEBUG
        if let script = Harness.script {
            if script.hasPrefix("window:") {
                Harness.showWindow(String(script.dropFirst("window:".count)), coordinator: self)
            } else {
                startMeasuring()
            }
            return
        }
        #endif
        if !AppSettings.shared.hasOnboarded || !ScreenPermission.isGranted {
            welcomeWindow.show()
        }
    }

    private func registerHotKey(_ shortcut: Shortcut?) {
        guard let shortcut else {
            HotKeyCenter.shared.unregister(id: Self.measureHotKey)
            AppState.shared.shortcutUnavailable = false
            return
        }
        let ok = HotKeyCenter.shared.register(id: Self.measureHotKey, shortcut: shortcut) { [weak self] in
            // Don't fire while the user is typing a new shortcut into Settings.
            guard !AppState.shared.isRecordingShortcut else { return }
            self?.toggleMeasuring()
        }
        AppState.shared.shortcutUnavailable = !ok
    }

    func toggleMeasuring() {
        if let session {
            session.end()
        } else {
            startMeasuring()
        }
    }

    func startMeasuring() {
        guard session == nil, !isStarting else { return }
        guard ScreenPermission.isGranted || DemoSnapshot.isEnabled else {
            welcomeWindow.show()
            return
        }
        isStarting = true
        Task { [self] in
            defer { isStarting = false }
            var snapshots: [ScreenSnapshot]
            do {
                if let demo = try DemoSnapshot.load() {
                    snapshots = demo
                } else {
                    snapshots = try await ScreenCapture.captureAllScreens()
                }
            } catch {
                NSLog("PixelMark: capture failed: \(error)")
                AppState.shared.refreshPermission()
                welcomeWindow.show()
                return
            }
            let session = MeasureSession(snapshots: snapshots)
            session.onEnd = { [weak self] in self?.session = nil }
            self.session = session
            session.show()
        }
    }

    func showSettings() {
        settingsWindow.show()
    }

    func showWelcome() {
        welcomeWindow.show()
    }
}

/// Measures a saved image instead of the screen: `PIXELMARK_DEMO_IMAGE=/path/to.png`.
/// Handy for trying PixelMark before granting Screen Recording, and for making screenshots.
enum DemoSnapshot {
    static var path: String? { ProcessInfo.processInfo.environment["PIXELMARK_DEMO_IMAGE"] }
    static var isEnabled: Bool { path != nil }

    @MainActor
    static func load() throws -> [ScreenSnapshot]? {
        guard let path, let screen = NSScreen.main else { return nil }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let buffer = PixelBuffer(image: image)
        else { throw ScreenCapture.Failure.nothingCaptured }
        return [ScreenSnapshot(screen: screen, image: image, buffer: buffer)]
    }
}
