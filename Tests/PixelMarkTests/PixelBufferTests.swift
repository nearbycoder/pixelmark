import XCTest
@testable import PixelMark

final class PixelBufferTests: XCTestCase {
    private let white: UInt32 = 0xFFFFFF
    private let black: UInt32 = 0x000000
    private let gray: UInt32 = 0xF4F4F4

    /// A white canvas with filled rectangles (x, y, width, height, color).
    private func canvas(width: Int, height: Int, rects: [(Int, Int, Int, Int, UInt32)] = []) -> PixelBuffer {
        var pixels = [UInt32](repeating: white, count: width * height)
        for (x, y, w, h, color) in rects {
            for row in y..<(y + h) {
                for column in x..<(x + w) { pixels[row * width + column] = color }
            }
        }
        return PixelBuffer(width: width, height: height, pixels: pixels)
    }

    func testSpanStopsAtEdges() {
        // A black box from (10, 5) to (29, 19).
        let buffer = canvas(width: 40, height: 30, rects: [(10, 5, 20, 15, black)])
        XCTAssertEqual(buffer.span(x: 15, y: 10, tolerance: 0), EdgeSpan(left: 10, right: 29, top: 5, bottom: 19))
        XCTAssertEqual(buffer.span(x: 15, y: 10, tolerance: 0)?.width, 20)
        XCTAssertEqual(buffer.span(x: 15, y: 10, tolerance: 0)?.height, 15)
    }

    func testSpanReachesScreenBounds() {
        let buffer = canvas(width: 40, height: 30, rects: [(10, 5, 20, 15, black)])
        // Left of the box, the white run spans from the screen edge to the box.
        XCTAssertEqual(buffer.span(x: 3, y: 10, tolerance: 0), EdgeSpan(left: 0, right: 9, top: 0, bottom: 29))
    }

    func testToleranceIgnoresSubtleChanges() {
        // A faint gray stripe at x = 20 inside white.
        let buffer = canvas(width: 40, height: 10, rects: [(20, 0, 1, 10, gray)])
        XCTAssertEqual(buffer.span(x: 5, y: 5, tolerance: 0)?.right, 19)
        XCTAssertEqual(buffer.span(x: 5, y: 5, tolerance: 12)?.right, 39)
    }

    func testContentBoundsShrinksToContent() {
        let buffer = canvas(width: 100, height: 80, rects: [(30, 20, 25, 10, black), (40, 35, 5, 5, black)])
        let bounds = buffer.contentBounds(in: PixelRect(minX: 5, minY: 5, maxX: 90, maxY: 70), tolerance: 0)
        XCTAssertEqual(bounds, PixelRect(minX: 30, minY: 20, maxX: 55, maxY: 40))
    }

    func testContentBoundsOfFlatRegionIsNil() {
        let buffer = canvas(width: 50, height: 50)
        XCTAssertNil(buffer.contentBounds(in: PixelRect(minX: 0, minY: 0, maxX: 50, maxY: 50), tolerance: 0))
    }

    func testContentBoundsInsideADarkElement() {
        // Dragging inside a black card around white text finds the text.
        let buffer = canvas(width: 100, height: 100, rects: [(0, 0, 100, 100, black), (40, 45, 20, 8, white)])
        let bounds = buffer.contentBounds(in: PixelRect(minX: 10, minY: 10, maxX: 90, maxY: 90), tolerance: 0)
        XCTAssertEqual(bounds, PixelRect(minX: 40, minY: 45, maxX: 60, maxY: 53))
    }

    func testRunCountsMatchingPixels() {
        let buffer = canvas(width: 40, height: 10, rects: [(30, 0, 10, 10, black)])
        XCTAssertEqual(buffer.run(fromX: 10, y: 5, dx: 1, dy: 0, tolerance: 0), 20)
        XCTAssertEqual(buffer.run(fromX: 10, y: 5, dx: -1, dy: 0, tolerance: 0), 11)
    }

    func testHex() {
        XCTAssertEqual(PixelBuffer.hex(0x12AB_EF), "#12ABEF")
    }

    func testImageRoundTripKeepsColors() throws {
        // Red, green, blue and a gray in a 2 × 2 sRGB image.
        let colors: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 30, 60, 90, 255]
        let provider = try XCTUnwrap(CGDataProvider(data: Data(colors) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let buffer = try XCTUnwrap(PixelBuffer(image: image))
        XCTAssertEqual(PixelBuffer.hex(buffer.color(x: 0, y: 0)), "#FF0000")
        XCTAssertEqual(PixelBuffer.hex(buffer.color(x: 1, y: 0)), "#00FF00")
        XCTAssertEqual(PixelBuffer.hex(buffer.color(x: 0, y: 1)), "#0000FF")
        XCTAssertEqual(PixelBuffer.hex(buffer.color(x: 1, y: 1)), "#1E3C5A")
    }

    func testFormatting() {
        XCTAssertEqual(OverlayScene.format(160.5, scale: 2, unit: .points), "160.5")
        XCTAssertEqual(OverlayScene.format(160.5, scale: 2, unit: .pixels), "321")
        XCTAssertEqual(OverlayScene.format(48, scale: 2, unit: .points), "48")
    }
}
