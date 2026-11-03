import SwiftUI

@MainActor
final class HUDModel: ObservableObject {
    struct Toast: Equatable, Identifiable {
        let id = UUID()
        var text: String
        var symbol: String
    }

    @Published var activeScreen: CGDirectDisplayID = 0
    @Published var atTop = false
    @Published var showHelp = false
    @Published var toast: Toast?
    private var toastTask: Task<Void, Never>?

    func showToast(_ text: String, symbol: String) {
        withAnimation(.snappy(duration: 0.25)) { toast = Toast(text: text, symbol: symbol) }
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) { self?.toast = nil }
        }
    }

    #if DEBUG
    /// Names the feature being shown in the demo video.
    struct Caption: Equatable {
        let id = UUID()
        var keys: [String]
        var text: String
    }

    @Published var caption: Caption?

    func showCaption(keys: [String], text: String) {
        withAnimation(.smooth(duration: 0.35)) { caption = Caption(keys: keys, text: text) }
    }
    #endif

    func moveBar(toTop: Bool) {
        guard atTop != toTop else { return }
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { atTop = toTop }
    }
}

/// The glass helper bar, toasts and shortcut sheet floating over the measuring overlay.
struct HUDView: View {
    @ObservedObject var model: HUDModel
    @ObservedObject private var settings = AppSettings.shared
    let screenID: CGDirectDisplayID
    let topInset: CGFloat
    let regions: HitRegions

    private var isActive: Bool { model.activeScreen == screenID }

    var body: some View {
        ZStack {
            if isActive {
                VStack(spacing: 10) {
                    if model.atTop {
                        bar
                        toast
                    } else {
                        toast
                        bar
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.atTop ? .top : .bottom)
                .padding(.top, max(topInset, 30) + 10)
                .padding(.bottom, 28)

                #if DEBUG
                if let caption = model.caption {
                    CaptionView(caption: caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 64)
                }
                #endif

                if model.showHelp {
                    // Dims the busy screen behind the sheet; clicking it closes the sheet.
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture(perform: closeHelp)
                        .reportFrame("scrim", to: regions)
                        .transition(.opacity)
                    ShortcutSheet(onClose: closeHelp)
                        .reportFrame("help", to: regions)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isActive) { _, active in
            if !active { ["bar", "help", "scrim"].forEach { regions.set($0, nil) } }
        }
    }

    private func closeHelp() {
        withAnimation(.snappy) { model.showHelp = false }
    }

    @ViewBuilder
    private var toast: some View {
        if let toast = model.toast {
            Label(toast.text, systemImage: toast.symbol)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)
                .id(toast.id)
                .transition(.move(edge: model.atTop ? .top : .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
        }
    }

    @ViewBuilder
    private var bar: some View {
        if settings.showHelperBar {
            HStack(spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    hints(full: true)
                    hints(full: false)
                    EmptyView()
                }
                .frame(maxWidth: 640)

                Divider().frame(height: 18)

                Button(action: { AppCoordinator.shared?.session?.toggleUnit() }) {
                    Text(settings.unit.suffix)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .frame(minWidth: 22)
                }
                .buttonStyle(.plain)
                .help("Switch between points and pixels (U)")
                .accessibilityLabel(settings.unit == .points ? "Measuring in points" : "Measuring in pixels")

                toleranceControl

                Button("Done") { AppCoordinator.shared?.session?.end() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .help("Finish measuring (Esc)")
            }
            .padding(.horizontal, 18)
            .frame(height: 40)
            .glassEffect(.regular, in: .capsule)
            .fixedSize()
            .reportFrame("bar", to: regions)
            .transition(.opacity)
        }
    }

    private func hints(full: Bool) -> some View {
        HStack(spacing: 14) {
            KeyHint(keys: ["Drag"], label: "box")
            KeyHint(keys: ["Click"], label: "pin")
            KeyHint(keys: ["⌥"], label: "spacing")
            if full {
                KeyHint(keys: ["⌘C"], label: "copy")
                KeyHint(keys: ["⌘S"], label: "screenshot")
            }
            KeyHint(keys: ["?"], label: "all shortcuts")
        }
        .fixedSize()
    }

    private var toleranceControl: some View {
        HStack(spacing: 2) {
            Button(action: { AppCoordinator.shared?.session?.adjustTolerance(-2) }) {
                Image(systemName: "minus").frame(width: 20, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Lower tolerance")
            Text("Tolerance \(settings.tolerance)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(settings.tolerance)))
            Button(action: { AppCoordinator.shared?.session?.adjustTolerance(2) }) {
                Image(systemName: "plus").frame(width: 20, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Raise tolerance")
        }
        .font(.system(size: 10, weight: .semibold))
        .help("How different two colors must be to count as an edge ([ and ])")
    }
}

#if DEBUG
private struct CaptionView: View {
    let caption: HUDModel.Caption

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                ForEach(caption.keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.horizontal, 9)
                        .frame(minWidth: 32, minHeight: 32)
                        .background(.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            Text(caption.text)
                .font(.system(size: 19, weight: .medium))
        }
        .padding(.leading, 10)
        .padding(.trailing, 22)
        .frame(height: 52)
        .glassEffect(.regular, in: .capsule)
        .id(caption.id)
        .transition(.opacity.combined(with: .offset(y: -8)))
    }
}
#endif

struct KeyHint: View {
    let keys: [String]
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { Keycap(text: $0) }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Every overlay shortcut, toggled with ?.
struct ShortcutSheet: View {
    let onClose: () -> Void

    static let groups: [(String, [(String, String)])] = [
        ("Measure", [
            ("Move", "Distances to the nearest edges"),
            ("Drag", "Box that snaps to the content inside"),
            ("⇧ Drag", "Free box (no snapping)"),
            ("⌘ Drag", "Line between two points (⇧ for 45°)"),
            ("Click  Space", "Pin the current measurement"),
            ("⌥", "Spacing around the hovered box"),
            ("⌃", "Padding inside the hovered box"),
            ("H  V", "Add a horizontal / vertical guide"),
            ("⇧H  ⇧V", "Guide through the box's center"),
            ("← → ↑ ↓", "Nudge 1 px (⇧ for 10)"),
        ]),
        ("Act", [
            ("⌘C", "Copy dimensions"),
            ("⌥⌘C", "Copy every measurement"),
            ("C", "Copy the color under the pointer"),
            ("⇧C", "Change the color format"),
            ("K", "Check contrast against this color"),
            ("⌘S", "Screenshot with measurements"),
            ("⇧⌘S", "Screenshot of just the measured area"),
            ("⌫  ⌘Z", "Remove the hovered or last mark"),
            ("⇧⌘Z", "Put back what you removed"),
            ("X", "Clear everything"),
        ]),
        ("View", [
            ("R", "Rulers"),
            ("G", "Layout grid (from the hovered box)"),
            ("A", "Aspect ratios"),
            ("P", "Positions"),
            ("Z", "Loupe zoom"),
            ("L", "Show or hide the loupe"),
            ("M", "Mark color"),
            ("U", "Points ↔ pixels"),
            ("[  ]", "Edge tolerance (⇧ for bigger steps)"),
            ("Esc", "Done"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Shortcuts")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
            }
            HStack(alignment: .top, spacing: 36) {
                ForEach(Self.groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.0)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(group.1, id: \.0) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(item.0)
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 78, alignment: .leading)
                                Text(item.1)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                    }
                }
            }
        }
        .padding(26)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .fixedSize()
    }
}

extension View {
    /// Tells the hosting view where this element is, so clicks elsewhere fall through to the overlay.
    func reportFrame(_ key: String, to regions: HitRegions) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { regions.set(key, $0) }
            .onDisappear { regions.set(key, nil) }
    }
}
