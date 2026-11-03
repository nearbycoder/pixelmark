import AppKit
import Combine
import ServiceManagement
import SwiftUI

enum MeasureUnit: String, CaseIterable, Identifiable, Codable {
    case points, pixels
    var id: String { rawValue }
    var suffix: String { self == .points ? "pt" : "px" }
    var title: String { self == .points ? "Points" : "Pixels" }
}

/// How ⌘C formats a measurement.
enum CopyFormat: String, CaseIterable, Identifiable {
    case times, plain, css, swiftUI
    var id: String { rawValue }

    func format(width: String, height: String) -> String {
        switch self {
        case .times: "\(width) × \(height)"
        case .plain: "\(width)x\(height)"
        case .css: "width: \(width)px;\nheight: \(height)px;"
        case .swiftUI: ".frame(width: \(width), height: \(height))"
        }
    }

    var title: String {
        switch self {
        case .times: "320 × 48"
        case .plain: "320x48"
        case .css: "CSS"
        case .swiftUI: "SwiftUI"
        }
    }

    var example: String { format(width: "320", height: "48").replacingOccurrences(of: "\n", with: " ") }
}

/// The color used for lines and labels in the measuring overlay.
enum MarkColor: String, CaseIterable, Identifiable {
    case pink, orange, lime, cyan, blue, violet
    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .pink: NSColor(srgbRed: 1.00, green: 0.24, blue: 0.50, alpha: 1)
        case .orange: NSColor(srgbRed: 1.00, green: 0.48, blue: 0.10, alpha: 1)
        case .lime: NSColor(srgbRed: 0.40, green: 0.82, blue: 0.10, alpha: 1)
        case .cyan: NSColor(srgbRed: 0.00, green: 0.74, blue: 0.90, alpha: 1)
        case .blue: NSColor(srgbRed: 0.18, green: 0.45, blue: 1.00, alpha: 1)
        case .violet: NSColor(srgbRed: 0.58, green: 0.33, blue: 1.00, alpha: 1)
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let unit = "unit"
        static let tolerance = "tolerance"
        static let markColor = "markColor"
        static let showLoupe = "showLoupe"
        static let showHelperBar = "showHelperBar"
        static let snapToContent = "snapToContent"
        static let copyFormat = "copyFormat"
        static let copyScreenshot = "copyScreenshot"
        static let saveScreenshot = "saveScreenshot"
        static let saveFolder = "saveFolder"
        static let measureShortcut = "measureShortcut"
        static let hasOnboarded = "hasOnboarded"
    }

    private let defaults = UserDefaults.standard

    @Published var unit: MeasureUnit { didSet { defaults.set(unit.rawValue, forKey: Key.unit) } }
    /// Largest per-channel difference (0–255) that still counts as the same color when finding edges.
    @Published var tolerance: Int { didSet { defaults.set(tolerance, forKey: Key.tolerance) } }
    @Published var markColor: MarkColor { didSet { defaults.set(markColor.rawValue, forKey: Key.markColor) } }
    @Published var showLoupe: Bool { didSet { defaults.set(showLoupe, forKey: Key.showLoupe) } }
    @Published var showHelperBar: Bool { didSet { defaults.set(showHelperBar, forKey: Key.showHelperBar) } }
    @Published var snapToContent: Bool { didSet { defaults.set(snapToContent, forKey: Key.snapToContent) } }
    @Published var copyFormat: CopyFormat { didSet { defaults.set(copyFormat.rawValue, forKey: Key.copyFormat) } }
    @Published var copyScreenshot: Bool { didSet { defaults.set(copyScreenshot, forKey: Key.copyScreenshot) } }
    @Published var saveScreenshot: Bool { didSet { defaults.set(saveScreenshot, forKey: Key.saveScreenshot) } }
    @Published var saveFolder: URL { didSet { defaults.set(saveFolder.path, forKey: Key.saveFolder) } }
    @Published var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: Key.hasOnboarded) } }
    @Published var measureShortcut: Shortcut? {
        didSet {
            if let data = try? JSONEncoder().encode(measureShortcut) {
                defaults.set(data, forKey: Key.measureShortcut)
            }
        }
    }

    static let toleranceRange = 0...96

    private init() {
        defaults.register(defaults: [
            Key.unit: MeasureUnit.points.rawValue,
            Key.tolerance: 12,
            Key.markColor: MarkColor.pink.rawValue,
            Key.showLoupe: true,
            Key.showHelperBar: true,
            Key.snapToContent: true,
            Key.copyFormat: CopyFormat.times.rawValue,
            Key.copyScreenshot: true,
            Key.saveScreenshot: true,
        ])
        unit = MeasureUnit(rawValue: defaults.string(forKey: Key.unit) ?? "") ?? .points
        tolerance = defaults.integer(forKey: Key.tolerance)
        markColor = MarkColor(rawValue: defaults.string(forKey: Key.markColor) ?? "") ?? .pink
        showLoupe = defaults.bool(forKey: Key.showLoupe)
        showHelperBar = defaults.bool(forKey: Key.showHelperBar)
        snapToContent = defaults.bool(forKey: Key.snapToContent)
        copyFormat = CopyFormat(rawValue: defaults.string(forKey: Key.copyFormat) ?? "") ?? .times
        copyScreenshot = defaults.bool(forKey: Key.copyScreenshot)
        saveScreenshot = defaults.bool(forKey: Key.saveScreenshot)
        hasOnboarded = defaults.bool(forKey: Key.hasOnboarded)
        saveFolder = defaults.string(forKey: Key.saveFolder).map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        if let data = defaults.data(forKey: Key.measureShortcut),
           let stored = try? JSONDecoder().decode(Shortcut?.self, from: data) {
            measureShortcut = stored
        } else {
            measureShortcut = .defaultMeasure
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("PixelMark: failed to update login item: \(error)")
            }
        }
    }

    func resetToDefaults() {
        unit = .points
        tolerance = 12
        markColor = .pink
        showLoupe = true
        showHelperBar = true
        snapToContent = true
        copyFormat = .times
        copyScreenshot = true
        saveScreenshot = true
        measureShortcut = .defaultMeasure
    }
}

/// Runtime (non-persisted) state shared across the UI.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var hasScreenPermission = ScreenPermission.isGranted
    @Published var shortcutUnavailable = false
    @Published var isRecordingShortcut = false
    @Published var settingsTab: SettingsTab = .measuring

    func refreshPermission() {
        let granted = ScreenPermission.isGranted
        if granted != hasScreenPermission {
            hasScreenPermission = granted
        }
    }
}

enum ScreenPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Adds PixelMark to the Screen Recording list (once) so the user only has to flip its switch.
    static func request() {
        if !CGRequestScreenCaptureAccess() {
            openSystemSettings()
        }
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Quits and reopens PixelMark so a newly granted permission takes effect.
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.8; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
