import XCTest

@testable import MouselessRuntime

final class MouselessRuntimeTests: XCTestCase {
  func testMissingPermissionPassesThroughKeysAndCannotEnterFreeMode() {
    let runtime = MouselessRuntime(permissions: .none)

    let down = runtime.handle(.keyDown(.leftOption, at: 0))
    let up = runtime.handle(.keyUp(.leftOption, at: 0.1))

    XCTAssertEqual(down.disposition, .passThrough)
    XCTAssertEqual(up.disposition, .passThrough)
    XCTAssertFalse(up.effects.contains(.modeChanged(isEnabled: true)))
  }

  func testAQualifiedLeftOptionTapEntersFreeModeWhenCapabilitiesAreReady() {
    let runtime = MouselessRuntime(permissions: .allGranted)

    _ = runtime.handle(.keyDown(.leftOption, at: 0))
    let response = runtime.handle(.keyUp(.leftOption, at: 0.1))

    XCTAssertEqual(response.disposition, .passThrough)
    XCTAssertTrue(response.effects.contains(.modeChanged(isEnabled: true)))
    XCTAssertTrue(response.effects.contains(.indicator(isVisible: true)))
  }

  func testLeftOptionTimeoutAndCombinationDoNotToggle() {
    let runtime = MouselessRuntime(permissions: .allGranted)

    _ = runtime.handle(.keyDown(.leftOption, at: 0))
    let timeout = runtime.handle(.keyUp(.leftOption, at: 0.251))
    _ = runtime.handle(.keyDown(.leftOption, at: 1))
    _ = runtime.handle(.keyDown(.other(42), at: 1.01))
    let combination = runtime.handle(.keyUp(.leftOption, at: 1.1))

    XCTAssertEqual(timeout.disposition, .passThrough)
    XCTAssertEqual(combination.disposition, .passThrough)
    XCTAssertFalse(combination.effects.contains(.modeChanged(isEnabled: true)))
  }

  func testRightOptionNeverTogglesFreeMode() {
    let runtime = MouselessRuntime(permissions: .allGranted)

    _ = runtime.handle(.keyDown(.rightOption, at: 0))
    let response = runtime.handle(.keyUp(.rightOption, at: 0.1))

    XCTAssertEqual(response.disposition, .passThrough)
    XCTAssertFalse(response.effects.contains(.modeChanged(isEnabled: true)))
  }

  func testOnlyMappedKeysAreConsumedInFreeModeAndEscapeExits() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)

    let unmapped = runtime.handle(.keyDown(.other(99), at: 1))
    let mapped = runtime.handle(.keyDown(.i, at: 1.1))
    let escape = runtime.handle(.keyDown(.escape, at: 1.2))

    XCTAssertEqual(unmapped.disposition, .passThrough)
    XCTAssertEqual(mapped.disposition, .consume)
    XCTAssertEqual(escape.disposition, .consume)
    XCTAssertTrue(escape.effects.contains(.modeChanged(isEnabled: false)))
  }

  func testMovementUsesTimeBasedSpeedAndNormalizesDiagonalInput() {
    let runtime = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 100, y: 100))
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.i, at: 1))

    var oneAxisDistance = 0.0
    for _ in 0..<60 {
      let response = runtime.handle(.frame(deltaTime: 1.0 / 60.0))
      if case .pointerMoved(to: let point, buttons: _) = response.effects.first(where: {
        if case .pointerMoved = $0 { return true }
        return false
      }) {
        oneAxisDistance = point.y - 100
      }
    }

    XCTAssertEqual(oneAxisDistance, 280, accuracy: 4)

    let diagonal = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 100, y: 100))
    enterFreeMode(diagonal)
    _ = diagonal.handle(.keyDown(.i, at: 1))
    _ = diagonal.handle(.keyDown(.l, at: 1))
    let response = diagonal.handle(.frame(deltaTime: 0.2))
    guard
      case .pointerMoved(to: let point, buttons: _) = response.effects.first(where: {
        if case .pointerMoved = $0 { return true }
        return false
      })
    else { return XCTFail("expected diagonal movement") }

    XCTAssertEqual(point.x - 100, 39.3, accuracy: 0.4)
    XCTAssertEqual(point.y - 100, 39.3, accuracy: 0.4)
  }

  func testMouseButtonsPairEdgesIgnoreAutoRepeatAndReleaseOnExit() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)

    let down = runtime.handle(.keyDown(.space, at: 1))
    let repeatDown = runtime.handle(.keyDown(.space, at: 1.1, isAutoRepeat: true))
    let up = runtime.handle(.keyUp(.space, at: 1.2))

    XCTAssertEqual(down.effects, [.mouseButton(.left, .down)])
    XCTAssertTrue(repeatDown.effects.isEmpty)
    XCTAssertEqual(up.effects, [.mouseButton(.left, .up)])

    _ = runtime.handle(.keyDown(.r, at: 2))
    let exit = runtime.handle(.keyDown(.escape, at: 2.1))
    XCTAssertTrue(exit.effects.contains(.mouseButton(.right, .up)))

    let second = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(second)
    _ = second.handle(.keyDown(.space, at: 3))
    _ = second.handle(.keyDown(.leftOption, at: 4))
    let tapExit = second.handle(.keyUp(.leftOption, at: 4.1))
    XCTAssertTrue(tapExit.effects.contains(.mouseButton(.left, .up)))
    XCTAssertTrue(tapExit.effects.contains(.modeChanged(isEnabled: false)))
  }

  func testPermissionLossAndInactiveSessionSafelyReleaseButtons() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.space, at: 1))
    let lostPermission = runtime.handle(.permissionsChanged(.none))

    XCTAssertTrue(lostPermission.effects.contains(.mouseButton(.left, .up)))
    XCTAssertTrue(lostPermission.effects.contains(.modeChanged(isEnabled: false)))

    let inactive = runtime.handle(.sessionChanged(.inactive))
    XCTAssertTrue(inactive.effects.isEmpty)
  }

  func testDisplayTopologyProjectsIntoNearestScreenAndClampsEdges() {
    let topology = DisplayTopology(regions: [
      DisplayRegion(x: 0, y: 0, width: 100, height: 100),
      DisplayRegion(x: 200, y: 0, width: 100, height: 100),
    ])
    let runtime = MouselessRuntime(
      permissions: .allGranted, topology: topology, pointer: Point(x: 50, y: 50))
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.l, at: 1))
    let response = runtime.handle(.frame(deltaTime: 1))

    guard
      case .pointerMoved(to: let point, buttons: _) = response.effects.first(where: {
        if case .pointerMoved = $0 { return true }
        return false
      })
    else { return XCTFail("expected clamped movement") }
    XCTAssertEqual(point.x, 100, accuracy: 0.001)
  }

  func testScrollAccumulatesSubpixelDeltasAndSupportsDiagonalInput() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.m, at: 1))
    var total = 0
    for _ in 0..<100 {
      let response = runtime.handle(.frame(deltaTime: 0.001))
      for effect in response.effects {
        if case .scroll(_, let pixelY) = effect { total += pixelY }
      }
    }
    XCTAssertGreaterThan(total, 0)

    _ = runtime.handle(.keyDown(.slash, at: 2))
    let diagonal = runtime.handle(.frame(deltaTime: 0.02))
    guard
      case .scroll(let pixelX, let pixelY) = diagonal.effects.first(where: {
        if case .scroll = $0 { return true }
        return false
      })
    else { return XCTFail("expected diagonal scroll") }
    XCTAssertGreaterThan(pixelX, 0)
    XCTAssertGreaterThan(pixelY, 0)
  }

  func testConfigurationIsAtomicAndRejectsUnknownFields() throws {
    let runtime = MouselessRuntime(permissions: .allGranted)
    var validObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: RuntimeConfiguration.defaultJSON) as? [String: Any])
    var movement = try XCTUnwrap(validObject["movement"] as? [String: Any])
    movement["baseSpeed"] = 600
    validObject["movement"] = movement
    let valid = try JSONSerialization.data(withJSONObject: validObject)
    let accepted = runtime.handle(.configuration(valid))
    XCTAssertTrue(accepted.effects.contains(.configurationAccepted))

    validObject["unexpected"] = true
    let invalid = try JSONSerialization.data(withJSONObject: validObject)
    let rejected = runtime.handle(.configuration(invalid))
    XCTAssertTrue(rejected.effects.contains(.configurationRejected))
  }

  func testEventTapFailureRequestsRecoveryWithoutChangingMode() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    let response = runtime.handle(.eventTapDisabled)

    XCTAssertEqual(response.disposition, .passThrough)
    XCTAssertTrue(response.effects.contains(.eventTapShouldBeReenabled))
  }

  private func enterFreeMode(_ runtime: MouselessRuntime) {
    _ = runtime.handle(.keyDown(.leftOption, at: 0))
    _ = runtime.handle(.keyUp(.leftOption, at: 0.1))
  }
}
