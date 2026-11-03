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

                if model.showHelp {
                    ShortcutSheet { withAnimation(.snappy) { model.showHelp = false } }
                        .reportFrame("help", to: regions)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(settings.markColor.color)
        .onChange(of: isActive) { _, active in
            if !active { ["bar", "help", "toast"].forEach { regions.set($0, nil) } }
        }
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
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        hints(compact: false)
                        hints(compact: true)
                        EmptyView()
                    }
                    .frame(maxWidth: 820)

                    Button(action: { AppCoordinator.shared?.session?.toggleUnit() }) {
                        Text(settings.unit.suffix)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .frame(width: 34, height: 30)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .help("Switch between points and pixels (U)")

                    toleranceControl

                    Button(action: { AppCoordinator.shared?.session?.end() }) {
                        Text("Done")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(settings.markColor.nsColor.prefersDarkText ? .black : .white)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(settings.markColor.color).interactive(), in: .capsule)
                    .help("Finish measuring (Esc)")
                }
                .padding(6)
                .glassEffect(.regular, in: .capsule)
            }
            .fixedSize()
            .reportFrame("bar", to: regions)
            .transition(.opacity)
        }
    }

    private func hints(compact: Bool) -> some View {
        HStack(spacing: compact ? 10 : 14) {
            Image(nsImage: StatusBarController.menuBarIcon())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(settings.markColor.color.gradient, in: Circle())
            KeyHint(keys: ["drag"], label: "Measure", compact: compact)
            KeyHint(keys: ["click"], label: "Pin", compact: compact)
            KeyHint(keys: ["⌥"], label: "Spacing", compact: compact)
            if !compact {
                KeyHint(keys: ["H", "V"], label: "Guides", compact: compact)
                KeyHint(keys: ["C"], label: "Color", compact: compact)
            }
            KeyHint(keys: ["⌘C"], label: "Copy", compact: compact)
            KeyHint(keys: ["⌘S"], label: "Save", compact: compact)
            KeyHint(keys: ["?"], label: "More", compact: compact)
        }
        .padding(.leading, 0)
        .padding(.trailing, 4)
        .fixedSize()
    }

    private var toleranceControl: some View {
        HStack(spacing: 0) {
            Button(action: { AppCoordinator.shared?.session?.adjustTolerance(-2) }) {
                Image(systemName: "minus").frame(width: 26, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(spacing: -1) {
                Text("\(settings.tolerance)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(settings.tolerance)))
                Text("tolerance")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50)
            Button(action: { AppCoordinator.shared?.session?.adjustTolerance(2) }) {
                Image(systemName: "plus").frame(width: 26, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11, weight: .bold))
        .glassEffect(.regular.interactive(), in: .capsule)
        .help("How different two colors must be to count as an edge ([ and ])")
    }
}

struct KeyHint: View {
    let keys: [String]
    let label: String
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { Keycap(text: $0) }
            }
            if !compact {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .help(label)
    }
}

struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
            }
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
            ("Click  Space", "Pin the current measurement"),
            ("⌥", "Spacing around the hovered box"),
            ("H  V", "Add a horizontal / vertical guide"),
            ("← → ↑ ↓", "Nudge 1 px (⇧ for 10)"),
        ]),
        ("Act", [
            ("⌘C", "Copy dimensions"),
            ("C", "Copy the color under the pointer"),
            ("⌘S", "Screenshot with measurements"),
            ("⇧⌘S", "Screenshot of just the measured area"),
            ("⌫  ⌘Z", "Remove the hovered or last mark"),
            ("X", "Clear everything"),
        ]),
        ("Adjust", [
            ("[  ]", "Edge tolerance (⇧ for bigger steps)"),
            ("U", "Points ↔ pixels"),
            ("L", "Show or hide the loupe"),
            ("Esc", "Done"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Shortcuts")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
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
            HStack(alignment: .top, spacing: 28) {
                ForEach(Self.groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.0.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.tint)
                        ForEach(group.1, id: \.0) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(item.0)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .frame(width: 78, alignment: .leading)
                                Text(item.1)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(width: 290, alignment: .leading)
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
