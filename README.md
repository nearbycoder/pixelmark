<img src="docs/assets/og.png" alt="PixelMark: measure anything on your screen">

# PixelMark

A free, open source screen ruler for macOS. Press **⇧⌘2**, hover, and PixelMark shows the distance to the nearest edges in every direction. Drag a box and it snaps to the content inside. Inspired by [PixelSnap](https://pixelsnap.com).

**[Download PixelMark](https://github.com/nearbycoder/pixelmark/releases/latest/download/PixelMark.dmg)** · [Website](https://nearbycoder.github.io/pixelmark/) · [Watch the tour](https://nearbycoder.github.io/pixelmark/#tour) · requires macOS 26 Tahoe or later · signed with a Developer ID and notarized by Apple

## Features

- **Hover to measure.** Lines run from the pointer to the nearest edge in each direction, labeled with the width and height.
- **Boxes that snap.** Drag around anything and the box shrinks to fit the content. Hold ⇧ for a free box. Show aspect ratios (A) and positions (P); boxes of the same size get an = mark.
- **Spacing and padding.** Hold ⌥ over a box to see the gaps to its neighbors, or ⌃ to see the padding around the content inside it. Aligned boxes get alignment lines.
- **Point to point.** ⌘-drag to measure the distance and angle between any two points (⇧ for 45° steps).
- **Guides, rulers and grid.** Press H or V for a guide (⇧ puts it through the middle of a box), R for rulers along the screen edges, and G for a layout grid that starts at the hovered box.
- **Loupe and colors.** A magnified view of the pixels under the pointer; Z zooms it. C copies the color as hex, RGB, HSL or SwiftUI (⇧C switches), and K checks the WCAG contrast between two colors.
- **Copy formats.** ⌘C copies `320 × 48`, `320x48`, CSS or a SwiftUI `.frame`; ⌥⌘C copies every measurement as a list.
- **Screenshots.** ⌘S saves and copies the screen with every measurement on it; ⇧⌘S crops to the measured area.
- **Points or pixels,** adjustable edge tolerance, and every connected display.

PixelMark takes one still image of each display when you start measuring and discards it when you finish. It has no network access, analytics or account.

## Shortcuts

| Key | Action |
| --- | --- |
| ⇧⌘2 | Start measuring (customizable) |
| Drag / ⇧ Drag | Box that snaps to content / free box |
| ⌘ Drag | Line between two points |
| Click or Space | Pin the current measurement |
| ⌥ / ⌃ | Spacing around / padding inside the hovered box |
| H / V | Horizontal / vertical guide (⇧ through the box's center) |
| R / G | Rulers / layout grid |
| A / P | Aspect ratios / positions |
| ⌘C / ⌥⌘C | Copy dimensions / every measurement |
| C / ⇧C | Copy color / change color format |
| K | Check contrast against the color under the pointer |
| ⌘S / ⇧⌘S | Screenshot / cropped screenshot |
| [ / ] | Edge tolerance |
| U / L / Z / M | Points ↔ pixels / loupe / loupe zoom / mark color |
| Arrow keys | Nudge 1 px (⇧ for 10) |
| ⌫ or ⌘Z / ⇧⌘Z / X | Remove hovered or last mark / put it back / clear all |
| ? | Show every shortcut |
| Esc | Done |

## Building

```sh
brew install xcodegen
xcodegen generate
open PixelMark.xcodeproj
```

Run the tests with `xcodebuild test -project PixelMark.xcodeproj -scheme PixelMark -destination 'platform=macOS'`.

`./Scripts/release.sh` archives, signs with Developer ID, notarizes and packages a DMG; `./Scripts/release.sh publish` also tags the version and creates a GitHub release. Bump the version in `Resources/Info.plist` first.

Debug builds can drive the overlay from a script for screenshots, without covering your screen: `./Scripts/shoot.sh <backdrop.png> <out.png> "drag 100 100 300 200; option 150 150"`. `Scripts/make-demo-backdrop.swift` renders the mock desktop used on the website, and `./Scripts/record-demo.sh` records the feature tour video (`docs/assets/demo.mp4`) the same way.

## License

[MIT](LICENSE) © 2026 Josh Hamilton. PixelSnap is a trademark of its owners; PixelMark is an independent project.
