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
  public var postEvent: Bool

  public init(accessibility: Bool, postEvent: Bool) {
    self.accessibility = accessibility
    self.postEvent = postEvent
  }

  public static let none = PermissionState(accessibility: false, postEvent: false)
  public static let allGranted = PermissionState(accessibility: true, postEvent: true)

  public var isReady: Bool { accessibility && postEvent }
}

public enum PermissionRequestFeedback: Equatable, Sendable {
  case allGranted
  case openAccessibilitySettings

  public init(state: PermissionState) {
    self = state.isReady ? .allGranted : .openAccessibilitySettings
  }
}

public struct PermissionRequestCoordinator {
  private let request: () -> PermissionState
  private let apply: (PermissionState) -> Void
  private let present: (PermissionRequestFeedback) -> Void

  public init(
    request: @escaping () -> PermissionState,
    apply: @escaping (PermissionState) -> Void,
    present: @escaping (PermissionRequestFeedback) -> Void
  ) {
    self.request = request
    self.apply = apply
    self.present = present
  }

  public func run() {
    let state = request()
    apply(state)
    present(PermissionRequestFeedback(state: state))
  }
}

public enum Key: Hashable, Sendable {
  case leftCommand, rightCommand, leftControl, rightControl
  case leftOption, rightOption, leftShift, rightShift, capsLock, function
  case a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t, u, v, w, x, y, z
  case digit0, digit1, digit2, digit3, digit4, digit5, digit6, digit7, digit8, digit9
  case minus, equal, leftBracket, rightBracket, backslash, semicolon, quote, grave
  case comma, period, slash, space
  case keypad0, keypad1, keypad2, keypad3, keypad4, keypad5, keypad6, keypad7, keypad8, keypad9
  case keypadDecimal, keypadMultiply, keypadPlus, keypadClear, keypadDivide, keypadMinus
  case keypadEquals
  case isoSection, jisYen, jisUnderscore, jisKeypadComma, jisEisu, jisKana
  case returnKey, keypadEnter, delete, forwardDelete, tab, escape
  case arrowUp, arrowDown, arrowLeft, arrowRight, home, end, pageUp, pageDown
  case functionKey(Int), mediaKey(Int)
  case other(Int)

  fileprivate init(configurationName: String) {
    switch configurationName {
    case "leftOption": self = .leftOption
    case "rightOption": self = .rightOption
    case "escape": self = .escape
    case "a": self = .a
    case "b": self = .b
    case "c": self = .c
    case "d": self = .d
    case "e": self = .e
    case "f": self = .f
    case "g": self = .g
    case "h": self = .h
    case "i": self = .i
    case "j": self = .j
    case "k": self = .k
    case "l": self = .l
    case "m": self = .m
    case "n": self = .n
    case "o": self = .o
    case "p": self = .p
    case "q": self = .q
    case "r": self = .r
    case "s": self = .s
    case "t": self = .t
    case "u": self = .u
    case "v": self = .v
    case "w": self = .w
    case "x": self = .x
    case "y": self = .y
    case "z": self = .z
    case "digit0": self = .digit0
    case "digit1": self = .digit1
    case "digit2": self = .digit2
    case "digit3": self = .digit3
    case "digit4": self = .digit4
    case "digit5": self = .digit5
    case "digit6": self = .digit6
    case "digit7": self = .digit7
    case "digit8": self = .digit8
    case "digit9": self = .digit9
    case "0": self = .digit0
    case "1": self = .digit1
    case "2": self = .digit2
    case "3": self = .digit3
    case "4": self = .digit4
    case "5": self = .digit5
    case "6": self = .digit6
    case "7": self = .digit7
    case "8": self = .digit8
    case "9": self = .digit9
    case "minus": self = .minus
    case "equal": self = .equal
    case "leftBracket": self = .leftBracket
    case "rightBracket": self = .rightBracket
    case "backslash": self = .backslash
    case "semicolon": self = .semicolon
    case "quote": self = .quote
    case "grave": self = .grave
    case "comma": self = .comma
    case "period": self = .period
    case "slash": self = .slash
    case "space": self = .space
    case "keypad0": self = .keypad0
    case "keypad1": self = .keypad1
    case "keypad2": self = .keypad2
    case "keypad3": self = .keypad3
    case "keypad4": self = .keypad4
    case "keypad5": self = .keypad5
    case "keypad6": self = .keypad6
    case "keypad7": self = .keypad7
    case "keypad8": self = .keypad8
    case "keypad9": self = .keypad9
    case "keypadDecimal": self = .keypadDecimal
    case "keypadMultiply": self = .keypadMultiply
    case "keypadPlus": self = .keypadPlus
    case "keypadClear": self = .keypadClear
    case "keypadDivide": self = .keypadDivide
    case "keypadMinus": self = .keypadMinus
    case "keypadEquals": self = .keypadEquals
    case "isoSection": self = .isoSection
    case "jisYen": self = .jisYen
    case "jisUnderscore": self = .jisUnderscore
    case "jisKeypadComma": self = .jisKeypadComma
    case "jisEisu": self = .jisEisu
    case "jisKana": self = .jisKana
    default: self = .other(Int.min)
    }
  }

  fileprivate var isValidConfigurationKey: Bool {
    switch self {
    case .leftOption, .rightOption, .escape: return true
    default: return isProtectedCharacter
    }
  }

  fileprivate var isProtectedCharacter: Bool {
    switch self {
    case .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r, .s, .t, .u,
      .v, .w, .x, .y, .z,
      .digit0, .digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9,
      .minus, .equal, .leftBracket, .rightBracket, .backslash, .semicolon, .quote, .grave,
      .comma, .period, .slash, .space,
      .keypad0, .keypad1, .keypad2, .keypad3, .keypad4, .keypad5, .keypad6, .keypad7, .keypad8,
      .keypad9, .keypadDecimal, .keypadMultiply, .keypadPlus, .keypadDivide,
      .keypadMinus, .keypadEquals, .isoSection, .jisYen, .jisUnderscore, .jisKeypadComma,
      .jisEisu, .jisKana:
      return true
    default:
      return false
    }
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

public enum KeyboardEventPhase: Equatable, Sendable {
  case down, up
}

public struct KeyboardModifiers: OptionSet, Equatable, Sendable {
  public let rawValue: UInt16

  public init(rawValue: UInt16) {
    self.rawValue = rawValue
  }

  public static let leftCommand = KeyboardModifiers(rawValue: 1 << 0)
  public static let rightCommand = KeyboardModifiers(rawValue: 1 << 1)
  public static let leftControl = KeyboardModifiers(rawValue: 1 << 2)
  public static let rightControl = KeyboardModifiers(rawValue: 1 << 3)
  public static let leftOption = KeyboardModifiers(rawValue: 1 << 4)
  public static let rightOption = KeyboardModifiers(rawValue: 1 << 5)
  public static let leftShift = KeyboardModifiers(rawValue: 1 << 6)
  public static let rightShift = KeyboardModifiers(rawValue: 1 << 7)
  public static let capsLock = KeyboardModifiers(rawValue: 1 << 8)
  public static let function = KeyboardModifiers(rawValue: 1 << 9)

  public static let command: KeyboardModifiers = [.leftCommand, .rightCommand]
  public static let control: KeyboardModifiers = [.leftControl, .rightControl]
  public static let option: KeyboardModifiers = [.leftOption, .rightOption]
  public static let shift: KeyboardModifiers = [.leftShift, .rightShift]

  public var containsCommandOrControl: Bool {
    contains(.leftCommand) || contains(.rightCommand)
      || contains(.leftControl) || contains(.rightControl)
  }

  public static func modifier(for key: Key) -> KeyboardModifiers? {
    switch key {
    case .leftCommand: return .leftCommand
    case .rightCommand: return .rightCommand
    case .leftControl: return .leftControl
    case .rightControl: return .rightControl
    case .leftOption: return .leftOption
    case .rightOption: return .rightOption
    case .leftShift: return .leftShift
    case .rightShift: return .rightShift
    case .capsLock: return .capsLock
    case .function: return .function
    default: return nil
    }
  }
}

public struct KeyboardEvent: Equatable, Sendable {
  public let key: Key
  public let phase: KeyboardEventPhase
  public let timestamp: TimeInterval
  public let isAutoRepeat: Bool
  public let modifiers: KeyboardModifiers

  public init(
    key: Key, phase: KeyboardEventPhase, timestamp: TimeInterval, isAutoRepeat: Bool,
    modifiers: KeyboardModifiers
  ) {
    self.key = key
    self.phase = phase
    self.timestamp = timestamp
    self.isAutoRepeat = isAutoRepeat
    self.modifiers = modifiers
  }
}

public enum EventDisposition: Equatable, Sendable {
  case passThrough
  case consume
}

public enum Diagnostic: Equatable, Sendable {
  case safetyExit
  case eventTapDisabled
  case eventTapRecovered
  case eventTapRecoveryFailed
  case cursorHaloUnavailable
  case configurationAccepted
  case configurationRejected
}

public enum DiagnosticConfigurationStatus: String, Equatable, Sendable {
  case valid
  case invalid
}

public enum DiagnosticEventTapStatus: String, Equatable, Sendable {
  case unknown
  case healthy
  case unavailable
  case recovering
  case recoveryFailed
}

public struct DiagnosticCounters: Equatable, Sendable {
  public var callbackCount: Int
  public var callbackLatencySampleCount: Int
  public var totalCallbackLatencyMilliseconds: Double
  public var maximumCallbackLatencyMilliseconds: Double
  public var frameCount: Int
  public var modeChangeCount: Int
  public var safetyExitCount: Int
  public var eventTapDisabledCount: Int
  public var eventTapRecoveryCount: Int
  public var eventTapRecoveryFailureCount: Int
  public var configurationAcceptedCount: Int
  public var configurationRejectedCount: Int
  public var cursorHaloPresentationFailureCount: Int
  public var pointerEffectCount: Int
  public var mouseButtonEffectCount: Int
  public var scrollEffectCount: Int

  public init(
    callbackCount: Int = 0, callbackLatencySampleCount: Int = 0,
    totalCallbackLatencyMilliseconds: Double = 0,
    maximumCallbackLatencyMilliseconds: Double = 0, frameCount: Int = 0,
    modeChangeCount: Int = 0, safetyExitCount: Int = 0, eventTapDisabledCount: Int = 0,
    eventTapRecoveryCount: Int = 0, eventTapRecoveryFailureCount: Int = 0,
    configurationAcceptedCount: Int = 0, configurationRejectedCount: Int = 0,
    cursorHaloPresentationFailureCount: Int = 0,
    pointerEffectCount: Int = 0, mouseButtonEffectCount: Int = 0, scrollEffectCount: Int = 0
  ) {
    self.callbackCount = callbackCount
    self.callbackLatencySampleCount = callbackLatencySampleCount
    self.totalCallbackLatencyMilliseconds = totalCallbackLatencyMilliseconds
    self.maximumCallbackLatencyMilliseconds = maximumCallbackLatencyMilliseconds
    self.frameCount = frameCount
    self.modeChangeCount = modeChangeCount
    self.safetyExitCount = safetyExitCount
    self.eventTapDisabledCount = eventTapDisabledCount
    self.eventTapRecoveryCount = eventTapRecoveryCount
    self.eventTapRecoveryFailureCount = eventTapRecoveryFailureCount
    self.configurationAcceptedCount = configurationAcceptedCount
    self.configurationRejectedCount = configurationRejectedCount
    self.cursorHaloPresentationFailureCount = cursorHaloPresentationFailureCount
    self.pointerEffectCount = pointerEffectCount
    self.mouseButtonEffectCount = mouseButtonEffectCount
    self.scrollEffectCount = scrollEffectCount
  }

  public mutating func recordCallback(duration: TimeInterval) -> Int? {
    callbackCount += 1
#if DEBUG
    if duration.isFinite, duration >= 0 {
      callbackLatencySampleCount += 1
      let milliseconds = duration * 1_000
      totalCallbackLatencyMilliseconds += milliseconds
      maximumCallbackLatencyMilliseconds = max(maximumCallbackLatencyMilliseconds, milliseconds)
    }
    return callbackCount.isMultiple(of: 128) ? callbackCount : nil
#else
    return nil
#endif
  }

  public mutating func recordFrame() {
    frameCount += 1
  }

  public mutating func record(_ effects: [RuntimeEffect]) {
    for effect in effects {
      switch effect {
      case .pointerMoved, .pointerPositionChanged: pointerEffectCount += 1
      case .mouseButton: mouseButtonEffectCount += 1
      case .scroll: scrollEffectCount += 1
      case .modeChanged: modeChangeCount += 1
      case .diagnostic(.safetyExit): safetyExitCount += 1
      case .diagnostic(.eventTapDisabled): eventTapDisabledCount += 1
      case .diagnostic(.eventTapRecovered): eventTapRecoveryCount += 1
      case .diagnostic(.eventTapRecoveryFailed): eventTapRecoveryFailureCount += 1
      case .diagnostic(.configurationAccepted): configurationAcceptedCount += 1
      case .diagnostic(.configurationRejected): configurationRejectedCount += 1
      case .diagnostic(.cursorHaloUnavailable): cursorHaloPresentationFailureCount += 1
      default: break
      }
    }
  }
}

public struct DiagnosticSummary: Equatable, Sendable {
  public let version: String
  public let buildIdentity: String
  public let permissions: PermissionState
  public let configuration: DiagnosticConfigurationStatus
  public let eventTap: DiagnosticEventTapStatus
  public let counters: DiagnosticCounters

  public init(
    version: String, buildIdentity: String, permissions: PermissionState,
    configuration: DiagnosticConfigurationStatus, eventTap: DiagnosticEventTapStatus,
    counters: DiagnosticCounters
  ) {
    self.version = version
    self.buildIdentity = buildIdentity
    self.permissions = permissions
    self.configuration = configuration
    self.eventTap = eventTap
    self.counters = counters
  }

  public var text: String {
    let counters = counters
    return [
      "Keyveer diagnostics",
      "version: \(singleLine(version))",
      "buildIdentity: \(singleLine(buildIdentity))",
      "permissions: accessibility=\(permissions.accessibility), postEvent=\(permissions.postEvent)",
      "configuration: \(configuration.rawValue)",
      "eventTap: \(eventTap.rawValue)",
      "callbacks: \(counters.callbackCount)",
      "callbackLatencySamples: \(counters.callbackLatencySampleCount)",
      "totalCallbackLatencyMilliseconds: \(counters.totalCallbackLatencyMilliseconds)",
      "maximumCallbackLatencyMilliseconds: \(counters.maximumCallbackLatencyMilliseconds)",
      "frames: \(counters.frameCount)",
      "modeChanges: \(counters.modeChangeCount)",
      "safetyExits: \(counters.safetyExitCount)",
      "eventTapDisabled: \(counters.eventTapDisabledCount)",
      "eventTapRecoveries: \(counters.eventTapRecoveryCount)",
      "eventTapRecoveryFailures: \(counters.eventTapRecoveryFailureCount)",
      "configurationAccepted: \(counters.configurationAcceptedCount)",
      "configurationRejected: \(counters.configurationRejectedCount)",
      "cursorHaloPresentationFailures: \(counters.cursorHaloPresentationFailureCount)",
      "pointerEffects: \(counters.pointerEffectCount)",
      "mouseButtonEffects: \(counters.mouseButtonEffectCount)",
      "scrollEffects: \(counters.scrollEffectCount)",
    ].joined(separator: "\n")
  }
}

private func singleLine(_ value: String) -> String {
  value.replacingOccurrences(of: "\n", with: " ")
    .replacingOccurrences(of: "\r", with: " ")
}

public enum RuntimeEffect: Equatable, Sendable {
  case capabilitiesChanged(PermissionState)
  case freeModeStatusChanged(FreeModeStatus)
  case modeChanged(isEnabled: Bool)
  case cursorHalo(isVisible: Bool)
  case cursorHaloDiameterChanged(diameter: Double)
  case pointerPositionChanged(to: Point)
  case pointerMoved(to: Point, buttons: Set<MouseButton>)
  case mouseButton(MouseButton, ButtonPhase)
  case scroll(pixelX: Int, pixelY: Int)
  case configurationAccepted
  case configurationRejected(reason: String)
  case eventTapShouldBeReenabled
  case diagnostic(Diagnostic)
}

/// Converts the runtime's horizontal scroll direction to Core Graphics' wheel-2 direction.
public enum ScrollEventMapping {
  public static func coreGraphicsWheel2Value(forHorizontalPixelDelta delta: Int) -> Int {
    -delta
  }
}

public enum FreeModeStatus: String, Equatable, Sendable {
  case available
  case enabled
  case unavailable

  public var symbol: String {
    switch self {
    case .available: return "○"
    case .enabled: return "●"
    case .unavailable: return "!"
    }
  }

  public var menuBarSymbolName: String {
    switch self {
    case .available: return "computermouse"
    case .enabled: return "computermouse.fill"
    case .unavailable: return "exclamationmark.triangle.fill"
    }
  }

  public var accessibilityDescription: String {
    switch self {
    case .available: return "Keyveer: available; free mode is off."
    case .enabled: return "Keyveer: enabled; free mode is on."
    case .unavailable: return "Keyveer: unavailable; free mode is off."
    }
  }
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
  case locked
  case sleeping
  case waking
}

public struct RuntimeEvent {
  fileprivate enum Kind {
    case keyboard(KeyboardEvent)
    case modifierChanged(Key, isPressed: Bool, timestamp: TimeInterval)
    case frame(deltaTime: TimeInterval)
    case pointerMoved(Point, source: PointerSource)
    case topologyChanged(DisplayTopology)
    case permissionsChanged(PermissionState)
    case sessionChanged(SessionState)
    case eventTapReady
    case eventTapDisabled
    case eventTapReenabled
    case eventTapRecoveryFailed
    case cursorHaloPresentationFailed
    case configuration(Data)
    case shutdown
  }

  fileprivate enum PointerSource { case physical, synthesized }
  fileprivate let kind: Kind

  public static func keyboard(_ event: KeyboardEvent) -> RuntimeEvent {
    RuntimeEvent(kind: .keyboard(event))
  }

  public static func keyDown(
    _ key: Key, at timestamp: TimeInterval, isAutoRepeat: Bool = false,
    modifiers: KeyboardModifiers = []
  ) -> RuntimeEvent {
    keyboard(
      KeyboardEvent(
        key: key, phase: .down, timestamp: timestamp, isAutoRepeat: isAutoRepeat,
        modifiers: modifiers))
  }

  public static func keyUp(
    _ key: Key, at timestamp: TimeInterval, modifiers: KeyboardModifiers = []
  ) -> RuntimeEvent {
    keyboard(
      KeyboardEvent(
        key: key, phase: .up, timestamp: timestamp, isAutoRepeat: false, modifiers: modifiers))
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

  public static let eventTapReady = RuntimeEvent(kind: .eventTapReady)

  public static let eventTapReenabled = RuntimeEvent(kind: .eventTapReenabled)

  public static let eventTapRecoveryFailed = RuntimeEvent(kind: .eventTapRecoveryFailed)

  public static let cursorHaloPresentationFailed = RuntimeEvent(kind: .cursorHaloPresentationFailed)

  public static func configuration(_ data: Data) -> RuntimeEvent {
    RuntimeEvent(kind: .configuration(data))
  }

  public static let shutdown = RuntimeEvent(kind: .shutdown)
}

public struct KeyBindings: Codable, Equatable, Sendable {
  public var activation: String
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
    activation: String = "leftOption",
    moveUp: String = "i", moveDown: String = "k", moveLeft: String = "j", moveRight: String = "l",
    leftClick: String = "space", rightClick: String = "r", middleClick: String = "e",
    backClick: String = "q", forwardClick: String = "w", scrollUp: String = "m",
    scrollDown: String = "comma", scrollLeft: String = "period", scrollRight: String = "slash",
    precision: String = "a", speedOne: String = "s", speedTwo: String = "d",
    speedThree: String = "f"
  ) {
    self.activation = activation
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
    case activation, moveUp, moveDown, moveLeft, moveRight, leftClick, rightClick, middleClick
    case backClick, forwardClick, scrollUp, scrollDown, scrollLeft, scrollRight, precision
    case speedOne, speedTwo, speedThree
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
    self.init(
      activation: try container.decode(String.self, forKey: .activation),
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

private struct LegacyIndicatorSettings: Codable, Equatable, Sendable {
  public var enabled: Bool
  public var size: Double

  init(enabled: Bool = false, size: Double = 8) {
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

public struct CursorHaloSettings: Codable, Equatable, Sendable {
  public var enabled: Bool
  public var diameter: Double

  public init(enabled: Bool = true, diameter: Double = 28) {
    self.enabled = enabled
    self.diameter = diameter
  }

  private enum CodingKeys: String, CodingKey, CaseIterable { case enabled, diameter }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
    self.init(
      enabled: try container.decode(Bool.self, forKey: .enabled),
      diameter: try container.decode(Double.self, forKey: .diameter))
  }
}

private struct LegacyKeyBindings: Codable {
  let toggle: String
  let escape: String
  let moveUp: String
  let moveDown: String
  let moveLeft: String
  let moveRight: String
  let leftClick: String
  let rightClick: String
  let middleClick: String
  let backClick: String
  let forwardClick: String
  let scrollUp: String
  let scrollDown: String
  let scrollLeft: String
  let scrollRight: String
  let precision: String
  let speedOne: String
  let speedTwo: String
  let speedThree: String

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case toggle, escape, moveUp, moveDown, moveLeft, moveRight, leftClick, rightClick, middleClick
    case backClick, forwardClick, scrollUp, scrollDown, scrollLeft, scrollRight, precision
    case speedOne, speedTwo, speedThree
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.stringValue))
    toggle = try container.decode(String.self, forKey: .toggle)
    escape = try container.decode(String.self, forKey: .escape)
    moveUp = try container.decode(String.self, forKey: .moveUp)
    moveDown = try container.decode(String.self, forKey: .moveDown)
    moveLeft = try container.decode(String.self, forKey: .moveLeft)
    moveRight = try container.decode(String.self, forKey: .moveRight)
    leftClick = try container.decode(String.self, forKey: .leftClick)
    rightClick = try container.decode(String.self, forKey: .rightClick)
    middleClick = try container.decode(String.self, forKey: .middleClick)
    backClick = try container.decode(String.self, forKey: .backClick)
    forwardClick = try container.decode(String.self, forKey: .forwardClick)
    scrollUp = try container.decode(String.self, forKey: .scrollUp)
    scrollDown = try container.decode(String.self, forKey: .scrollDown)
    scrollLeft = try container.decode(String.self, forKey: .scrollLeft)
    scrollRight = try container.decode(String.self, forKey: .scrollRight)
    precision = try container.decode(String.self, forKey: .precision)
    speedOne = try container.decode(String.self, forKey: .speedOne)
    speedTwo = try container.decode(String.self, forKey: .speedTwo)
    speedThree = try container.decode(String.self, forKey: .speedThree)
  }

  var migrated: KeyBindings {
    KeyBindings(
      activation: toggle, moveUp: moveUp, moveDown: moveDown, moveLeft: moveLeft,
      moveRight: moveRight, leftClick: leftClick, rightClick: rightClick,
      middleClick: middleClick, backClick: backClick, forwardClick: forwardClick,
      scrollUp: scrollUp, scrollDown: scrollDown, scrollLeft: scrollLeft,
      scrollRight: scrollRight, precision: precision, speedOne: speedOne,
      speedTwo: speedTwo, speedThree: speedThree)
  }
}

public struct RuntimeConfiguration: Codable, Equatable, Sendable {
  public var schemaVersion: Int
  public var bindings: KeyBindings
  public var movement: MotionSettings
  public var scrolling: ScrollSettings
  public var optionTapMilliseconds: Double
  public var cursorHalo: CursorHaloSettings

  public init(
    schemaVersion: Int = 3, bindings: KeyBindings = KeyBindings(),
    movement: MotionSettings = MotionSettings(), scrolling: ScrollSettings = ScrollSettings(),
    optionTapMilliseconds: Double = 250, cursorHalo: CursorHaloSettings = CursorHaloSettings()
  ) {
    self.schemaVersion = schemaVersion
    self.bindings = bindings
    self.movement = movement
    self.scrolling = scrolling
    self.optionTapMilliseconds = optionTapMilliseconds
    self.cursorHalo = cursorHalo
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion, bindings, movement, scrolling, optionTapMilliseconds, cursorHalo
  }

  private enum DecodingKeys: String, CodingKey, CaseIterable {
    case schemaVersion, bindings, movement, scrolling, optionTapMilliseconds, indicator, cursorHalo
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: DecodingKeys.self)
    try rejectUnknownKeys(decoder, allowed: DecodingKeys.allCases.map(\.stringValue))
    let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    guard schemaVersion == 1 || schemaVersion == 2 || schemaVersion == 3 else {
      throw ConfigurationError.unsupportedSchemaVersion(schemaVersion)
    }
    let movement = try container.decode(MotionSettings.self, forKey: .movement)
    let scrolling = try container.decode(ScrollSettings.self, forKey: .scrolling)
    let optionTapMilliseconds = try container.decode(Double.self, forKey: .optionTapMilliseconds)
    let legacyIndicator = try container.decodeIfPresent(LegacyIndicatorSettings.self, forKey: .indicator)
    switch schemaVersion {
    case 1:
      let legacy = try container.decode(LegacyKeyBindings.self, forKey: .bindings)
      _ = legacyIndicator
      self.init(
        schemaVersion: 3, bindings: legacy.migrated, movement: movement, scrolling: scrolling,
        optionTapMilliseconds: optionTapMilliseconds)
    case 2:
      self.init(
        schemaVersion: 3, bindings: try container.decode(KeyBindings.self, forKey: .bindings),
        movement: movement, scrolling: scrolling, optionTapMilliseconds: optionTapMilliseconds,
        cursorHalo: CursorHaloSettings())
      _ = legacyIndicator
    case 3:
      guard !container.contains(.indicator) else {
        throw ConfigurationError.unknownFields(["indicator"])
      }
      self.init(
        schemaVersion: 3, bindings: try container.decode(KeyBindings.self, forKey: .bindings),
        movement: movement, scrolling: scrolling, optionTapMilliseconds: optionTapMilliseconds,
        cursorHalo: try container.decode(CursorHaloSettings.self, forKey: .cursorHalo))
    default:
      throw ConfigurationError.unsupportedSchemaVersion(schemaVersion)
    }
  }

  public func validated() throws -> RuntimeConfiguration {
    guard schemaVersion == 3 else {
      throw ConfigurationError.unsupportedSchemaVersion(schemaVersion)
    }
    try validate(
      optionTapMilliseconds, named: "optionTapMilliseconds", range: 0.001...1_000)
    try validate(movement.baseSpeed, named: "movement.baseSpeed", range: 1...10_000)
    try validate(
      movement.precisionMultiplier, named: "movement.precisionMultiplier", range: 0.001...1)
    try validate(movement.fastMultiplier, named: "movement.fastMultiplier", range: 1...10)
    try validate(
      movement.smoothingMilliseconds, named: "movement.smoothingMilliseconds", range: 1...1_000)
    try validate(scrolling.baseSpeed, named: "scrolling.baseSpeed", range: 1...50_000)
    try validate(
      scrolling.precisionMultiplier, named: "scrolling.precisionMultiplier", range: 0.001...1)
    try validate(scrolling.fastMultiplier, named: "scrolling.fastMultiplier", range: 1...10)
    try validate(
      scrolling.smoothingMilliseconds, named: "scrolling.smoothingMilliseconds", range: 1...1_000)
    try validate(cursorHalo.diameter, named: "cursorHalo.diameter", range: 4...200)

    let activation = Key(configurationName: bindings.activation)
    guard activation == .leftOption || activation == .rightOption else {
      throw ConfigurationError.invalidActivationKey(bindings.activation)
    }
    let namedBindings = [
      ("activation", bindings.activation), ("moveUp", bindings.moveUp),
      ("moveDown", bindings.moveDown), ("moveLeft", bindings.moveLeft),
      ("moveRight", bindings.moveRight), ("leftClick", bindings.leftClick),
      ("rightClick", bindings.rightClick), ("middleClick", bindings.middleClick),
      ("backClick", bindings.backClick), ("forwardClick", bindings.forwardClick),
      ("scrollUp", bindings.scrollUp), ("scrollDown", bindings.scrollDown),
      ("scrollLeft", bindings.scrollLeft), ("scrollRight", bindings.scrollRight),
      ("precision", bindings.precision), ("speedOne", bindings.speedOne),
      ("speedTwo", bindings.speedTwo), ("speedThree", bindings.speedThree),
    ]
    if let reserved = namedBindings.first(where: { $0.1 == "escape" }) {
      throw ConfigurationError.reservedKey(name: reserved.0, value: reserved.1)
    }
    if let invalid = namedBindings.first(where: { !Key(configurationName: $0.1).isValidConfigurationKey }) {
      throw ConfigurationError.invalidKey(name: invalid.0, value: invalid.1)
    }
    var bindingNamesByValue: [String: [String]] = [:]
    for (name, value) in namedBindings {
      bindingNamesByValue[value, default: []].append(name)
    }
    let duplicates = bindingNamesByValue
      .filter { $0.value.count > 1 }
      .flatMap { $0.value }
      .sorted()
    if !duplicates.isEmpty {
      throw ConfigurationError.duplicateBindings(duplicates)
    }
    return self
  }

  public static var defaultJSON: Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try! encoder.encode(RuntimeConfiguration())
  }
}

public struct BindingReferenceItem: Equatable, Sendable {
  public let key: String
  public let action: String

  public init(key: String, action: String) {
    self.key = key
    self.action = action
  }
}

public struct BindingReferenceSection: Equatable, Sendable {
  public let title: String
  public let items: [BindingReferenceItem]

  public init(title: String, items: [BindingReferenceItem]) {
    self.title = title
    self.items = items
  }
}

public struct BindingReference: Equatable, Sendable {
  public let sections: [BindingReferenceSection]
  public let safetyExit: BindingReferenceItem

  public init(bindings: KeyBindings) {
    func item(_ key: String, _ action: String) -> BindingReferenceItem {
      BindingReferenceItem(key: bindingKeyLabel(key), action: action)
    }

    sections = [
      BindingReferenceSection(
        title: "Activation", items: [item(bindings.activation, "Tap to Enter")]),
      BindingReferenceSection(
        title: "Movement",
        items: [
          item(bindings.moveUp, "Up"), item(bindings.moveLeft, "Left"),
          item(bindings.moveDown, "Down"), item(bindings.moveRight, "Right"),
        ]),
      BindingReferenceSection(
        title: "Mouse Buttons",
        items: [
          item(bindings.leftClick, "Left Click"), item(bindings.rightClick, "Right Click"),
          item(bindings.middleClick, "Middle Click"), item(bindings.backClick, "Back"),
          item(bindings.forwardClick, "Forward"),
        ]),
      BindingReferenceSection(
        title: "Scrolling",
        items: [
          item(bindings.scrollUp, "Up"), item(bindings.scrollDown, "Down"),
          item(bindings.scrollLeft, "Left"), item(bindings.scrollRight, "Right"),
        ]),
      BindingReferenceSection(
        title: "Speed",
        items: [
          item(bindings.precision, "Precision"), item(bindings.speedOne, "Fast 1"),
          item(bindings.speedTwo, "Fast 2"), item(bindings.speedThree, "Fast 3"),
        ]),
    ]
    safetyExit = BindingReferenceItem(key: "Left Option", action: "Exit Free Mode")
  }
}

private func bindingKeyLabel(_ name: String) -> String {
  let labels = [
    "leftOption": "Left Option", "rightOption": "Right Option", "space": "Space",
    "minus": "−", "equal": "=", "leftBracket": "[", "rightBracket": "]",
    "backslash": "\\", "semicolon": ";", "quote": "'", "grave": "`", "comma": ",",
    "period": ".", "slash": "/", "keypadDecimal": "Keypad .",
    "keypadMultiply": "Keypad ×", "keypadPlus": "Keypad +", "keypadDivide": "Keypad ÷",
    "keypadMinus": "Keypad −", "keypadEquals": "Keypad =", "isoSection": "§",
    "jisYen": "¥", "jisUnderscore": "JIS _", "jisKeypadComma": "Keypad ,",
    "jisEisu": "英数", "jisKana": "かな",
  ]
  if let label = labels[name] { return label }
  if name.hasPrefix("keypad"), let number = name.last, number.isNumber {
    return "Keypad \(number)"
  }
  if name.hasPrefix("digit"), let number = name.last, number.isNumber { return String(number) }
  if name.count == 1 { return name.uppercased() }
  return name
}

public enum ConfigurationError: Error, Equatable, Sendable, LocalizedError {
  case invalidJSON
  case unknownFields([String])
  case unsupportedSchemaVersion(Int)
  case duplicateBindings([String])
  case invalidValue(name: String, description: String)
  case invalidKey(name: String, value: String)
  case invalidActivationKey(String)
  case reservedKey(name: String, value: String)

  public var errorDescription: String? {
    switch self {
    case .invalidJSON:
      return "invalid JSON configuration"
    case .unknownFields(let fields):
      return "unknown field(s) in configuration: " + fields.sorted().joined(separator: ", ")
    case .unsupportedSchemaVersion(let version):
      return "unsupported configuration schema version: " + String(version)
    case .duplicateBindings(let bindings):
      return "duplicate binding key(s): " + bindings.sorted().joined(separator: ", ")
    case .invalidValue(let name, let description):
      return "invalid configuration value for " + name + ": " + description
    case .invalidKey(let name, let value):
      return "unsupported key for " + name + ": " + value
    case .invalidActivationKey(let value):
      return "invalid activation key \(value); activation must be leftOption or rightOption"
    case .reservedKey(let name, let value):
      return "reserved key for \(name): \(value); physical Escape cannot be a Keyveer binding"
    }
  }
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
  let unknown = container.allKeys.map(\.stringValue).filter { !allowed.contains($0) }.sorted()
  if !unknown.isEmpty {
    throw ConfigurationError.unknownFields(unknown)
  }
}

private func validate(_ value: Double, named name: String, range: ClosedRange<Double>) throws {
  guard value.isFinite, range.contains(value) else {
    throw ConfigurationError.invalidValue(
      name: name,
      description: "must be between \(range.lowerBound) and \(range.upperBound)")
  }
}

private func decodingErrorDescription(_ error: Error) -> String {
  let path: ([any CodingKey]) -> String = { codingPath in
    codingPath.map(\.stringValue).joined(separator: ".")
  }
  switch error {
  case DecodingError.keyNotFound(let key, let context):
    let prefix = path(context.codingPath)
    return "invalid JSON configuration: missing field " + (prefix.isEmpty ? key.stringValue : prefix + "." + key.stringValue)
  case DecodingError.typeMismatch(_, let context):
    let location = path(context.codingPath)
    return "invalid JSON configuration: invalid value type at " + (location.isEmpty ? "root" : location)
  case DecodingError.valueNotFound(_, let context):
    let location = path(context.codingPath)
    return "invalid JSON configuration: missing value at " + (location.isEmpty ? "root" : location)
  case DecodingError.dataCorrupted(let context):
    let location = path(context.codingPath)
    return "invalid JSON configuration: " + (location.isEmpty ? context.debugDescription : location + ": " + context.debugDescription)
  default:
    return "invalid JSON configuration"
  }
}

public final class KeyveerRuntime {
  private var configuration: RuntimeConfiguration
  private var permissions: PermissionState
  private var eventTapHealthy: Bool
  private var sessionIsActive = true
  private var modeEnabled = false
  private var topology: DisplayTopology
  private var pointer = Point(x: 0, y: 0)
  private var movementPoint = Point(x: 0, y: 0)
  private var pressedKeys: Set<Key> = []
  private var keyboardDispositions: [Key: EventDisposition] = [:]
  private var activeModifiers: KeyboardModifiers = []
  private var heldButtons: Set<MouseButton> = []
  private var activationDownAt: TimeInterval?
  private var activationHadCombination = false
  private var leftOptionSafetyExitHeld = false
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
    self.eventTapHealthy = permissions.isReady
    self.topology = topology
    self.pointer = topology.projected(pointer)
    self.movementPoint = self.pointer
  }

  public func handle(_ event: RuntimeEvent) -> RuntimeResponse {
    switch event.kind {
    case .keyboard(let keyboardEvent): return keyboard(keyboardEvent)
    case .modifierChanged(let key, let isPressed, let timestamp):
      var modifiers = activeModifiers
      if let modifier = KeyboardModifiers.modifier(for: key) {
        if isPressed {
          modifiers.insert(modifier)
        } else {
          modifiers.remove(modifier)
        }
      }
      return keyboard(
        KeyboardEvent(
          key: key, phase: isPressed ? .down : .up, timestamp: timestamp,
          isAutoRepeat: false, modifiers: modifiers))
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
      let previousStatus = freeModeStatus
      permissions = newPermissions
      if !newPermissions.isReady { eventTapHealthy = false }
      var effects = [RuntimeEffect.capabilitiesChanged(newPermissions)]
      if !newPermissions.isReady {
        effects.append(contentsOf: safetyExitEffects(emitDiagnostic: true))
      }
      effects.append(contentsOf: freeModeStatusEffects(changedFrom: previousStatus))
      return RuntimeResponse(disposition: .passThrough, effects: effects)
    case .sessionChanged(let state):
      let previousStatus = freeModeStatus
      switch state {
      case .active:
        sessionIsActive = true
        return RuntimeResponse(
          disposition: .passThrough,
          effects: freeModeStatusEffects(changedFrom: previousStatus))
      case .waking:
        sessionIsActive = false
        var effects = safetyExitEffects()
        effects.append(contentsOf: freeModeStatusEffects(changedFrom: previousStatus))
        return RuntimeResponse(disposition: .passThrough, effects: effects)
      case .inactive, .locked, .sleeping:
        sessionIsActive = false
        var effects = safetyExitEffects(emitDiagnostic: true)
        effects.append(contentsOf: freeModeStatusEffects(changedFrom: previousStatus))
        return RuntimeResponse(disposition: .passThrough, effects: effects)
      }
    case .eventTapReady:
      let previousStatus = freeModeStatus
      eventTapHealthy = permissions.isReady
      return RuntimeResponse(
        disposition: .passThrough,
        effects: freeModeStatusEffects(changedFrom: previousStatus))
    case .eventTapDisabled:
      let previousStatus = freeModeStatus
      eventTapHealthy = false
      var effects = safetyExitEffects(emitDiagnostic: true)
      effects.append(.eventTapShouldBeReenabled)
      effects.append(.diagnostic(.eventTapDisabled))
      effects.append(contentsOf: freeModeStatusEffects(changedFrom: previousStatus))
      return RuntimeResponse(
        disposition: .passThrough,
        effects: effects)
    case .eventTapReenabled:
      let previousStatus = freeModeStatus
      eventTapHealthy = permissions.isReady
      var effects = [RuntimeEffect.diagnostic(.eventTapRecovered)]
      effects.append(contentsOf: freeModeStatusEffects(changedFrom: previousStatus))
      return RuntimeResponse(
        disposition: .passThrough, effects: effects)
    case .eventTapRecoveryFailed:
      let previousStatus = freeModeStatus
      eventTapHealthy = false
      var effects = safetyExitEffects(emitDiagnostic: true)
      effects.append(.diagnostic(.eventTapRecoveryFailed))
      effects.append(contentsOf: freeModeStatusEffects(changedFrom: previousStatus))
      return RuntimeResponse(disposition: .passThrough, effects: effects)
    case .cursorHaloPresentationFailed:
      return RuntimeResponse(
        disposition: .passThrough, effects: [.diagnostic(.cursorHaloUnavailable)])
    case .configuration(let data):
      do {
        let decoded = try JSONDecoder().decode(RuntimeConfiguration.self, from: data).validated()
        let releasedButtons = heldButtons.sorted { $0.rawValue < $1.rawValue }.map {
          RuntimeEffect.mouseButton($0, .up)
        }
        configuration = decoded
        heldButtons.removeAll()
        pressedKeys.removeAll()
        keyboardDispositions.removeAll()
        activeModifiers = []
        activationDownAt = nil
        activationHadCombination = false
        leftOptionSafetyExitHeld = false
        movementVelocity = Point(x: 0, y: 0)
        scrollVelocity = Point(x: 0, y: 0)
        scrollRemainder = Point(x: 0, y: 0)
        var effects = releasedButtons
        effects.append(.configurationAccepted)
        effects.append(.diagnostic(.configurationAccepted))
        if modeEnabled {
          effects.append(.cursorHaloDiameterChanged(diameter: decoded.cursorHalo.diameter))
          effects.append(.cursorHalo(isVisible: decoded.cursorHalo.enabled))
        }
        return RuntimeResponse(
          disposition: .passThrough,
          effects: effects)
      } catch let error as ConfigurationError {
        return RuntimeResponse(
          disposition: .passThrough,
          effects: [
            .configurationRejected(reason: error.errorDescription ?? "invalid JSON configuration"),
            .diagnostic(.configurationRejected),
          ])
      } catch {
        return RuntimeResponse(
          disposition: .passThrough,
          effects: [
            .configurationRejected(reason: decodingErrorDescription(error)),
            .diagnostic(.configurationRejected),
          ])
      }
    case .shutdown:
      return RuntimeResponse(
        disposition: .passThrough, effects: safetyExitEffects(emitDiagnostic: true))
    }
  }

  public var freeModeStatus: FreeModeStatus {
    guard sessionIsActive && permissions.isReady && eventTapHealthy else { return .unavailable }
    return modeEnabled ? .enabled : .available
  }

  public var bindingReference: BindingReference {
    BindingReference(bindings: configuration.bindings)
  }

  private func keyboard(_ event: KeyboardEvent) -> RuntimeResponse {
    activeModifiers = event.modifiers
    switch event.phase {
    case .down:
      return keyDown(
        event.key, timestamp: event.timestamp, isAutoRepeat: event.isAutoRepeat,
        modifiers: event.modifiers)
    case .up:
      return keyUp(event.key, timestamp: event.timestamp)
    }
  }

  private func keyDown(
    _ key: Key, timestamp: TimeInterval, isAutoRepeat: Bool, modifiers: KeyboardModifiers
  ) -> RuntimeResponse {
    if key == .leftOption, modeEnabled {
      leftOptionSafetyExitHeld = true
      return RuntimeResponse(
        disposition: .passThrough,
        effects: safetyExitEffects(preserveKeyboardDispositions: true))
    }
    if leftOptionSafetyExitHeld {
      if isAutoRepeat, let disposition = keyboardDispositions[key] {
        return RuntimeResponse(disposition: disposition)
      }
      guard !isAutoRepeat else { return RuntimeResponse(disposition: .passThrough) }
      let disposition: EventDisposition =
        key.isProtectedCharacter && !modifiers.containsCommandOrControl ? .consume : .passThrough
      keyboardDispositions[key] = disposition
      return RuntimeResponse(disposition: disposition)
    }
    if key == configurationKey(named: configuration.bindings.activation) {
      if !isAutoRepeat {
        activationDownAt = timestamp
        let activationModifier = KeyboardModifiers.modifier(for: key) ?? []
        let persistentCapsLock = KeyboardModifiers.capsLock
        activationHadCombination = !modifiers
          .subtracting(activationModifier)
          .subtracting(persistentCapsLock)
          .isEmpty
        keyboardDispositions[key] = .passThrough
      }
      return RuntimeResponse(disposition: .passThrough)
    }
    if activationDownAt != nil { activationHadCombination = true }
    if isAutoRepeat, let disposition = keyboardDispositions[key] {
      return RuntimeResponse(disposition: disposition)
    }
    if isAutoRepeat { return RuntimeResponse(disposition: .passThrough) }
    guard modeEnabled, permissions.isReady else {
      keyboardDispositions[key] = .passThrough
      return RuntimeResponse(disposition: .passThrough)
    }
    if modifiers.containsCommandOrControl {
      keyboardDispositions[key] = .passThrough
      return RuntimeResponse(disposition: .passThrough)
    }
    guard key.isProtectedCharacter else {
      keyboardDispositions[key] = .passThrough
      return RuntimeResponse(disposition: .passThrough)
    }
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
    guard let button = button(for: key) else {
      let disposition: EventDisposition = .consume
      keyboardDispositions[key] = disposition
      if isMappedKey(key) { pressedKeys.insert(key) }
      return RuntimeResponse(disposition: disposition)
    }
    if heldButtons.insert(button).inserted {
      keyboardDispositions[key] = .consume
      return RuntimeResponse(disposition: .consume, effects: [.mouseButton(button, .down)])
    }
    keyboardDispositions[key] = .consume
    return RuntimeResponse(disposition: .consume)
  }

  private func keyUp(_ key: Key, timestamp: TimeInterval) -> RuntimeResponse {
    if key == .leftOption, leftOptionSafetyExitHeld {
      leftOptionSafetyExitHeld = false
      keyboardDispositions.removeValue(forKey: key)
      return RuntimeResponse(disposition: .passThrough)
    }
    if key == configurationKey(named: configuration.bindings.activation) {
      defer {
        activationDownAt = nil
        activationHadCombination = false
        keyboardDispositions.removeValue(forKey: key)
      }
      guard permissions.isReady, eventTapHealthy, let started = activationDownAt,
        timestamp - started <= configuration.optionTapMilliseconds / 1_000,
        !activationHadCombination
      else { return RuntimeResponse(disposition: .passThrough) }
      guard !modeEnabled else { return RuntimeResponse(disposition: .passThrough) }
      let previousStatus = freeModeStatus
      modeEnabled = true
      movementVelocity = Point(x: 0, y: 0)
      scrollVelocity = Point(x: 0, y: 0)
      var effects: [RuntimeEffect] = [
        .modeChanged(isEnabled: true),
        .cursorHaloDiameterChanged(diameter: configuration.cursorHalo.diameter),
        .cursorHalo(isVisible: configuration.cursorHalo.enabled),
      ]
      effects.append(contentsOf: freeModeStatusEffects(changedFrom: previousStatus))
      return RuntimeResponse(disposition: .passThrough, effects: effects)
    }
    guard permissions.isReady else {
      return RuntimeResponse(disposition: .passThrough)
    }
    guard let disposition = keyboardDispositions.removeValue(forKey: key) else {
      return RuntimeResponse(disposition: .passThrough)
    }
    guard disposition == .consume else { return RuntimeResponse(disposition: .passThrough) }
    if let button = button(for: key), heldButtons.remove(button) != nil {
      pressedKeys.remove(key)
      return RuntimeResponse(disposition: .consume, effects: [.mouseButton(button, .up)])
    }
    pressedKeys.remove(key)
    return RuntimeResponse(disposition: .consume)
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
    let scrollDisplacement = smoothedDisplacement(
      current: scrollVelocity, target: scrollTarget, deltaTime: dt,
      timeConstant: configuration.scrolling.smoothingMilliseconds / 1_000)
    scrollVelocity = smoothed(
      current: scrollVelocity, target: scrollTarget, deltaTime: dt,
      timeConstant: configuration.scrolling.smoothingMilliseconds / 1_000)
    scrollRemainder = scrollRemainder + scrollDisplacement
    let pixelsX = Int(scrollRemainder.x.rounded(.towardZero))
    let pixelsY = Int(scrollRemainder.y.rounded(.towardZero))
    scrollRemainder.x -= Double(pixelsX)
    scrollRemainder.y -= Double(pixelsY)
    if pixelsX != 0 || pixelsY != 0 { effects.append(.scroll(pixelX: pixelsX, pixelY: pixelsY)) }
    return RuntimeResponse(disposition: .passThrough, effects: effects)
  }

  private func safetyExitEffects(
    emitDiagnostic: Bool = false, preserveKeyboardDispositions: Bool = false
  ) -> [RuntimeEffect] {
    let previousStatus = freeModeStatus
    var effects = heldButtons.sorted { $0.rawValue < $1.rawValue }.map {
      RuntimeEffect.mouseButton($0, .up)
    }
    heldButtons.removeAll()
    pressedKeys.removeAll()
    if !preserveKeyboardDispositions { keyboardDispositions.removeAll() }
    activeModifiers = []
    activationDownAt = nil
    activationHadCombination = false
    if !preserveKeyboardDispositions { leftOptionSafetyExitHeld = false }
    movementVelocity = Point(x: 0, y: 0)
    scrollVelocity = Point(x: 0, y: 0)
    scrollRemainder = Point(x: 0, y: 0)
    if modeEnabled {
      modeEnabled = false
      effects.append(.modeChanged(isEnabled: false))
      effects.append(.cursorHalo(isVisible: false))
    }
    if emitDiagnostic || !effects.isEmpty { effects.append(.diagnostic(.safetyExit)) }
    effects.append(contentsOf: freeModeStatusEffects(changedFrom: previousStatus))
    return effects
  }

  private func freeModeStatusEffects(changedFrom previousStatus: FreeModeStatus)
    -> [RuntimeEffect]
  {
    let status = freeModeStatus
    return status == previousStatus ? [] : [.freeModeStatusChanged(status)]
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
      configuration.bindings.moveUp, configuration.bindings.moveDown,
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
      (pressedKeys.contains(configurationKey(named: configuration.bindings.moveDown)) ? 1.0 : 0)
      - (pressedKeys.contains(configurationKey(named: configuration.bindings.moveUp)) ? 1.0 : 0)
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

  private func smoothedDisplacement(
    current: Point, target: Point, deltaTime: Double, timeConstant: Double
  ) -> Point {
    guard deltaTime > 0 else { return Point(x: 0, y: 0) }
    guard timeConstant > 0 else { return target * deltaTime }
    let decay = exp(-deltaTime / timeConstant)
    return target * deltaTime + (current - target) * (timeConstant * (1 - decay))
  }
}

private func + (lhs: Point, rhs: Point) -> Point { Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
private func - (lhs: Point, rhs: Point) -> Point { Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
private func * (lhs: Point, rhs: Double) -> Point { Point(x: lhs.x * rhs, y: lhs.y * rhs) }
