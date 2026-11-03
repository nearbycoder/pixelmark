import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A standard Settings window: toolbar tabs, each a grouped form.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var tabs: NSTabViewController?

    func show() {
        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.transitionOptions = [.crossfade, .allowUserInteraction]
            for tab in SettingsTab.allCases {
                let hosting = NSHostingController(rootView: SettingsPane(tab: tab))
                hosting.sizingOptions = [.preferredContentSize]
                hosting.title = tab.title // shown as the window title
                let item = NSTabViewItem(viewController: hosting)
                item.label = tab.title
                item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
                tabs.addTabViewItem(item)
            }
            // Opens on General the first time, then wherever it was left.
            tabs.selectedTabViewItemIndex = SettingsTab.allCases.firstIndex(of: AppState.shared.settingsTab) ?? 0
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            self.tabs = tabs
            self.window = window
        }
        AppState.shared.refreshPermission()
        if window?.isVisible != true { window?.center() }
        if AppCoordinator.isHarness {
            window?.orderBack(nil) // screenshots without stealing focus
        } else {
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, measuring, capture, shortcuts, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .measuring: "Measuring"
        case .capture: "Copy & Save"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .measuring: "ruler"
        case .capture: "doc.on.doc"
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        }
    }
}

struct SettingsPane: View {
    let tab: SettingsTab
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var state = AppState.shared

    var body: some View {
        Form {
            switch tab {
            case .general: general
            case .measuring: measuring
            case .capture: capture
            case .shortcuts: shortcuts
            case .about: about
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(tab != .shortcuts)
        .frame(width: 480, height: tab == .shortcuts ? 560 : nil)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var general: some View {
        if !state.hasScreenPermission {
            Section {
                PermissionRow()
            }
        }
        Section {
            LabeledContent("Start measuring") {
                ShortcutRecorder(shortcut: $settings.measureShortcut, isUnavailable: state.shortcutUnavailable)
            }
        } footer: {
            Text("Works from any app. Press it again, or Esc, to finish.")
        }
        Section {
            Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
            Toggle("Show the helper bar while measuring", isOn: $settings.showHelperBar)
        }
        Section {
            LabeledContent("Reset all settings") {
                Button("Reset…", action: confirmReset)
            }
        }
    }

    @ViewBuilder
    private var measuring: some View {
        Section {
            LabeledContent("Edge tolerance") {
                HStack {
                    Slider(
                        value: Binding(get: { Double(settings.tolerance) }, set: { settings.tolerance = Int($0.rounded()) }),
                        in: Double(AppSettings.toleranceRange.lowerBound)...Double(AppSettings.toleranceRange.upperBound)
                    )
                    .frame(width: 180)
                    Text("\(settings.tolerance)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
            }
            Toggle("Snap boxes to content", isOn: $settings.snapToContent)
        } header: {
            Text("Edges")
        } footer: {
            Text("Lower tolerance stops at faint borders; higher skips shadows and anti-aliasing. Change it while measuring with [ and ]. Hold ⇧ while dragging to flip snapping.")
        }

        Section("Display") {
            Picker("Units", selection: $settings.unit) {
                ForEach(MeasureUnit.allCases) { Text($0.title).tag($0) }
            }
            LabeledContent("Measurement color") {
                ColorChoice(selection: $settings.markColor)
            }
            Toggle("Show loupe", isOn: $settings.showLoupe)
        }

        Section {
            Toggle("Rulers", isOn: $settings.showRulers)
            Toggle("Aspect ratios on boxes", isOn: $settings.showAspectRatio)
            Toggle("Positions on boxes", isOn: $settings.showPositions)
            Picker("Grid size", selection: $settings.gridSize) {
                ForEach(AppSettings.gridSizes, id: \.self) { Text("\($0) pt").tag($0) }
            }
        } header: {
            Text("Extras")
        } footer: {
            Text("Toggle these while measuring with R, A and P. G shows the grid, starting at the hovered box.")
        }
    }

    @ViewBuilder
    private var capture: some View {
        Section {
            Picker("Format", selection: $settings.copyFormat) {
                ForEach(CopyFormat.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Copy dimensions (⌘C)")
        } footer: {
            Text(settings.copyFormat.example).font(.system(.callout, design: .monospaced))
        }

        Section {
            Picker("Format", selection: $settings.colorFormat) {
                ForEach(ColorFormat.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Copy colors (C)")
        } footer: {
            Text(settings.colorFormat.format(0xFF3D7F)).font(.system(.callout, design: .monospaced))
        }

        Section {
            Toggle("Copy to clipboard", isOn: $settings.copyScreenshot)
            Toggle("Save to folder", isOn: $settings.saveScreenshot)
            if settings.saveScreenshot {
                LabeledContent("Folder") {
                    HStack {
                        Text((settings.saveFolder.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…", action: chooseFolder)
                    }
                }
            }
        } header: {
            Text("Screenshots (⌘S)")
        } footer: {
            Text("Screenshots include every measurement on screen. ⇧⌘S crops to the measured area.")
        }
    }

    /// The same list as the ? sheet while measuring.
    @ViewBuilder
    private var shortcuts: some View {
        ForEach(ShortcutSheet.groups, id: \.0) { group in
            Section(group.0) {
                ForEach(group.1, id: \.0) { item in
                    LabeledContent(item.1) {
                        Text(item.0).font(.body.weight(.medium))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var about: some View {
        Section {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PixelMark").font(.title3.weight(.semibold))
                    Text("Version \(Bundle.main.shortVersion)").foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            Text("A free, open source screen ruler for macOS. Made by Josh Hamilton and released under the MIT License. Inspired by PixelSnap.")
                .foregroundStyle(.secondary)
        }
        Section {
            Link("Source code on GitHub", destination: StatusBarController.repositoryURL)
            Link("Report an issue", destination: StatusBarController.repositoryURL.appendingPathComponent("issues"))
            Button("Show welcome window") { AppCoordinator.shared?.showWelcome() }
                .buttonStyle(.link)
        }
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset all settings?"
        alert.informativeText = "Units, colors, formats, the shortcut and every other setting go back to how PixelMark started."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            settings.resetToDefaults()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveFolder
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveFolder = url
        }
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
}

struct PermissionRow: View {
    var body: some View {
        LabeledContent {
            Button("Allow…") { ScreenPermission.request() }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Recording is off")
                    Text("PixelMark reads the pixels on screen to find edges. Nothing leaves your Mac.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }
}

struct ColorChoice: View {
    @Binding var selection: MarkColor

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MarkColor.allCases) { color in
                let selected = selection == color
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 16, height: 16)
                        .padding(3)
                        .overlay { Circle().strokeBorder(selected ? Color.primary.opacity(0.6) : .clear, lineWidth: 1.5) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.rawValue.capitalized)
                .accessibilityLabel(color.rawValue.capitalized)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    var isUnavailable = false

    @StateObject private var recorder = ShortcutRecorderModel()

    var body: some View {
        HStack(spacing: 6) {
            if isUnavailable && !recorder.isRecording {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("This shortcut is already used by another app")
            }
            Button(action: toggleRecording) {
                Text(label)
                    .foregroundStyle(recorder.isRecording || shortcut == nil ? .secondary : .primary)
                    .frame(minWidth: 96)
            }
            if shortcut != nil && !recorder.isRecording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear shortcut")
            }
        }
        .onDisappear { recorder.stop() }
    }

    private var label: String {
        if recorder.isRecording { return "Type shortcut…" }
        return shortcut?.displayString ?? "Record Shortcut"
    }

    private func toggleRecording() {
        if recorder.isRecording {
            recorder.stop()
        } else {
            recorder.start { shortcut = $0 }
        }
    }
}

/// Captures the next key combo typed while the settings window is focused.
@MainActor
final class ShortcutRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?

    func start(onRecord: @escaping (Shortcut?) -> Void) {
        stop()
        isRecording = true
        AppState.shared.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event, onRecord: onRecord)
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if isRecording {
            isRecording = false
            AppState.shared.isRecordingShortcut = false
        }
    }

    private func handle(_ event: NSEvent, onRecord: (Shortcut?) -> Void) {
        let modifiers = event.modifierFlags.intersection(Shortcut.relevantModifiers)
        let keyCode = Int(event.keyCode)

        if keyCode == kVK_Escape && modifiers.isEmpty {
            stop()
            return
        }
        if (keyCode == kVK_Delete || keyCode == kVK_ForwardDelete) && modifiers.isEmpty {
            onRecord(nil)
            stop()
            return
        }
        // Require a real modifier (not just Shift) unless it's a function key.
        guard !modifiers.subtracting(.shift).isEmpty || Shortcut.isFunctionKey(event.keyCode) else {
            NSSound.beep()
            return
        }
        onRecord(Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers))
        stop()
    }
}
