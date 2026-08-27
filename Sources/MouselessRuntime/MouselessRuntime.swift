import Foundation

public struct Point: Equatable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct DisplayRegion: Equatable, Sendable {
  public var origin: Point
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.origin = Point(x: x, y: y)
    self.width = width
    self.height = height
  }

  fileprivate func closestPoint(to point: Point) -> Point {
    Point(
      x: min(max(point.x, origin.x), origin.x + width),
      y: min(max(point.y, origin.y), origin.y + height)
    )
  }

  fileprivate func contains(_ point: Point) -> Bool {
    point.x >= origin.x && point.x <= origin.x + width
      && point.y >= origin.y && point.y <= origin.y + height
  }
}

public struct DisplayTopology: Equatable, Sendable {
  public var regions: [DisplayRegion]

  public init(regions: [DisplayRegion]) {
    self.regions = regions
  }

  public static let unrestricted = DisplayTopology(regions: [])

  fileprivate func projected(_ point: Point) -> Point {
    guard !regions.isEmpty, !regions.contains(where: { $0.contains(point) }) else { return point }
    return
      regions
      .map { ($0.closestPoint(to: point), squaredDistance($0.closestPoint(to: point), point)) }
      .min { $0.1 < $1.1 }?.0 ?? point
  }

  fileprivate func constrainedMotionPoint(from start: Point, to candidate: Point) -> Point {
    guard !regions.isEmpty else { return candidate }

    let delta = candidate - start
    let distance = sqrt(delta.x * delta.x + delta.y * delta.y)
    guard distance > 0 else { return start }
    let direction = delta * (1 / distance)
    let furthestReachableDistance = regions.compactMap {
      rayIntersectionInterval(from: start, direction: direction, with: $0)?.upperBound
    }.max()

    guard let furthestReachableDistance else { return projected(start) }
    return distance <= furthestReachableDistance
      ? candidate
      : start + direction * furthestReachableDistance
  }

  private func rayIntersectionInterval(
    from start: Point, direction: Point, with region: DisplayRegion
  ) -> ClosedRange<Double>? {
    var lower = 0.0
    var upper = Double.infinity
    for (position, velocity, minimum, maximum) in [
      (start.x, direction.x, region.origin.x, region.origin.x + region.width),
      (start.y, direction.y, region.origin.y, region.origin.y + region.height),
    ] {
      if abs(velocity) < 0.0000001 {
        guard position >= minimum && position <= maximum else { return nil }
        continue
      }
      let first = (minimum - position) / velocity
      let second = (maximum - position) / velocity
      lower = max(lower, min(first, second))
      upper = min(upper, max(first, second))
      if lower > upper { return nil }
    }
    return lower <= upper ? lower...upper : nil
  }
}

private func squaredDistance(_ lhs: Point, _ rhs: Point) -> Double {
  let dx = lhs.x - rhs.x
  let dy = lhs.y - rhs.y
  return dx * dx + dy * dy
}

public struct PermissionState: Equatable, Sendable {
  public var accessibility: Bool
  public var listenEvent: Bool
  public var postEvent: Bool

  public init(accessibility: Bool, listenEvent: Bool, postEvent: Bool) {
    self.accessibility = accessibility
    self.listenEvent = listenEvent
    self.postEvent = postEvent
  }

  public static let none = PermissionState(
    accessibility: false, listenEvent: false, postEvent: false)
  public static let allGranted = PermissionState(
    accessibility: true, listenEvent: true, postEvent: true)

  public var isReady: Bool { accessibility && listenEvent && postEvent }
}

public enum Key: Hashable, Sendable {
  case leftOption, rightOption, escape
  case i, j, k, l
  case space, r, e, q, w
  case m, comma, period, slash
  case a, s, d, f
  case other(Int)

  fileprivate init(configurationName: String) {
    switch configurationName {
    case "leftOption": self = .leftOption
    case "rightOption": self = .rightOption
    case "escape": self = .escape
    case "i": self = .i
    case "j": self = .j
    case "k": self = .k
    case "l": self = .l
    case "space": self = .space
    case "r": self = .r
    case "e": self = .e
    case "q": self = .q
    case "w": self = .w
    case "m": self = .m
    case "comma": self = .comma
    case "period": self = .period
    case "slash": self = .slash
    case "a": self = .a
    case "s": self = .s
    case "d": self = .d
    case "f": self = .f
    default: self = .other(Int.min)
    }
  }

  fileprivate var isValidConfigurationKey: Bool {
    if case .other = self { return false }
    return true
  }
}

public enum MouseButton: Int, CaseIterable, Hashable, Sendable {
  case left = 0
  case right = 1
  case middle = 2
  case back = 3
  case forward = 4
}

public enum ButtonPhase: Sendable {
  case down, up
}

public enum EventDisposition: Equatable, Sendable {
  case passThrough
  case consume
}

public enum Diagnostic: Equatable, Sendable {
  case safetyExit
  case eventTapRecovered
  case configurationAccepted
  case configurationRejected
}

public enum RuntimeEffect: Equatable, Sendable {
  case capabilitiesChanged(PermissionState)
  case modeChanged(isEnabled: Bool)
  case indicator(isVisible: Bool)
  case pointerPositionChanged(to: Point)
  case pointerMoved(to: Point, buttons: Set<MouseButton>)
  case mouseButton(MouseButton, ButtonPhase)
  case scroll(pixelX: Int, pixelY: Int)
  case configurationAccepted
  case configurationRejected
  case eventTapShouldBeReenabled
  case diagnostic(Diagnostic)
}

public struct RuntimeResponse: Equatable, Sendable {
  public let disposition: EventDisposition
  public let effects: [RuntimeEffect]

  public init(disposition: EventDisposition, effects: [RuntimeEffect] = []) {
    self.disposition = disposition
    self.effects = effects
  }
}

public enum SessionState: Sendable {
  case active
  case inactive
  case sleeping
  case waking
}

public struct RuntimeEvent {
  fileprivate enum Kind {
    case keyDown(Key, timestamp: TimeInterval, isAutoRepeat: Bool)
    case keyUp(Key, timestamp: TimeInterval)
    case modifierChanged(Key, isPressed: Bool, timestamp: TimeInterval)
    case frame(deltaTime: TimeInterval)
    case pointerMoved(Point, source: PointerSource)
    case topologyChanged(DisplayTopology)
    case permissionsChanged(PermissionState)
    case sessionChanged(SessionState)
    case eventTapDisabled
    case configuration(Data)
    case shutdown
  }

  fileprivate enum PointerSource { case physical, synthesized }
  fileprivate let kind: Kind

  public static func keyDown(_ key: Key, at timestamp: TimeInterval, isAutoRepeat: Bool = false)
    -> RuntimeEvent
  {
    RuntimeEvent(kind: .keyDown(key, timestamp: timestamp, isAutoRepeat: isAutoRepeat))
  }

  public static func keyUp(_ key: Key, at timestamp: TimeInterval) -> RuntimeEvent {
    RuntimeEvent(kind: .keyUp(key, timestamp: timestamp))
  }

  public static func modifierChanged(_ key: Key, isPressed: Bool, at timestamp: TimeInterval)
    -> RuntimeEvent
  {
    RuntimeEvent(kind: .modifierChanged(key, isPressed: isPressed, timestamp: timestamp))
  }

  public static func frame(deltaTime: TimeInterval) -> RuntimeEvent {
    RuntimeEvent(kind: .frame(deltaTime: deltaTime))
  }

  public static func pointerMoved(to point: Point) -> RuntimeEvent {
    RuntimeEvent(kind: .pointerMoved(point, source: .physical))
  }

  public static func synthesizedPointerMoved(to point: Point) -> RuntimeEvent {
    RuntimeEvent(kind: .pointerMoved(point, source: .synthesized))
  }

  public static func topologyChanged(_ topology: DisplayTopology) -> RuntimeEvent {
    RuntimeEvent(kind: .topologyChanged(topology))
  }

  public static func permissionsChanged(_ permissions: PermissionState) -> RuntimeEvent {
    RuntimeEvent(kind: .permissionsChanged(permissions))
  }

  public static func sessionChanged(_ state: SessionState) -> RuntimeEvent {
    RuntimeEvent(kind: .sessionChanged(state))
  }

  public static let eventTapDisabled = RuntimeEvent(kind: .eventTapDisabled)

  public static func configuration(_ data: Data) -> RuntimeEvent {
    RuntimeEvent(kind: .configuration(data))
  }

  public static let shutdown = RuntimeEvent(kind: .shutdown)
}

public struct KeyBindings: Codable, Equatable, Sendable {
  public var toggle: String
  public var escape: String
  public var moveUp: String
  public var moveDown: String
  public var moveLeft: String
  public var moveRight: String
  public var leftClick: String
  public var rightClick: String
  public var middleClick: String
  public var backClick: String
  public var forwardClick: String
  public var scrollUp: String
  public var scrollDown: String
  public var scrollLeft: String
  public var scrollRight: String
  public var precision: String
  public var speedOne: String
  public var speedTwo: String
  public var speedThree: String

  public init(
    toggle: String = "leftOption", escape: String = "escape",
    moveUp: String = "i", moveDown: String = "k", moveLeft: String = "j", moveRight: String = "l",
    leftClick: String = "space", rightClick: String = "r", middleClick: String = "e",
    backClick: String = "q", forwardClick: String = "w", scrollUp: String = "m",
    scrollDown: String = "comma", scrollLeft: String = "period", scrollRight: String = "slash",
    precision: String = "a", speedOne: String = "s", speedTwo: String = "d",
    speedThree: String = "f"
  ) {
    self.toggle = toggle
    self.escape = escape
    self.moveUp = moveUp
    self.moveDown = moveDown
    self.moveLeft = moveLeft
    self.moveRight = moveRight
    self.leftClick = leftClick
    self.rightClick = rightClick
    self.middleClick = middleClick
    self.backClick = backClick
    self.forwardClick = forwardClick
    self.scrollUp = scrollUp
    self.scrollDown = scrollDown
    self.scrollLeft = scrollLeft
    self.scrollRight = scrollRight
    self.precision = precision
    self.speedOne = speedOne
    self.speedTwo = speedTwo
    self.speedThree = speedThree
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case toggle, escape, moveUp, moveDown, moveLeft, moveRight, leftClick, rightClick, middleClick
    case backClick, forwardClick, scrollUp, scrollDown, scrollLeft, scrollRight, precision
    case speedOne, speedTwo, speedThree
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
    self.init(
      toggle: try container.decode(String.self, forKey: .toggle),
      escape: try container.decode(String.self, forKey: .escape),
      moveUp: try container.decode(String.self, forKey: .moveUp),
      moveDown: try container.decode(String.self, forKey: .moveDown),
      moveLeft: try container.decode(String.self, forKey: .moveLeft),
      moveRight: try container.decode(String.self, forKey: .moveRight),
      leftClick: try container.decode(String.self, forKey: .leftClick),
      rightClick: try container.decode(String.self, forKey: .rightClick),
      middleClick: try container.decode(String.self, forKey: .middleClick),
      backClick: try container.decode(String.self, forKey: .backClick),
      forwardClick: try container.decode(String.self, forKey: .forwardClick),
      scrollUp: try container.decode(String.self, forKey: .scrollUp),
      scrollDown: try container.decode(String.self, forKey: .scrollDown),
      scrollLeft: try container.decode(String.self, forKey: .scrollLeft),
      scrollRight: try container.decode(String.self, forKey: .scrollRight),
      precision: try container.decode(String.self, forKey: .precision),
      speedOne: try container.decode(String.self, forKey: .speedOne),
      speedTwo: try container.decode(String.self, forKey: .speedTwo),
      speedThree: try container.decode(String.self, forKey: .speedThree)
    )
  }
}

public struct MotionSettings: Codable, Equatable, Sendable {
  public var baseSpeed: Double
  public var precisionMultiplier: Double
  public var fastMultiplier: Double
  public var smoothingMilliseconds: Double

  public init(
    baseSpeed: Double = 300, precisionMultiplier: Double = 1.0 / 3.0, fastMultiplier: Double = 3,
    smoothingMilliseconds: Double = 75
  ) {
    self.baseSpeed = baseSpeed
    self.precisionMultiplier = precisionMultiplier
    self.fastMultiplier = fastMultiplier
    self.smoothingMilliseconds = smoothingMilliseconds
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case baseSpeed, precisionMultiplier, fastMultiplier, smoothingMilliseconds
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
    self.init(
      baseSpeed: try container.decode(Double.self, forKey: .baseSpeed),
      precisionMultiplier: try container.decode(Double.self, forKey: .precisionMultiplier),
      fastMultiplier: try container.decode(Double.self, forKey: .fastMultiplier),
      smoothingMilliseconds: try container.decode(Double.self, forKey: .smoothingMilliseconds))
  }
}

public struct ScrollSettings: Codable, Equatable, Sendable {
  public var baseSpeed: Double
  public var precisionMultiplier: Double
  public var fastMultiplier: Double
  public var smoothingMilliseconds: Double

  public init(
    baseSpeed: Double = 960, precisionMultiplier: Double = 0.25, fastMultiplier: Double = 4,
    smoothingMilliseconds: Double = 47
  ) {
    self.baseSpeed = baseSpeed
    self.precisionMultiplier = precisionMultiplier
    self.fastMultiplier = fastMultiplier
    self.smoothingMilliseconds = smoothingMilliseconds
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case baseSpeed, precisionMultiplier, fastMultiplier, smoothingMilliseconds
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
    self.init(
      baseSpeed: try container.decode(Double.self, forKey: .baseSpeed),
      precisionMultiplier: try container.decode(Double.self, forKey: .precisionMultiplier),
      fastMultiplier: try container.decode(Double.self, forKey: .fastMultiplier),
      smoothingMilliseconds: try container.decode(Double.self, forKey: .smoothingMilliseconds))
  }
}

public struct IndicatorSettings: Codable, Equatable, Sendable {
  public var enabled: Bool
  public var size: Double

  public init(enabled: Bool = true, size: Double = 8) {
    self.enabled = enabled
    self.size = size
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case enabled, size }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
    self.init(
      enabled: try container.decode(Bool.self, forKey: .enabled),
      size: try container.decode(Double.self, forKey: .size))
  }
}

public struct RuntimeConfiguration: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var bindings: KeyBindings
  public var movement: MotionSettings
  public var scrolling: ScrollSettings
  public var optionTapMilliseconds: Double
  public var indicator: IndicatorSettings

  public init(
    schemaVersion: Int = 1, bindings: KeyBindings = KeyBindings(),
    movement: MotionSettings = MotionSettings(), scrolling: ScrollSettings = ScrollSettings(),
    optionTapMilliseconds: Double = 250, indicator: IndicatorSettings = IndicatorSettings()
  ) {
    self.schemaVersion = schemaVersion
    self.bindings = bindings
    self.movement = movement
    self.scrolling = scrolling
    self.optionTapMilliseconds = optionTapMilliseconds
    self.indicator = indicator
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion, bindings, movement, scrolling, optionTapMilliseconds, indicator
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
    self.init(
      schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
      bindings: try container.decode(KeyBindings.self, forKey: .bindings),
      movement: try container.decode(MotionSettings.self, forKey: .movement),
      scrolling: try container.decode(ScrollSettings.self, forKey: .scrolling),
      optionTapMilliseconds: try container.decode(Double.self, forKey: .optionTapMilliseconds),
      indicator: try container.decode(IndicatorSettings.self, forKey: .indicator)
    )
  }

  public func validated() throws -> RuntimeConfiguration {
    guard schemaVersion == 1, optionTapMilliseconds > 0, optionTapMilliseconds <= 1_000,
      movement.baseSpeed > 0, movement.precisionMultiplier > 0, movement.fastMultiplier >= 1,
      movement.smoothingMilliseconds > 0,
      scrolling.baseSpeed > 0, scrolling.precisionMultiplier > 0, scrolling.fastMultiplier >= 1,
      scrolling.smoothingMilliseconds > 0,
      indicator.size > 0, indicator.size <= 100
    else { throw ConfigurationError.invalidValue }

    let names = [
      bindings.toggle, bindings.escape, bindings.moveUp, bindings.moveDown, bindings.moveLeft,
      bindings.moveRight,
      bindings.leftClick, bindings.rightClick, bindings.middleClick, bindings.backClick,
      bindings.forwardClick,
      bindings.scrollUp, bindings.scrollDown, bindings.scrollLeft, bindings.scrollRight,
      bindings.precision,
      bindings.speedOne, bindings.speedTwo, bindings.speedThree,
    ]
    guard names.allSatisfy({ Key(configurationName: $0).isValidConfigurationKey }) else {
      throw ConfigurationError.invalidKey
    }
    return self
  }

  public static var defaultJSON: Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try! encoder.encode(RuntimeConfiguration())
  }
}

public enum ConfigurationError: Error, Equatable, Sendable {
  case invalidValue
  case invalidKey
}

private struct AnyCodingKey: CodingKey {
  let stringValue: String
  let intValue: Int?

  init?(stringValue: String) {
    self.stringValue = stringValue
    intValue = nil
  }
  init?(intValue: Int) {
    stringValue = String(intValue)
    self.intValue = intValue
  }
}

private func rejectUnknownKeys(_ decoder: Decoder, allowed: [String]) throws {
  let container = try decoder.container(keyedBy: AnyCodingKey.self)
  if container.allKeys.map(\.stringValue).contains(where: { !allowed.contains($0) }) {
    throw ConfigurationError.invalidValue
  }
}

public final class MouselessRuntime {
  private var configuration: RuntimeConfiguration
  private var permissions: PermissionState
  private var modeEnabled = false
  private var topology: DisplayTopology
  private var pointer = Point(x: 0, y: 0)
  private var movementPoint = Point(x: 0, y: 0)
  private var pressedKeys: Set<Key> = []
  private var heldButtons: Set<MouseButton> = []
  private var optionDownAt: TimeInterval?
  private var optionHadCombination = false
  private var movementVelocity = Point(x: 0, y: 0)
  private var scrollVelocity = Point(x: 0, y: 0)
  private var scrollRemainder = Point(x: 0, y: 0)

  public init(
    configuration: RuntimeConfiguration = RuntimeConfiguration(),
    permissions: PermissionState = .none, topology: DisplayTopology = .unrestricted,
    pointer: Point = Point(x: 0, y: 0)
  ) {
    self.configuration = (try? configuration.validated()) ?? RuntimeConfiguration()
    self.permissions = permissions
    self.topology = topology
    self.pointer = topology.projected(pointer)
    self.movementPoint = self.pointer
  }

  public func handle(_ event: RuntimeEvent) -> RuntimeResponse {
    switch event.kind {
    case .keyDown(let key, let timestamp, let isAutoRepeat):
      return keyDown(key, timestamp: timestamp, isAutoRepeat: isAutoRepeat)
    case .keyUp(let key, let timestamp): return keyUp(key, timestamp: timestamp)
    case .modifierChanged(let key, let isPressed, let timestamp):
      return isPressed
        ? keyDown(key, timestamp: timestamp, isAutoRepeat: false)
        : keyUp(key, timestamp: timestamp)
    case .frame(let deltaTime): return frame(deltaTime: deltaTime)
    case .pointerMoved(let point, let source):
      guard source == .physical else {
        return RuntimeResponse(disposition: .passThrough)
      }
      pointer = topology.projected(point)
      movementPoint = pointer
      return RuntimeResponse(
        disposition: .passThrough, effects: [.pointerPositionChanged(to: pointer)])
    case .topologyChanged(let newTopology):
      topology = newTopology
      let projected = topology.projected(pointer)
      movementPoint = projected
      guard projected != pointer else {
        return RuntimeResponse(disposition: .passThrough)
      }
      pointer = projected
      return RuntimeResponse(
        disposition: .passThrough, effects: [.pointerPositionChanged(to: pointer)])
    case .permissionsChanged(let newPermissions):
      permissions = newPermissions
      var effects = [RuntimeEffect.capabilitiesChanged(newPermissions)]
      if !newPermissions.isReady { effects.append(contentsOf: safetyExitEffects()) }
      return RuntimeResponse(disposition: .passThrough, effects: effects)
    case .sessionChanged(let state):
      guard state == .active else {
        return RuntimeResponse(disposition: .passThrough, effects: safetyExitEffects())
      }
      return RuntimeResponse(disposition: .passThrough)
    case .eventTapDisabled:
      return RuntimeResponse(
        disposition: .passThrough,
        effects: [.eventTapShouldBeReenabled, .diagnostic(.eventTapRecovered)])
    case .configuration(let data):
      do {
        let decoded = try JSONDecoder().decode(RuntimeConfiguration.self, from: data).validated()
        configuration = decoded
        return RuntimeResponse(
          disposition: .passThrough,
          effects: [.configurationAccepted, .diagnostic(.configurationAccepted)])
      } catch {
        return RuntimeResponse(
          disposition: .passThrough,
          effects: [.configurationRejected, .diagnostic(.configurationRejected)])
      }
    case .shutdown:
      return RuntimeResponse(disposition: .passThrough, effects: safetyExitEffects())
    }
  }

  private func keyDown(_ key: Key, timestamp: TimeInterval, isAutoRepeat: Bool) -> RuntimeResponse {
    if key == configurationKey(named: configuration.bindings.toggle) {
      if !isAutoRepeat {
        optionDownAt = timestamp
        optionHadCombination = false
      }
      return RuntimeResponse(disposition: .passThrough)
    }
    if optionDownAt != nil { optionHadCombination = true }
    guard modeEnabled, permissions.isReady else {
      return RuntimeResponse(disposition: .passThrough)
    }
    if !isAutoRepeat {
      if key == configurationKey(named: configuration.bindings.moveLeft), movementVelocity.x > 0 {
        movementVelocity.x = 0
      }
      if key == configurationKey(named: configuration.bindings.moveRight), movementVelocity.x < 0 {
        movementVelocity.x = 0
      }
      if key == configurationKey(named: configuration.bindings.moveUp), movementVelocity.y < 0 {
        movementVelocity.y = 0
      }
      if key == configurationKey(named: configuration.bindings.moveDown), movementVelocity.y > 0 {
        movementVelocity.y = 0
      }
    }
    if key == configurationKey(named: configuration.bindings.escape) {
      return RuntimeResponse(disposition: .consume, effects: safetyExitEffects())
    }
    guard let button = button(for: key) else {
      if isMappedKey(key), !isAutoRepeat { pressedKeys.insert(key) }
      return RuntimeResponse(disposition: isMappedKey(key) ? .consume : .passThrough)
    }
    if !isAutoRepeat, heldButtons.insert(button).inserted {
      return RuntimeResponse(disposition: .consume, effects: [.mouseButton(button, .down)])
    }
    return RuntimeResponse(disposition: .consume)
  }

  private func keyUp(_ key: Key, timestamp: TimeInterval) -> RuntimeResponse {
    if key == configurationKey(named: configuration.bindings.toggle) {
      defer {
        optionDownAt = nil
        optionHadCombination = false
      }
      guard permissions.isReady, let started = optionDownAt,
        timestamp - started <= configuration.optionTapMilliseconds / 1_000,
        !optionHadCombination
      else { return RuntimeResponse(disposition: .passThrough) }
      if modeEnabled {
        return RuntimeResponse(disposition: .passThrough, effects: safetyExitEffects())
      }
      modeEnabled = true
      movementVelocity = Point(x: 0, y: 0)
      scrollVelocity = Point(x: 0, y: 0)
      return RuntimeResponse(
        disposition: .passThrough,
        effects: [
          .modeChanged(isEnabled: true), .indicator(isVisible: configuration.indicator.enabled),
        ])
    }
    guard modeEnabled, permissions.isReady else {
      return RuntimeResponse(disposition: .passThrough)
    }
    if let button = button(for: key), heldButtons.remove(button) != nil {
      pressedKeys.remove(key)
      return RuntimeResponse(disposition: .consume, effects: [.mouseButton(button, .up)])
    }
    pressedKeys.remove(key)
    return RuntimeResponse(disposition: isMappedKey(key) ? .consume : .passThrough)
  }

  private func frame(deltaTime: TimeInterval) -> RuntimeResponse {
    guard modeEnabled, permissions.isReady else {
      return RuntimeResponse(disposition: .passThrough)
    }
    let dt = deltaTime.isFinite ? max(deltaTime, 0) : 0
    let movementTarget =
      movementVector() * (configuration.movement.baseSpeed * movementMultiplier())
    movementVelocity = smoothed(
      current: movementVelocity, target: movementTarget, deltaTime: dt,
      timeConstant: configuration.movement.smoothingMilliseconds / 1_000)
    var effects: [RuntimeEffect] = []
    let candidate = Point(
      x: movementPoint.x + movementVelocity.x * dt, y: movementPoint.y + movementVelocity.y * dt)
    movementPoint = topology.constrainedMotionPoint(from: movementPoint, to: candidate)
    let projected = topology.projected(movementPoint)
    if projected != pointer {
      pointer = projected
      effects.append(.pointerMoved(to: pointer, buttons: heldButtons))
    }

    let scrollTarget = scrollVector() * (configuration.scrolling.baseSpeed * scrollMultiplier())
    scrollVelocity = smoothed(
      current: scrollVelocity, target: scrollTarget, deltaTime: dt,
      timeConstant: configuration.scrolling.smoothingMilliseconds / 1_000)
    scrollRemainder = scrollRemainder + scrollVelocity * dt
    let pixelsX = Int(scrollRemainder.x.rounded(.towardZero))
    let pixelsY = Int(scrollRemainder.y.rounded(.towardZero))
    scrollRemainder.x -= Double(pixelsX)
    scrollRemainder.y -= Double(pixelsY)
    if pixelsX != 0 || pixelsY != 0 { effects.append(.scroll(pixelX: pixelsX, pixelY: pixelsY)) }
    return RuntimeResponse(disposition: .passThrough, effects: effects)
  }

  private func safetyExitEffects() -> [RuntimeEffect] {
    var effects = heldButtons.sorted { $0.rawValue < $1.rawValue }.map {
      RuntimeEffect.mouseButton($0, .up)
    }
    heldButtons.removeAll()
    pressedKeys.removeAll()
    optionDownAt = nil
    optionHadCombination = false
    movementVelocity = Point(x: 0, y: 0)
    scrollVelocity = Point(x: 0, y: 0)
    scrollRemainder = Point(x: 0, y: 0)
    if modeEnabled {
      modeEnabled = false
      effects.append(.modeChanged(isEnabled: false))
      effects.append(.indicator(isVisible: false))
    }
    if !effects.isEmpty { effects.append(.diagnostic(.safetyExit)) }
    return effects
  }

  private func configurationKey(named name: String) -> Key { Key(configurationName: name) }

  private func button(for key: Key) -> MouseButton? {
    if key == configurationKey(named: configuration.bindings.leftClick) { return .left }
    if key == configurationKey(named: configuration.bindings.rightClick) { return .right }
    if key == configurationKey(named: configuration.bindings.middleClick) { return .middle }
    if key == configurationKey(named: configuration.bindings.backClick) { return .back }
    if key == configurationKey(named: configuration.bindings.forwardClick) { return .forward }
    return nil
  }

  private func isMappedKey(_ key: Key) -> Bool {
    let values = [
      configuration.bindings.escape, configuration.bindings.moveUp, configuration.bindings.moveDown,
      configuration.bindings.moveLeft, configuration.bindings.moveRight,
      configuration.bindings.leftClick,
      configuration.bindings.rightClick, configuration.bindings.middleClick,
      configuration.bindings.backClick,
      configuration.bindings.forwardClick, configuration.bindings.scrollUp,
      configuration.bindings.scrollDown,
      configuration.bindings.scrollLeft, configuration.bindings.scrollRight,
      configuration.bindings.precision,
      configuration.bindings.speedOne, configuration.bindings.speedTwo,
      configuration.bindings.speedThree,
    ]
    return values.map(configurationKey(named:)).contains(key)
  }

  private func movementVector() -> Point {
    let x =
      (pressedKeys.contains(configurationKey(named: configuration.bindings.moveRight)) ? 1.0 : 0)
      - (pressedKeys.contains(configurationKey(named: configuration.bindings.moveLeft)) ? 1.0 : 0)
    let y =
      (pressedKeys.contains(configurationKey(named: configuration.bindings.moveUp)) ? 1.0 : 0)
      - (pressedKeys.contains(configurationKey(named: configuration.bindings.moveDown)) ? 1.0 : 0)
    return normalized(Point(x: x, y: y))
  }

  private func scrollVector() -> Point {
    let x =
      (pressedKeys.contains(configurationKey(named: configuration.bindings.scrollRight)) ? 1.0 : 0)
      - (pressedKeys.contains(configurationKey(named: configuration.bindings.scrollLeft)) ? 1.0 : 0)
    let y =
      (pressedKeys.contains(configurationKey(named: configuration.bindings.scrollUp)) ? 1.0 : 0)
      - (pressedKeys.contains(configurationKey(named: configuration.bindings.scrollDown)) ? 1.0 : 0)
    return normalized(Point(x: x, y: y))
  }

  private func movementMultiplier() -> Double {
    let precision =
      pressedKeys.contains(configurationKey(named: configuration.bindings.precision))
      ? configuration.movement.precisionMultiplier : 1
    let fastKeys = [
      configuration.bindings.speedOne, configuration.bindings.speedTwo,
      configuration.bindings.speedThree,
    ].map(configurationKey(named:))
    return precision
      * pow(
        configuration.movement.fastMultiplier, Double(fastKeys.filter(pressedKeys.contains).count))
  }

  private func scrollMultiplier() -> Double {
    let precision =
      pressedKeys.contains(configurationKey(named: configuration.bindings.precision))
      ? configuration.scrolling.precisionMultiplier : 1
    let fastKeys = [
      configuration.bindings.speedOne, configuration.bindings.speedTwo,
      configuration.bindings.speedThree,
    ].map(configurationKey(named:))
    return precision
      * pow(
        configuration.scrolling.fastMultiplier, Double(fastKeys.filter(pressedKeys.contains).count))
  }

  private func normalized(_ vector: Point) -> Point {
    let length = sqrt(vector.x * vector.x + vector.y * vector.y)
    return length > 0 ? Point(x: vector.x / length, y: vector.y / length) : Point(x: 0, y: 0)
  }

  private func smoothed(current: Point, target: Point, deltaTime: Double, timeConstant: Double)
    -> Point
  {
    let alpha = timeConstant > 0 ? 1 - exp(-deltaTime / timeConstant) : 1
    return current + (target - current) * alpha
  }
}

private func + (lhs: Point, rhs: Point) -> Point { Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
private func - (lhs: Point, rhs: Point) -> Point { Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
private func * (lhs: Point, rhs: Double) -> Point { Point(x: lhs.x * rhs, y: lhs.y * rhs) }
