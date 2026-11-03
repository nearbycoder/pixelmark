import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            hosting.sizingOptions = [.preferredContentSize]
            let window = GlassWindow(contentViewController: hosting)
            window.title = "PixelMark Settings"
            self.window = window
        }
        AppState.shared.refreshPermission()
        window?.center()
        if AppCoordinator.isHarness {
            window?.orderBack(nil) // screenshots without stealing focus
        } else {
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
        }
    }
}

/// A titled window with a hidden, transparent title bar so glass content fills it edge to edge.
final class GlassWindow: NSWindow {
    convenience init(contentViewController: NSViewController) {
        self.init(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        self.contentViewController = contentViewController
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case measuring, capture, shortcuts, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .measuring: "Measuring"
        case .capture: "Copy & Save"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .measuring: "ruler"
        case .capture: "camera.viewfinder"
        case .shortcuts: "keyboard"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if !state.hasScreenPermission {
                PermissionBanner()
            }

            TabSwitch(selection: $state.settingsTab)

            // Every tab is laid out, so the window stays the size of the tallest instead of jumping.
            ZStack(alignment: .top) {
                ForEach(SettingsTab.allCases) { tab in
                    let selected = tab == state.settingsTab
                    page(tab)
                        .opacity(selected ? 1 : 0)
                        .allowsHitTesting(selected)
                        .accessibilityHidden(!selected)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .background { AmbientBackground().ignoresSafeArea() }
        .tint(settings.markColor.color)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("PixelMark")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Measure anything on your screen.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                AppCoordinator.shared?.startMeasuring()
            } label: {
                Label("Measure", systemImage: "ruler")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.glassProminent)
            .help("Start measuring")
        }
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        switch tab {
        case .measuring: measuringPage
        case .capture: capturePage
        case .shortcuts: shortcutsPage
        case .about: aboutPage
        }
    }

    private var measuringPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassSection("Edges", symbol: "viewfinder") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Edge tolerance").font(.system(size: 13))
                        Spacer()
                        Text("\(settings.tolerance)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(get: { Double(settings.tolerance) }, set: { settings.tolerance = Int($0) }),
                        in: Double(AppSettings.toleranceRange.lowerBound)...Double(AppSettings.toleranceRange.upperBound),
                        step: 1
                    ) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Exact").font(.system(size: 10)).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("Loose").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Text("Low values stop at the faintest change, like a 1 px border. Raise it to skip shadows, gradients and anti-aliasing. Adjust it live with [ and ].")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().opacity(0.5)
                SettingToggle(
                    "Snap boxes to content",
                    detail: "A dragged box shrinks to fit what's inside it. Hold ⇧ while dragging to do the opposite.",
                    isOn: $settings.snapToContent
                )
            }

            GlassSection("Display", symbol: "paintpalette") {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Units").font(.system(size: 13))
                        Text("Points match your design files. Pixels are the physical pixels on this display.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Picker("Units", selection: $settings.unit) {
                        ForEach(MeasureUnit.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                HStack {
                    Text("Color").font(.system(size: 13))
                    Spacer()
                    ColorChoice(selection: $settings.markColor)
                }
                SettingToggle("Show the loupe", detail: "A magnified view of the pixels under the pointer, with their color.", isOn: $settings.showLoupe)
                SettingToggle("Show the helper bar", detail: "Shortcut hints and controls at the bottom of the screen.", isOn: $settings.showHelperBar)
            }
        }
    }

    private var capturePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassSection("Copy Dimensions (⌘C)", symbol: "doc.on.doc") {
                HStack {
                    Text("Format").font(.system(size: 13))
                    Spacer()
                    Picker("Format", selection: $settings.copyFormat) {
                        ForEach(CopyFormat.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                Text(settings.copyFormat.example)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            GlassSection("Screenshots (⌘S)", symbol: "camera") {
                SettingToggle("Copy to clipboard", isOn: $settings.copyScreenshot)
                SettingToggle("Save to folder", isOn: $settings.saveScreenshot)
                if settings.saveScreenshot {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill").foregroundStyle(.tint)
                        Text((settings.saveFolder.path as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…", action: chooseFolder)
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                }
                Text("Screenshots include every measurement on screen. ⇧⌘S crops to just the measured area.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            GlassSection("General", symbol: "gearshape") {
                SettingToggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
                HStack {
                    Text("Reset all settings").font(.system(size: 13))
                    Spacer()
                    Button("Reset", action: settings.resetToDefaults)
                        .buttonStyle(.glass)
                        .controlSize(.small)
                }
            }
        }
    }

    private var shortcutsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassSection("Global", symbol: "command") {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Start measuring").font(.system(size: 13))
                        Text("Works from any app. Press it again, or Esc, to finish.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShortcutRecorder(shortcut: $settings.measureShortcut, isUnavailable: state.shortcutUnavailable)
                }
            }
            GlassSection("While Measuring", symbol: "keyboard") {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(ShortcutSheet.groups.flatMap(\.1), id: \.0) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.0)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .frame(width: 100, alignment: .leading)
                            Text(item.1)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var aboutPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassSection("PixelMark \(Bundle.main.shortVersion)", symbol: "sparkles") {
                Text("A free, open source screen ruler for macOS. Hover to see distances to the nearest edges, drag to box anything, and copy exact sizes in points or pixels.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Inspired by PixelSnap. Made by Josh Hamilton and released under the MIT License.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(StatusBarController.repositoryURL)
                    } label: {
                        Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(.glass)
                    Button {
                        NSWorkspace.shared.open(StatusBarController.repositoryURL.appendingPathComponent("issues"))
                    } label: {
                        Label("Report an Issue", systemImage: "ladybug")
                    }
                    .buttonStyle(.glass)
                    Button {
                        AppCoordinator.shared?.showWelcome()
                    } label: {
                        Label("Welcome Tour", systemImage: "hand.wave")
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.small)
            }
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

struct PermissionBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.dashed.badge.record")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Recording is off")
                    .font(.system(size: 13, weight: .semibold))
                Text("PixelMark reads the pixels on screen to find edges. Nothing leaves your Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Allow…") { ScreenPermission.request() }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        }
        .padding(14)
        .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .rect(cornerRadius: 18))
    }
}

struct ColorChoice: View {
    @Binding var selection: MarkColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MarkColor.allCases) { color in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = color }
                } label: {
                    Circle()
                        .fill(color.color.gradient)
                        .frame(width: 20, height: 20)
                        .overlay {
                            Circle()
                                .strokeBorder(.white, lineWidth: selection == color ? 2 : 0)
                                .padding(selection == color ? -1 : 0)
                        }
                        .padding(3)
                        .overlay {
                            Circle().strokeBorder(color.color, lineWidth: selection == color ? 1.5 : 0)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.rawValue.capitalized)
            }
        }
    }
}

struct TabSwitch: View {
    @Binding var selection: SettingsTab

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    let selected = tab == selection
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selection = tab }
                    } label: {
                        Label(tab.title, systemImage: tab.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .glassEffect(selected ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: .capsule)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

struct GlassSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(_ title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 18))
        }
    }
}

struct SettingToggle: View {
    let title: String
    let detail: String?
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
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
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(recorder.isRecording || shortcut == nil ? .secondary : .primary)
                    .frame(minWidth: 108)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(
                recorder.isRecording ? .regular.tint(.accentColor.opacity(0.35)).interactive() : .regular.interactive(),
                in: .capsule
            )

            Button {
                shortcut = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Clear shortcut")
            .opacity(shortcut != nil && !recorder.isRecording ? 1 : 0)
            .disabled(shortcut == nil || recorder.isRecording)
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

/// Frosted window background with a soft wash of the mark color behind the glass.
struct AmbientBackground: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .underWindowBackground)
            RadialGradient(
                colors: [settings.markColor.color.opacity(0.22), .clear],
                center: .topLeading, startRadius: 0, endRadius: 420
            )
            RadialGradient(
                colors: [Color(red: 0.36, green: 0.3, blue: 0.95).opacity(0.18), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 460
            )
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
