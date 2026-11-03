import CoreGraphics

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
        let r = PixelRect(
            minX: max(0, rect.minX), minY: max(0, rect.minY),
            maxX: min(width, rect.maxX), maxY: min(height, rect.maxY)
        )
        guard !r.isEmpty else { return nil }

        return pixels.withUnsafeBufferPointer { buffer -> PixelRect? in
            let corners = [
                buffer[r.minY * width + r.minX], buffer[r.minY * width + r.maxX - 1],
                buffer[(r.maxY - 1) * width + r.minX], buffer[(r.maxY - 1) * width + r.maxX - 1],
            ]
            let background = corners.max { a, b in
                corners.filter { !Self.differs($0, a, tolerance: tolerance) }.count
                    < corners.filter { !Self.differs($0, b, tolerance: tolerance) }.count
            }!

            func rowHasContent(_ y: Int) -> Bool {
                let base = y * width
                for x in r.minX..<r.maxX where Self.differs(buffer[base + x], background, tolerance: tolerance) { return true }
                return false
            }
            func columnHasContent(_ x: Int, _ y0: Int, _ y1: Int) -> Bool {
                for y in y0..<y1 where Self.differs(buffer[y * width + x], background, tolerance: tolerance) { return true }
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
}
