import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController {
    private var window: NSWindow?
    private var timer: Timer?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: WelcomeView(onFinish: { [weak self] in self?.finish() }))
            hosting.sizingOptions = [.preferredContentSize]
            let window = GlassWindow(contentViewController: hosting)
            window.title = "Welcome to PixelMark"
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

        // Pick up the permission as soon as it's granted in System Settings.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                AppState.shared.refreshPermission()
                if self?.window?.isVisible != true { self?.timer?.invalidate() }
            }
        }
    }

    private func finish() {
        AppSettings.shared.hasOnboarded = true
        window?.close()
        timer?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AppCoordinator.shared?.startMeasuring()
        }
    }
}

struct WelcomeView: View {
    let onFinish: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var state = AppState.shared
    @State private var askedForPermission = false

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                    .shadow(color: settings.markColor.color.opacity(0.35), radius: 18, y: 6)
                Text("Welcome to PixelMark")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Measure anything on your screen in one keystroke.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            MeasureDemo()
                .frame(height: 170)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))

            VStack(spacing: 10) {
                StepRow(number: 1, title: "Allow Screen Recording", detail: "PixelMark reads pixels to find edges. Nothing leaves your Mac.", done: state.hasScreenPermission) {
                    if state.hasScreenPermission {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                    } else if askedForPermission {
                        HStack(spacing: 6) {
                            Button("Open Settings") { ScreenPermission.openSystemSettings() }
                                .buttonStyle(.glass)
                            Button("Relaunch") { ScreenPermission.relaunch() }
                                .buttonStyle(.glassProminent)
                                .help("macOS applies the permission after PixelMark restarts")
                        }
                        .controlSize(.small)
                    } else {
                        Button("Allow…") {
                            askedForPermission = true
                            ScreenPermission.request()
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                    }
                }
                StepRow(number: 2, title: "Pick your shortcut", detail: "Press it from any app to start. Esc finishes.", done: settings.measureShortcut != nil) {
                    ShortcutRecorder(shortcut: $settings.measureShortcut, isUnavailable: state.shortcutUnavailable)
                }
                StepRow(number: 3, title: "Launch at login", detail: "Keep PixelMark ready in the menu bar.", done: settings.launchAtLogin) {
                    Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            Button(action: onFinish) {
                HStack(spacing: 8) {
                    Text(state.hasScreenPermission ? "Start Measuring" : "Try It Anyway")
                    if let shortcut = settings.measureShortcut {
                        Text(shortcut.displayString)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .opacity(0.75)
                    }
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!state.hasScreenPermission && !DemoSnapshot.isEnabled)
        }
        .padding(.horizontal, 30)
        .padding(.top, 44)
        .padding(.bottom, 28)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background { AmbientBackground().ignoresSafeArea() }
        .tint(settings.markColor.color)
    }
}

private struct StepRow<Accessory: View>: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(done ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(.tint))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

/// A looping sketch of what measuring looks like: a crosshair gliding over a mock window.
private struct MeasureDemo: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                draw(in: &ctx, size: size, time: context.date.timeIntervalSinceReferenceDate)
            }
        }
        .clipShape(.rect(cornerRadius: 22))
        .accessibilityHidden(true)
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let accent = settings.markColor.color
        let card = CGRect(x: size.width / 2 - 170, y: 18, width: 340, height: size.height - 36)
        ctx.fill(Path(roundedRect: card, cornerRadius: 14), with: .color(.primary.opacity(0.07)))

        let avatar = CGRect(x: card.minX + 20, y: card.minY + 18, width: 34, height: 34)
        ctx.fill(Path(ellipseIn: avatar), with: .color(.primary.opacity(0.18)))
        for (i, width) in [110.0, 70.0].enumerated() {
            let line = CGRect(x: avatar.maxX + 12, y: avatar.minY + 6 + Double(i) * 15, width: width, height: 8)
            ctx.fill(Path(roundedRect: line, cornerRadius: 4), with: .color(.primary.opacity(0.14)))
        }
        let button = CGRect(x: card.minX + 20, y: card.maxY - 46, width: 110, height: 28)
        ctx.fill(Path(roundedRect: button, cornerRadius: 8), with: .color(accent.opacity(0.85)))

        // The pointer drifts through the card's empty right side, so the lines run edge to edge.
        let t = time * 0.7
        let point = CGPoint(x: card.minX + 250 + cos(t) * 40, y: card.midY + sin(t * 1.4) * 22)
        let left = card.minX, right = card.maxX
        let top = card.minY, bottom = card.maxY

        var lines = Path()
        lines.move(to: CGPoint(x: left, y: point.y)); lines.addLine(to: CGPoint(x: right, y: point.y))
        lines.move(to: CGPoint(x: point.x, y: top)); lines.addLine(to: CGPoint(x: point.x, y: bottom))
        for x in [left + 0.5, right - 0.5] {
            lines.move(to: CGPoint(x: x, y: point.y - 4)); lines.addLine(to: CGPoint(x: x, y: point.y + 4))
        }
        for y in [top + 0.5, bottom - 0.5] {
            lines.move(to: CGPoint(x: point.x - 4, y: y)); lines.addLine(to: CGPoint(x: point.x + 4, y: y))
        }
        ctx.stroke(lines, with: .color(accent), lineWidth: 1)

        let label = Text("\(Int(right - left)) × \(Int(bottom - top))")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
        let resolved = ctx.resolve(label)
        let textSize = resolved.measure(in: size)
        let pill = CGRect(x: point.x - textSize.width - 26, y: point.y + 12, width: textSize.width + 14, height: textSize.height + 7)
        ctx.fill(Path(roundedRect: pill, cornerRadius: 5.5), with: .color(accent))
        ctx.draw(resolved, at: CGPoint(x: pill.midX, y: pill.midY))
    }
}
