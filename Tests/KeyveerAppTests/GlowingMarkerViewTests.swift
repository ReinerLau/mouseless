import AppKit
import XCTest

@testable import KeyveerApp

final class GlowingMarkerViewTests: XCTestCase {
  @MainActor
  func testGlowRemainsVisibleAndFadesBeyondTheSolidMarker() throws {
    let side = 28
    let view = GlowingMarkerView(frame: NSRect(x: 0, y: 0, width: side, height: side))
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0))
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()

    let center = try color(in: bitmap, x: 14, y: 14)
    let coreEdge = try color(in: bitmap, x: 17, y: 14)
    let middleGlow = try color(in: bitmap, x: 19, y: 14)
    let outerGlow = try color(in: bitmap, x: 20, y: 14)
    let edge = try color(in: bitmap, x: 23, y: 14)

    XCTAssertGreaterThan(center.redComponent, 0.9)
    XCTAssertGreaterThan(center.greenComponent, 0.9)
    XCTAssertGreaterThan(center.blueComponent, 0.9)
    XCTAssertGreaterThan(coreEdge.redComponent, 0.5)
    XCTAssertGreaterThan(coreEdge.greenComponent, 0.8)
    XCTAssertGreaterThan(coreEdge.blueComponent, 0.8)
    XCTAssertGreaterThan(middleGlow.alphaComponent, 0.18)
    XCTAssertGreaterThan(outerGlow.alphaComponent, 0.06)
    XCTAssertGreaterThan(middleGlow.alphaComponent, outerGlow.alphaComponent)
    XCTAssertGreaterThan(outerGlow.alphaComponent, edge.alphaComponent)
  }

  private func color(in bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
    try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
  }
}
