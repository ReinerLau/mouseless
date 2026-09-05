import CoreGraphics
import XCTest

@testable import KeyveerApp

final class LightningTrailEngineTests: XCTestCase {
  func testShortPrecisionMovementStillEmitsABolt() {
    var engine = LightningTrailEngine(seed: 1)

    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 12, y: 0), at: 0.1)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    XCTAssertEqual(bolt.trunk.points.first, CGPoint(x: 0, y: 0))
    XCTAssertEqual(bolt.trunk.points.last, CGPoint(x: 12, y: 0))
  }

  func testMovementBelowTenPointsDoesNotEmit() {
    var engine = LightningTrailEngine(seed: 1)

    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 9.9, y: 0), at: 0.1)

    XCTAssertTrue(engine.frame(at: 0.1).isEmpty)
  }

  func testHighSpeedAnchorIsLimitedToThreeHundredTwentyPoints() {
    var engine = LightningTrailEngine(seed: 2)

    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 500, y: 0), at: 0.1)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    XCTAssertEqual(bolt.trunk.points.first!.x, 180, accuracy: 0.001)
    XCTAssertEqual(bolt.trunk.points.last!.x, 500, accuracy: 0.001)
  }

  func testFirstAccelerationLevelProducesALongerBolt() {
    var engine = LightningTrailEngine(seed: 2)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 270, y: 0), at: 0.3)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.3).bolts.first)
    XCTAssertEqual(bolt.trunk.points.first!.x, 0, accuracy: 0.001)
    XCTAssertEqual(bolt.trunk.points.last!.x, 270, accuracy: 0.001)
  }

  func testNormalMinimumTargetSpanIsTwentyFourPoints() {
    var engine = LightningTrailEngine(seed: 2)

    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 24, y: 0), at: 0.14)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.14).bolts.first)
    XCTAssertEqual(bolt.trunk.points.first!.x, 0, accuracy: 0.001)
    XCTAssertEqual(bolt.trunk.points.last!.x, 24, accuracy: 0.001)
  }

  func testBoltGeometryIsDeterministicAndFrozen() {
    var first = LightningTrailEngine(seed: 42)
    var second = LightningTrailEngine(seed: 42)
    for point in [CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 0)] {
      let time = point.x == 0 ? 0 : 0.1
      first.move(to: point, at: time)
      second.move(to: point, at: time)
    }

    let initial = try! XCTUnwrap(first.frame(at: 0.1).bolts.first)
    let sameSeed = try! XCTUnwrap(second.frame(at: 0.1).bolts.first)
    let later = try! XCTUnwrap(first.frame(at: 0.2).bolts.first)

    XCTAssertEqual(initial.trunk, sameSeed.trunk)
    XCTAssertEqual(initial.trunk, later.trunk)
    XCTAssertTrue(initial.trunk.points.dropFirst().dropLast().contains { abs($0.y) > 0.1 })
  }

  func testBoltBendPositionsAreIrregularlySpaced() {
    var engine = LightningTrailEngine(seed: 42)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 200, y: 0), at: 0.1)

    let points = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.trunk.points)
    let gaps = zip(points, points.dropFirst()).map { $1.x - $0.x }

    XCTAssertGreaterThan(gaps.max()! - gaps.min()!, 2)
  }

  func testBendOffsetsUseTheSameDistributionAcrossTheWholeTrunk() {
    var edgeOffsets: [CGFloat] = []
    var middleOffsets: [CGFloat] = []
    for seed in 0..<200 {
      var engine = LightningTrailEngine(seed: UInt64(seed))
      engine.move(to: CGPoint(x: 0, y: 0), at: 0)
      engine.move(to: CGPoint(x: 200, y: 0), at: 0.1)

      let interior = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first?.trunk.points)
        .dropFirst().dropLast().map { abs($0.y) }
      edgeOffsets.append(contentsOf: [interior.first!, interior.last!])
      let middle = interior.count / 2
      middleOffsets.append(contentsOf: [interior[middle - 1], interior[middle]])
    }

    let edgeAverage = edgeOffsets.reduce(0, +) / CGFloat(edgeOffsets.count)
    let middleAverage = middleOffsets.reduce(0, +) / CGFloat(middleOffsets.count)
    XCTAssertGreaterThan(edgeAverage / middleAverage, 0.75)
    XCTAssertLessThan(edgeAverage / middleAverage, 1.25)
  }

  func testCurvedMovementHistoryBendsTheBoltAroundTheTurn() {
    var engine = LightningTrailEngine(seed: 42)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 0, y: 100), at: 0.1)
    engine.move(to: CGPoint(x: 100, y: 100), at: 0.2)
    engine.move(to: CGPoint(x: 100, y: 0), at: 0.3)

    let points = try! XCTUnwrap(engine.frame(at: 0.3).bolts.first?.trunk.points)
    XCTAssertGreaterThan(points.map(\.y).max()!, 50)
  }

  func testTaperedSegmentsConnectTailToHeadAndGrowTowardTheMarker() {
    let stroke = LightningStroke(
      points: [CGPoint(x: 0, y: 0), CGPoint(x: 6, y: 8), CGPoint(x: 16, y: 8)])

    let segments = stroke.taperedSegments(
      maximumLength: 4, tailWidthScale: 0.18, headWidthScale: 1.25)

    XCTAssertEqual(segments.first?.start, CGPoint(x: 0, y: 0))
    XCTAssertEqual(segments.last?.end, CGPoint(x: 16, y: 8))
    XCTAssertLessThan(segments.first!.widthScale, 0.5)
    XCTAssertGreaterThan(segments.last!.widthScale, 1.15)
    for pair in zip(segments, segments.dropFirst()) {
      XCTAssertEqual(pair.0.end, pair.1.start)
      XCTAssertLessThan(pair.0.widthScale, pair.1.widthScale)
    }
  }

  func testBoltHoldsThenFadesQuadratically() {
    var engine = LightningTrailEngine(seed: 3)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 20, y: 0), at: 0.1)

    XCTAssertEqual(engine.frame(at: 0.15).bolts.first?.alpha, 1)
    XCTAssertEqual(engine.frame(at: 0.275).bolts.first!.alpha, 0.25, accuracy: 0.001)
    XCTAssertTrue(engine.frame(at: 0.4).isEmpty)
  }

  func testContinuousMovementKeepsOnlyTheLatestBoltAtAnyRefreshRate() {
    let atSixty = activeBoltSnapshot(refreshRate: 60)
    let atOneTwenty = activeBoltSnapshot(refreshRate: 120)

    XCTAssertEqual(atSixty.count, 1)
    XCTAssertEqual(atOneTwenty.count, 1)
    XCTAssertEqual(atSixty.latestID, atOneTwenty.latestID)
    XCTAssertTrue((28...30).contains(atSixty.latestID))
  }

  func testNormalAndHighSpeedBoltsRemainSingleTrunks() {
    var normal = LightningTrailEngine(seed: 4)
    normal.move(to: CGPoint(x: 0, y: 0), at: 0)
    normal.move(to: CGPoint(x: 64, y: 0), at: 0.128)
    let normalBolt = try! XCTUnwrap(normal.frame(at: 0.128).bolts.first)

    var high = LightningTrailEngine(seed: 4)
    high.move(to: CGPoint(x: 0, y: 0), at: 0)
    high.move(to: CGPoint(x: 200, y: 0), at: 0.1)
    let highBolt = try! XCTUnwrap(high.frame(at: 0.1).bolts.first)

    XCTAssertEqual(normalBolt.trunk.points.first, CGPoint(x: 0, y: 0))
    XCTAssertEqual(normalBolt.trunk.points.last, CGPoint(x: 64, y: 0))
    XCTAssertEqual(highBolt.trunk.points.first, CGPoint(x: 0, y: 0))
    XCTAssertEqual(highBolt.trunk.points.last, CGPoint(x: 200, y: 0))
    XCTAssertEqual(normalBolt.glowScale, 1.05, accuracy: 0.001)
    XCTAssertEqual(highBolt.glowScale, 1.15, accuracy: 0.001)
  }

  func testReducedMotionUsesStraightBranchlessShortLivedBolts() {
    var engine = LightningTrailEngine(seed: 5)
    engine.setReduceMotion(true)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 20, y: 0), at: 0.1)

    let bolt = try! XCTUnwrap(engine.frame(at: 0.1).bolts.first)
    XCTAssertEqual(bolt.trunk.points, [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)])
    XCTAssertEqual(engine.frame(at: 0.15).bolts.first!.alpha, 2.0 / 3.0, accuracy: 0.001)
    XCTAssertTrue(engine.frame(at: 0.25).isEmpty)
  }

  func testClearAndAccessibilityModeChangeRemoveAllVisualState() {
    var engine = LightningTrailEngine(seed: 6)
    engine.move(to: CGPoint(x: 0, y: 0), at: 0)
    engine.move(to: CGPoint(x: 100, y: 0), at: 0.1)
    XCTAssertFalse(engine.frame(at: 0.1).isEmpty)

    engine.clear()
    XCTAssertTrue(engine.frame(at: 0.1).isEmpty)

    engine.move(to: CGPoint(x: 0, y: 0), at: 0.2)
    engine.move(to: CGPoint(x: 100, y: 0), at: 0.3)
    engine.setReduceMotion(true)
    XCTAssertTrue(engine.frame(at: 0.3).isEmpty)
  }

  private func activeBoltSnapshot(refreshRate: Double) -> (count: Int, latestID: UInt64) {
    var engine = LightningTrailEngine(seed: 7)
    let frameDuration = 1 / refreshRate
    for frame in 0...Int(refreshRate) {
      let timestamp = Double(frame) * frameDuration
      engine.move(to: CGPoint(x: timestamp * 300, y: 0), at: timestamp)
    }
    let bolts = engine.frame(at: 1).bolts
    return (bolts.count, bolts.last?.id ?? 0)
  }
}
