// Renders a mock desktop (wallpaper, menu bar and an app window) for screenshots of PixelMark.
// Usage: swift Scripts/make-demo-backdrop.swift <output.png> [width height]
// Point size defaults to 1920 × 1080; the image is rendered at 2x.
import AppKit
import SwiftUI

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: make-demo-backdrop.swift <output.png> [width height]")
    exit(1)
}
let size = CGSize(
    width: args.count >= 4 ? Double(args[2])! : 1920,
    height: args.count >= 4 ? Double(args[3])! : 1080
)

let indigo = Color(red: 0.36, green: 0.33, blue: 0.95)
let ink = Color(red: 0.09, green: 0.10, blue: 0.16)
let soft = Color(red: 0.42, green: 0.45, blue: 0.55)
let line = Color(red: 0.90, green: 0.91, blue: 0.94)

struct Desktop: View {
    var body: some View {
        ZStack(alignment: .top) {
            wallpaper
            menuBar
            AppWindow()
                .frame(width: 1180, height: 720)
                .position(x: size.width / 2, y: size.height / 2 + 24)
        }
        .frame(width: size.width, height: size.height)
    }

    private var wallpaper: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.40, blue: 0.47), Color(red: 0.15, green: 0.17, blue: 0.21)], startPoint: .top, endPoint: .bottom)
            Ellipse().fill(Color.white.opacity(0.10)).frame(width: 1800, height: 700).blur(radius: 200).offset(y: -420)
        }
    }

    private var menuBar: some View {
        HStack(spacing: 20) {
            Image(systemName: "apple.logo").font(.system(size: 15, weight: .semibold))
            Text("Orbit").font(.system(size: 13, weight: .bold))
            ForEach(["File", "Edit", "View", "Window", "Help"], id: \.self) { Text($0).font(.system(size: 13)) }
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("Mon Nov 2  9:41 AM").font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .frame(height: 32)
        .background(.black.opacity(0.22))
    }
}

struct AppWindow: View {
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(line).frame(width: 1)
            content
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .compositingGroup()
        .shadow(color: .black.opacity(0.45), radius: 50, y: 24)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.85)).frame(width: 12, height: 12) }
            }
            .padding(.bottom, 26)
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8).fill(indigo).frame(width: 30, height: 30)
                    .overlay(Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.white).font(.system(size: 14)))
                Text("Orbit").font(.system(size: 17, weight: .bold)).foregroundStyle(ink)
            }
            .padding(.bottom, 20)
            ForEach(Array(["Overview", "Projects", "Team", "Reports", "Settings"].enumerated()), id: \.offset) { index, item in
                HStack(spacing: 10) {
                    Image(systemName: ["square.grid.2x2.fill", "folder.fill", "person.2.fill", "chart.bar.fill", "gearshape.fill"][index])
                        .frame(width: 18)
                    Text(item).font(.system(size: 14, weight: index == 0 ? .semibold : .medium))
                    Spacer()
                }
                .foregroundStyle(index == 0 ? indigo : soft)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(index == 0 ? indigo.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer()
            HStack(spacing: 10) {
                Circle().fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom)).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ava Chen").font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                    Text("Design Lead").font(.system(size: 11)).foregroundStyle(soft)
                }
            }
        }
        .padding(20)
        .frame(width: 236)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.975, green: 0.977, blue: 0.985))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Good morning, Ava").font(.system(size: 30, weight: .bold)).foregroundStyle(ink)
                    Text("Here’s what’s happening across your projects today.").font(.system(size: 15)).foregroundStyle(soft)
                }
                Spacer()
                Text("New Project")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 140, height: 44)
                    .background(indigo, in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 24) {
                stat("Active projects", "24", "+3 this week", .green)
                stat("Open tasks", "128", "12 due today", .orange)
                stat("Team velocity", "92%", "+8% vs last sprint", indigo)
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Weekly activity").font(.system(size: 17, weight: .semibold)).foregroundStyle(ink)
                    Spacer()
                    Text("Last 7 days").font(.system(size: 13, weight: .medium)).foregroundStyle(soft)
                        .padding(.horizontal, 12).frame(height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(line))
                }
                HStack(alignment: .bottom, spacing: 28) {
                    ForEach(Array([0.45, 0.7, 0.55, 0.9, 0.62, 0.38, 0.75].enumerated()), id: \.offset) { index, value in
                        VStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(index == 3 ? indigo : indigo.opacity(0.2))
                                .frame(width: 64, height: 210 * value)
                            Text(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][index]).font(.system(size: 12, weight: .medium)).foregroundStyle(soft)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(line))
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stat(_ title: String, _ value: String, _ note: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(soft)
            Text(value).font(.system(size: 34, weight: .bold)).foregroundStyle(ink)
            Text(note).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                .padding(.horizontal, 8).frame(height: 22)
                .background(tint.opacity(0.12), in: Capsule())
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.975, green: 0.977, blue: 0.985), in: RoundedRectangle(cornerRadius: 16))
    }
}

let output = URL(fileURLWithPath: args[1])
MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Desktop().environment(\.colorScheme, .light))
    renderer.scale = 2
    guard let image = renderer.cgImage,
          let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)
    else {
        print("Rendering failed")
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("Wrote \(output.path) (\(image.width) × \(image.height))")
}
