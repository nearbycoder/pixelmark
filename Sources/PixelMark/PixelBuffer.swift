import CoreGraphics
import Foundation

/// An integer rectangle in pixel space (top-left origin, inclusive min, exclusive max).
struct PixelRect: Equatable {
    var minX: Int, minY: Int, maxX: Int, maxY: Int

    var width: Int { maxX - minX }
    var height: Int { maxY - minY }
    var isEmpty: Bool { width <= 0 || height <= 0 }
}

/// The run of same-colored pixels around a point, in each direction.
struct EdgeSpan: Equatable {
    /// First pixel that matches on each side (inclusive), so the span is `right - left + 1` wide.
    var left: Int, right: Int, top: Int, bottom: Int

    var width: Int { right - left + 1 }
    var height: Int { bottom - top + 1 }
}

/// A frozen RGBA copy of a screenshot that can find edges around a point, or the bounds of content in a region.
final class PixelBuffer {
    let width: Int
    let height: Int
    private let pixels: [UInt32]

    init(width: Int, height: Int, pixels: [UInt32]) {
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    convenience init?(image: CGImage) {
        let width = image.width
        let height = image.height
        var pixels = [UInt32](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }

    /// Packed 0x__RRGGBB (top-left origin).
    @inline(__always)
    func color(x: Int, y: Int) -> UInt32 {
        pixels[y * width + x]
    }

    func contains(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    /// Two colors differ when any channel is more than `tolerance` apart.
    @inline(__always)
    static func differs(_ a: UInt32, _ b: UInt32, tolerance: Int) -> Bool {
        let r = abs(Int((a >> 16) & 0xFF) - Int((b >> 16) & 0xFF))
        let g = abs(Int((a >> 8) & 0xFF) - Int((b >> 8) & 0xFF))
        let bl = abs(Int(a & 0xFF) - Int(b & 0xFF))
        return r > tolerance || g > tolerance || bl > tolerance
    }

    /// Walks out from (x, y) in all four directions while pixels match the starting color.
    func span(x: Int, y: Int, tolerance: Int) -> EdgeSpan? {
        guard contains(x: x, y: y) else { return nil }
        return pixels.withUnsafeBufferPointer { buffer in
            let row = y * width
            let start = buffer[row + x]

            var left = x
            while left > 0, !Self.differs(buffer[row + left - 1], start, tolerance: tolerance) { left -= 1 }
            var right = x
            while right < width - 1, !Self.differs(buffer[row + right + 1], start, tolerance: tolerance) { right += 1 }
            var top = y
            while top > 0, !Self.differs(buffer[(top - 1) * width + x], start, tolerance: tolerance) { top -= 1 }
            var bottom = y
            while bottom < height - 1, !Self.differs(buffer[(bottom + 1) * width + x], start, tolerance: tolerance) { bottom += 1 }

            return EdgeSpan(left: left, right: right, top: top, bottom: bottom)
        }
    }

    /// How many matching pixels follow `(x, y)` in a direction before the color changes, starting with that pixel's color.
    func run(fromX x: Int, y: Int, dx: Int, dy: Int, tolerance: Int) -> Int {
        guard contains(x: x, y: y) else { return 0 }
        return pixels.withUnsafeBufferPointer { buffer in
            let start = buffer[y * width + x]
            var cx = x, cy = y, count = 0
            while true {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < width, ny < height,
                      !Self.differs(buffer[ny * width + nx], start, tolerance: tolerance) else { break }
                cx = nx; cy = ny; count += 1
            }
            return count + 1
        }
    }

    /// Shrinks `rect` to the tightest box around anything that differs from the region's background
    /// (the most common corner color). Returns nil when the region is a single flat color.
    func contentBounds(in rect: PixelRect, tolerance: Int) -> PixelRect? {
        let r = clamped(rect)
        guard !r.isEmpty else { return nil }
        let corners = [color(x: r.minX, y: r.minY), color(x: r.maxX - 1, y: r.minY), color(x: r.minX, y: r.maxY - 1), color(x: r.maxX - 1, y: r.maxY - 1)]
        return contentBounds(in: r, background: Self.mostCommon(corners, tolerance: tolerance), tolerance: tolerance)
    }

    /// The content inside a box, such as a button's label: the box is inset past its border and
    /// rounded corners, and the background is its fill, taken from the middle of each edge.
    func innerContentBounds(in rect: PixelRect, inset: Int, tolerance: Int) -> PixelRect? {
        let r = clamped(PixelRect(minX: rect.minX + inset, minY: rect.minY + inset, maxX: rect.maxX - inset, maxY: rect.maxY - inset))
        guard r.width > 2, r.height > 2 else { return nil }
        let midX = (r.minX + r.maxX) / 2, midY = (r.minY + r.maxY) / 2
        let edges = [color(x: midX, y: r.minY), color(x: midX, y: r.maxY - 1), color(x: r.minX, y: midY), color(x: r.maxX - 1, y: midY)]
        let fill = Self.mostCommon(edges, tolerance: tolerance)

        // Rounded corners leave the outside showing in the box's corners. Walking in diagonally covers
        // about 0.29 of the radius, which gives the square to skip in each corner.
        var diagonal = 0
        let limit = min(r.width, r.height) / 2
        for (x, y, dx, dy) in [(r.minX, r.minY, 1, 1), (r.maxX - 1, r.minY, -1, 1), (r.minX, r.maxY - 1, 1, -1), (r.maxX - 1, r.maxY - 1, -1, -1)] {
            var d = 0
            while d < limit, Self.differs(color(x: x + d * dx, y: y + d * dy), fill, tolerance: tolerance) { d += 1 }
            diagonal = max(diagonal, d)
        }
        guard diagonal < limit else { return nil }
        let corner = diagonal == 0 ? 0 : min(Int((Double(diagonal + inset) / 0.29).rounded(.up)) - inset, limit - 1)
        guard let content = contentBounds(in: r, background: fill, tolerance: tolerance, corner: corner),
              content != r else { return nil }
        return content
    }

    private func clamped(_ rect: PixelRect) -> PixelRect {
        PixelRect(minX: max(0, rect.minX), minY: max(0, rect.minY), maxX: min(width, rect.maxX), maxY: min(height, rect.maxY))
    }

    private static func mostCommon(_ colors: [UInt32], tolerance: Int) -> UInt32 {
        colors.max { a, b in
            colors.filter { !differs($0, a, tolerance: tolerance) }.count < colors.filter { !differs($0, b, tolerance: tolerance) }.count
        }!
    }

    /// - Parameter corner: size of the square in each corner to ignore.
    private func contentBounds(in r: PixelRect, background: UInt32, tolerance: Int, corner: Int = 0) -> PixelRect? {
        guard !r.isEmpty else { return nil }
        return pixels.withUnsafeBufferPointer { buffer -> PixelRect? in
            func rowHasContent(_ y: Int) -> Bool {
                let base = y * width
                let nearCorner = y < r.minY + corner || y >= r.maxY - corner
                let x0 = nearCorner ? r.minX + corner : r.minX, x1 = nearCorner ? r.maxX - corner : r.maxX
                guard x0 < x1 else { return false }
                for x in x0..<x1 where Self.differs(buffer[base + x], background, tolerance: tolerance) { return true }
                return false
            }
            func columnHasContent(_ x: Int, _ y0: Int, _ y1: Int) -> Bool {
                let nearCorner = x < r.minX + corner || x >= r.maxX - corner
                let from = nearCorner ? max(y0, r.minY + corner) : y0, to = nearCorner ? min(y1, r.maxY - corner) : y1
                guard from < to else { return false }
                for y in from..<to where Self.differs(buffer[y * width + x], background, tolerance: tolerance) { return true }
                return false
            }

            var top = r.minY
            while top < r.maxY, !rowHasContent(top) { top += 1 }
            guard top < r.maxY else { return nil }
            var bottom = r.maxY - 1
            while bottom > top, !rowHasContent(bottom) { bottom -= 1 }
            var left = r.minX
            while left < r.maxX, !columnHasContent(left, top, bottom + 1) { left += 1 }
            var right = r.maxX - 1
            while right > left, !columnHasContent(right, top, bottom + 1) { right -= 1 }

            return PixelRect(minX: left, minY: top, maxX: right + 1, maxY: bottom + 1)
        }
    }

    static func hex(_ color: UInt32) -> String {
        String(format: "#%02X%02X%02X", (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF)
    }

    /// WCAG 2 contrast ratio between two colors, from 1 to 21.
    static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ c: UInt32) -> Double {
            func channel(_ v: UInt32) -> Double {
                let s = Double(v & 0xFF) / 255
                return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(c >> 16) + 0.7152 * channel(c >> 8) + 0.0722 * channel(c)
        }
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
