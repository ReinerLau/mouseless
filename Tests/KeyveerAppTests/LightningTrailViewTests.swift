import AppKit
import XCTest

@testable import KeyveerApp

final class LightningTrailViewTests: XCTestCase {
  @MainActor
  func testBroadGlowRemainsVisibleTenPointsFromTrunk() throws {
    let width = 200
    let height = 80
    let view = LightningTrailView(
      frame: NSRect(x: 0, y: 0, width: width, height: height))
    view.drawingState = .init(
      frame: LightningTrailFrame(
        bolts: [
          RenderedLightningBolt(
            id: 1,
            trunk: LightningStroke(
              points: [CGPoint(x: 20, y: 40), CGPoint(x: 180, y: 40)]),
            alpha: 1,
            glowScale: 1)
        ]),
      canvasOrigin: .zero)

    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
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

    let visibleGlow = try color(in: bitmap, x: 150, y: 50)
    let distantPixel = try color(in: bitmap, x: 150, y: 70)

    XCTAssertGreaterThan(visibleGlow.alphaComponent, 0.03)
    XCTAssertGreaterThan(visibleGlow.blueComponent, visibleGlow.redComponent)
    XCTAssertGreaterThan(visibleGlow.alphaComponent, distantPixel.alphaComponent)
  }

  private func color(in bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
    try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
  }
}
