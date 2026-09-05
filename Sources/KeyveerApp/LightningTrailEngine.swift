import CoreGraphics
import Foundation

struct LightningStroke: Equatable {
  let points: [CGPoint]

  func taperedSegments(
    maximumLength: CGFloat, tailWidthScale: CGFloat, headWidthScale: CGFloat
  ) -> [TaperedLightningSegment] {
    guard maximumLength > 0, points.count >= 2 else { return [] }
    let lengths = zip(points, points.dropFirst()).map(distance)
    let totalLength = lengths.reduce(0, +)
    guard totalLength > 0 else { return [] }

    var result: [TaperedLightningSegment] = []
    var traversed: CGFloat = 0
    for (index, length) in lengths.enumerated() where length > 0 {
      let start = points[index]
      let delta = subtract(points[index + 1], start)
      let subdivisionCount = max(1, Int(ceil(length / maximumLength)))
      for subdivision in 0..<subdivisionCount {
        let localStart = CGFloat(subdivision) / CGFloat(subdivisionCount)
        let localEnd = CGFloat(subdivision + 1) / CGFloat(subdivisionCount)
        let widthProgress = (traversed + length * (localStart + localEnd) / 2) / totalLength
        let easedProgress = CGFloat(pow(Double(widthProgress), 0.85))
        result.append(
          TaperedLightningSegment(
            start: add(start, multiply(delta, localStart)),
            end: add(start, multiply(delta, localEnd)),
            widthScale: tailWidthScale
              + (headWidthScale - tailWidthScale) * easedProgress))
      }
      traversed += length
    }
    return result
  }
}

struct TaperedLightningSegment: Equatable {
  let start: CGPoint
  let end: CGPoint
  let widthScale: CGFloat
}

struct LightningBolt: Equatable {
  let id: UInt64
  let trunk: LightningStroke
  let createdAt: TimeInterval
  let glowScale: CGFloat
}

struct RenderedLightningBolt: Equatable {
  let id: UInt64
  let trunk: LightningStroke
  let alpha: CGFloat
  let glowScale: CGFloat
}

struct LightningTrailFrame: Equatable {
  let bolts: [RenderedLightningBolt]

  static let empty = LightningTrailFrame(bolts: [])
  var isEmpty: Bool { bolts.isEmpty }
}

struct LightningTrailEngine {
  private struct Sample: Equatable {
    let point: CGPoint
    let timestamp: TimeInterval
  }

  private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
      state = seed
    }

    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var value = state
      value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
      value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
      return value ^ (value >> 31)
    }

    mutating func unit() -> CGFloat {
      CGFloat(Double(next() >> 11) / Double(1 << 53))
    }

    mutating func value(in range: ClosedRange<CGFloat>) -> CGFloat {
      range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }
  }

  private static let standardEmissionInterval: TimeInterval = 1.0 / 30.0
  private static let reducedMotionEmissionInterval: TimeInterval = 1.0 / 15.0
  private static let standardLifetime: TimeInterval = 0.30
  private static let reducedMotionLifetime: TimeInterval = 0.15
  private static let fullBrightnessDuration: TimeInterval = 0.05
  private static let speedWindow: TimeInterval = 0.10
  private static let tailLookback: TimeInterval = 0.36
  private static let minimumSpan: CGFloat = 10
  private static let normalMinimumSpan: CGFloat = 24
  private static let maximumSpan: CGFloat = 320
  private static let highSpeed: CGFloat = 900

  private var samples: [Sample] = []
  private var bolts: [LightningBolt] = []
  private var random: SplitMix64
  private var lastEmissionTime: TimeInterval?
  private var lastEmittedPoint: CGPoint?
  private var nextBoltID: UInt64 = 0
  private(set) var reduceMotion = false

  init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
    random = SplitMix64(seed: seed)
  }

  mutating func setReduceMotion(_ enabled: Bool) {
    guard enabled != reduceMotion else { return }
    reduceMotion = enabled
    clear()
  }

  mutating func clear() {
    samples.removeAll(keepingCapacity: true)
    bolts.removeAll(keepingCapacity: true)
    lastEmissionTime = nil
    lastEmittedPoint = nil
  }

  mutating func move(to point: CGPoint, at timestamp: TimeInterval) {
    prune(at: timestamp)
    guard samples.last?.point != point else { return }
    samples.append(Sample(point: point, timestamp: timestamp))
    trimSamples(at: timestamp)
    emitIfReady(at: timestamp)
  }

  mutating func frame(at timestamp: TimeInterval) -> LightningTrailFrame {
    prune(at: timestamp)
    let renderedBolts = bolts.map { bolt in
      RenderedLightningBolt(
        id: bolt.id,
        trunk: bolt.trunk,
        alpha: boltAlpha(for: bolt, at: timestamp),
        glowScale: bolt.glowScale)
    }
    return LightningTrailFrame(bolts: renderedBolts)
  }

  private mutating func emitIfReady(at timestamp: TimeInterval) {
    guard let current = samples.last else { return }
    let interval = reduceMotion
      ? Self.reducedMotionEmissionInterval : Self.standardEmissionInterval
    if let lastEmissionTime, timestamp - lastEmissionTime + 0.000_001 < interval { return }
    if let lastEmittedPoint, lastEmittedPoint == current.point { return }

    let speed = estimatedSpeed(at: timestamp)
    let accelerationProgress = min(1, max(0, (speed - 600) / (Self.highSpeed - 600)))
    let spanFactor = 0.18 + accelerationProgress * 0.12
    let targetSpan = min(Self.maximumSpan, max(Self.normalMinimumSpan, speed * spanFactor))
    guard
      let centerline = tailPath(
        for: current.point, targetSpan: targetSpan, at: timestamp)
    else { return }
    let span = polylineLength(centerline)
    guard span >= Self.minimumSpan else { return }

    let bolt = makeBolt(along: centerline, speed: speed, at: timestamp)
    bolts = [bolt]

    lastEmissionTime = timestamp
    lastEmittedPoint = current.point
  }

  private mutating func makeBolt(
    along centerline: [CGPoint], speed: CGFloat, at timestamp: TimeInterval
  ) -> LightningBolt {
    let boltID = nextBoltID
    nextBoltID &+= 1
    let anchor = centerline.first!
    let head = centerline.last!
    if reduceMotion {
      return LightningBolt(
        id: boltID, trunk: LightningStroke(points: [anchor, head]),
        createdAt: timestamp, glowScale: 1)
    }

    let span = polylineLength(centerline)
    let segmentCount = min(9, max(3, Int(ceil(span / 18))))
    let amplitude = min(24, max(6, span * 0.18))
    var segmentWeights: [CGFloat] = []
    segmentWeights.reserveCapacity(segmentCount)
    for _ in 0..<segmentCount {
      segmentWeights.append(random.value(in: 0.55...1.45))
    }
    let totalWeight = segmentWeights.reduce(0, +)
    var trunkPoints = [anchor]
    var accumulatedWeight: CGFloat = 0
    for index in 1..<segmentCount {
      accumulatedWeight += segmentWeights[index - 1]
      let progress = accumulatedWeight / totalWeight
      let (center, tangent) = pointAndTangent(along: centerline, progress: progress)
      let normal = CGPoint(x: -tangent.y, y: tangent.x)
      let direction: CGFloat = random.unit() < 0.5 ? -1 : 1
      let offset = direction * amplitude * random.value(in: 0.25...1)
      trunkPoints.append(add(center, multiply(normal, offset)))
    }
    trunkPoints.append(head)
    let trunk = LightningStroke(points: trunkPoints)

    let speedProgress = min(1, max(0, (speed - 300) / (Self.highSpeed - 300)))
    return LightningBolt(
      id: boltID, trunk: trunk, createdAt: timestamp,
      glowScale: 1 + speedProgress * 0.15)
  }

  private func estimatedSpeed(at timestamp: TimeInterval) -> CGFloat {
    guard samples.count >= 2 else { return 0 }
    let cutoff = timestamp - Self.speedWindow
    var traveled: CGFloat = 0
    var measuredDuration: TimeInterval = 0
    for index in 1..<samples.count {
      let older = samples[index - 1]
      let newer = samples[index]
      guard newer.timestamp > cutoff, newer.timestamp > older.timestamp else { continue }
      let startTime = max(cutoff, older.timestamp)
      let startProgress = CGFloat((startTime - older.timestamp) / (newer.timestamp - older.timestamp))
      let startPoint = add(
        older.point, multiply(subtract(newer.point, older.point), startProgress))
      traveled += distance(startPoint, newer.point)
      measuredDuration += newer.timestamp - startTime
    }
    return measuredDuration > 0 ? traveled / CGFloat(measuredDuration) : 0
  }

  private func tailPath(
    for head: CGPoint, targetSpan: CGFloat, at timestamp: TimeInterval
  ) -> [CGPoint]? {
    guard samples.count >= 2 else { return nil }
    let cutoff = timestamp - Self.tailLookback
    var reversedPath = [head]
    var remaining = targetSpan
    for index in stride(from: samples.count - 1, through: 1, by: -1) {
      let newerSample = samples[index]
      let olderSample = samples[index - 1]
      guard newerSample.timestamp > cutoff, newerSample.timestamp > olderSample.timestamp else {
        continue
      }
      let older: CGPoint
      if olderSample.timestamp < cutoff {
        let progress = CGFloat(
          (cutoff - olderSample.timestamp) / (newerSample.timestamp - olderSample.timestamp))
        older = add(
          olderSample.point,
          multiply(subtract(newerSample.point, olderSample.point), progress))
      } else {
        older = olderSample.point
      }
      let newer = newerSample.point
      let segmentLength = distance(newer, older)
      guard segmentLength > 0 else { continue }
      if segmentLength >= remaining {
        let anchor = add(newer, multiply(subtract(older, newer), remaining / segmentLength))
        if reversedPath.last != anchor { reversedPath.append(anchor) }
        return Array(reversedPath.reversed())
      }
      if reversedPath.last != older { reversedPath.append(older) }
      remaining -= segmentLength
      if olderSample.timestamp <= cutoff { break }
    }
    return reversedPath.count >= 2 ? Array(reversedPath.reversed()) : nil
  }

  private mutating func prune(at timestamp: TimeInterval) {
    let boltLifetime = reduceMotion ? Self.reducedMotionLifetime : Self.standardLifetime
    bolts.removeAll { timestamp - $0.createdAt >= boltLifetime }
    trimSamples(at: timestamp)
  }

  private mutating func trimSamples(at timestamp: TimeInterval) {
    let cutoff = timestamp - Self.tailLookback
    while samples.count > 2, samples[1].timestamp < cutoff {
      samples.removeFirst()
    }
  }

  private func boltAlpha(for bolt: LightningBolt, at timestamp: TimeInterval) -> CGFloat {
    let age = max(0, timestamp - bolt.createdAt)
    if reduceMotion {
      return CGFloat(max(0, 1 - age / Self.reducedMotionLifetime))
    }
    if age <= Self.fullBrightnessDuration { return 1 }
    let fadeDuration = Self.standardLifetime - Self.fullBrightnessDuration
    let remaining = max(0, 1 - (age - Self.fullBrightnessDuration) / fadeDuration)
    return CGFloat(remaining * remaining)
  }
}

private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
  hypot(lhs.x - rhs.x, lhs.y - rhs.y)
}

private func polylineLength(_ points: [CGPoint]) -> CGFloat {
  zip(points, points.dropFirst()).map(distance).reduce(0, +)
}

private func pointAndTangent(
  along points: [CGPoint], progress: CGFloat
) -> (point: CGPoint, tangent: CGPoint) {
  let lengths = zip(points, points.dropFirst()).map(distance)
  var remaining = polylineLength(points) * min(1, max(0, progress))
  for (index, segmentLength) in lengths.enumerated() where segmentLength > 0 {
    let delta = subtract(points[index + 1], points[index])
    if remaining <= segmentLength {
      return (
        add(points[index], multiply(delta, remaining / segmentLength)),
        normalized(delta))
    }
    remaining -= segmentLength
  }
  let fallback = subtract(points.last!, points[points.count - 2])
  return (points.last!, normalized(fallback))
}

private func add(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
  CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

private func subtract(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
  CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

private func multiply(_ point: CGPoint, _ scalar: CGFloat) -> CGPoint {
  CGPoint(x: point.x * scalar, y: point.y * scalar)
}

private func normalized(_ point: CGPoint) -> CGPoint {
  let length = hypot(point.x, point.y)
  return length > 0 ? multiply(point, 1 / length) : .zero
}
