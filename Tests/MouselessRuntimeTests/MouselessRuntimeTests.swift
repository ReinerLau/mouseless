import XCTest

@testable import MouselessRuntime

private let buttonBindings: [(Key, MouseButton)] = [
  (.space, .left), (.r, .right), (.e, .middle), (.q, .back), (.w, .forward),
]

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

  func testModifierChangedLeftOptionTapEntersFreeModeWhenCapabilitiesAreReady() {
    let runtime = MouselessRuntime(permissions: .allGranted)

    _ = runtime.handle(.modifierChanged(.leftOption, isPressed: true, at: 0))
    let response = runtime.handle(.modifierChanged(.leftOption, isPressed: false, at: 0.1))

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
        oneAxisDistance = 100 - point.y
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
    XCTAssertEqual(100 - point.y, 39.3, accuracy: 0.4)
  }

  func testQuartzVerticalBindingsMapIToUpAndKToDown() throws {
    let up = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 100, y: 100))
    enterFreeMode(up)
    _ = up.handle(.keyDown(.i, at: 1))
    let upPoint = try XCTUnwrap(pointer(from: up.handle(.frame(deltaTime: 0.2))))
    XCTAssertLessThan(upPoint.y, 100)

    let down = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 100, y: 100))
    enterFreeMode(down)
    _ = down.handle(.keyDown(.k, at: 1))
    let downPoint = try XCTUnwrap(pointer(from: down.handle(.frame(deltaTime: 0.2))))
    XCTAssertGreaterThan(downPoint.y, 100)
  }

  func testPhysicalPointerMovementProducesAnIndicatorPositionUpdate() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    let response = runtime.handle(.pointerMoved(to: Point(x: 240, y: 180)))

    XCTAssertEqual(response.disposition, .passThrough)
    XCTAssertEqual(response.effects, [.pointerPositionChanged(to: Point(x: 240, y: 180))])
  }

  func testMovementUsesTheEntireLongFrameInterval() {
    let runtime = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 0, y: 0))
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.l, at: 1))

    let response = runtime.handle(.frame(deltaTime: 1))

    guard let point = pointer(from: response) else {
      return XCTFail("expected movement during a long frame")
    }
    XCTAssertEqual(point.x, 300, accuracy: 0.5)
  }

  func testMovementSpeedSupportsPrecisionAndThreeStackingFastKeys() {
    let fastKeySets: [[Key]] = [
      [], [.s], [.d], [.f], [.s, .d], [.s, .f], [.d, .f], [.s, .d, .f],
    ]
    for precision in [false, true] {
      for fastKeys in fastKeySets {
        let runtime = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 0, y: 0))
        enterFreeMode(runtime)
        _ = runtime.handle(.keyDown(.l, at: 1))
        if precision { _ = runtime.handle(.keyDown(.a, at: 1.1)) }
        for key in fastKeys {
          _ = runtime.handle(.keyDown(key, at: 1.2))
        }

        guard let point = pointer(from: runtime.handle(.frame(deltaTime: 1))) else {
          return XCTFail("expected movement for multiplier combination")
        }
        let expected = 300.0 * (precision ? 1.0 / 3.0 : 1) * pow(3, Double(fastKeys.count))
        XCTAssertEqual(point.x, expected, accuracy: 0.5)
      }
    }
  }

  func testOpposingDirectionsCancelWithoutAffectingTheOtherAxis() {
    let runtime = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 10, y: 20))
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.i, at: 1))
    _ = runtime.handle(.keyDown(.k, at: 1.1))
    _ = runtime.handle(.keyDown(.l, at: 1.2))

    guard let point = pointer(from: runtime.handle(.frame(deltaTime: 1))) else {
      return XCTFail("expected movement on the non-conflicting axis")
    }
    XCTAssertEqual(point.x, 310, accuracy: 0.5)
    XCTAssertEqual(point.y, 20, accuracy: 0.001)
  }

  func testAutoRepeatDoesNotCreateMotionEdgesOrChangeSpeedState() {
    let repeated = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 0, y: 0))
    enterFreeMode(repeated)
    _ = repeated.handle(.keyDown(.l, at: 1))
    _ = repeated.handle(.keyDown(.s, at: 1))
    for _ in 0..<4 {
      _ = repeated.handle(.keyDown(.l, at: 1.1, isAutoRepeat: true))
      _ = repeated.handle(.keyDown(.s, at: 1.1, isAutoRepeat: true))
    }

    let ordinary = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 0, y: 0))
    enterFreeMode(ordinary)
    _ = ordinary.handle(.keyDown(.l, at: 1))
    _ = ordinary.handle(.keyDown(.s, at: 1))

    XCTAssertEqual(
      pointer(from: repeated.handle(.frame(deltaTime: 1))),
      pointer(from: ordinary.handle(.frame(deltaTime: 1))))
  }

  func testMovementSmoothingUsesTheConfiguredTimeConstantWhenStartingChangingAndStopping() throws {
    let runtime = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 0, y: 0))
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.l, at: 1))

    let first = runtime.handle(.frame(deltaTime: 0.075))
    let firstPoint = try XCTUnwrap(pointer(from: first))
    let alpha = 1 - exp(-1.0)
    XCTAssertEqual(firstPoint.x, 300 * alpha * 0.075, accuracy: 0.001)

    _ = runtime.handle(.keyDown(.s, at: 1.075))
    let changed = runtime.handle(.frame(deltaTime: 0.075))
    let changedPoint = try XCTUnwrap(pointer(from: changed))
    let firstVelocity = 300 * alpha
    let changedVelocity = firstVelocity + (900 - firstVelocity) * alpha
    XCTAssertEqual(changedPoint.x - firstPoint.x, changedVelocity * 0.075, accuracy: 0.001)
    XCTAssertLessThan(changedPoint.x - firstPoint.x, 900 * 0.075)

    _ = runtime.handle(.keyUp(.s, at: 1.15))
    _ = runtime.handle(.keyUp(.l, at: 1.15))
    let stopped = runtime.handle(.frame(deltaTime: 0.075))
    let stoppedPoint = try XCTUnwrap(pointer(from: stopped))
    let stoppedVelocity = changedVelocity * (1 - alpha)
    XCTAssertEqual(stoppedPoint.x - changedPoint.x, stoppedVelocity * 0.075, accuracy: 0.001)
  }

  func testSixtyAndOneTwentyHertzProduceNearlyTheSameHeldMovement() {
    let sixtyHertz = heldMovement(frameDelta: 1.0 / 60.0, frameCount: 60)
    let oneTwentyHertz = heldMovement(frameDelta: 1.0 / 120.0, frameCount: 120)

    XCTAssertEqual(sixtyHertz, oneTwentyHertz, accuracy: 2)
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

  func testAllFiveButtonBindingsProducePairedEdges() {
    for (key, button) in buttonBindings {
      let runtime = MouselessRuntime(permissions: .allGranted)
      enterFreeMode(runtime)

      let down = runtime.handle(.keyDown(key, at: 1))
      let repeatDown = runtime.handle(.keyDown(key, at: 1.1, isAutoRepeat: true))
      let up = runtime.handle(.keyUp(key, at: 1.2))

      XCTAssertEqual(down.disposition, .consume)
      XCTAssertEqual(down.effects, [.mouseButton(button, .down)])
      XCTAssertEqual(repeatDown.disposition, .consume)
      XCTAssertTrue(repeatDown.effects.isEmpty)
      XCTAssertEqual(up.disposition, .consume)
      XCTAssertEqual(up.effects, [.mouseButton(button, .up)])
    }
  }

  func testLongPressKeepsEachButtonHeldUntilKeyUp() {
    for (key, button) in buttonBindings {
      let runtime = MouselessRuntime(permissions: .allGranted)
      enterFreeMode(runtime)
      XCTAssertEqual(runtime.handle(.keyDown(key, at: 1)).effects, [.mouseButton(button, .down)])
      for frame in 0..<10 {
        XCTAssertTrue(
          runtime.handle(.keyDown(key, at: 1.1 + Double(frame) * 0.1, isAutoRepeat: true))
            .effects.isEmpty)
      }
      XCTAssertEqual(runtime.handle(.keyUp(key, at: 2.2)).effects, [.mouseButton(button, .up)])
    }
  }

  func testButtonBindingsPassThroughOutsideFreeMode() {
    let bindings: [Key] = [.space, .r, .e, .q, .w]
    let runtime = MouselessRuntime(permissions: .allGranted)

    for key in bindings {
      XCTAssertEqual(runtime.handle(.keyDown(key, at: 1)).disposition, .passThrough)
      XCTAssertEqual(runtime.handle(.keyUp(key, at: 1.1)).disposition, .passThrough)
    }
  }

  func testHeldButtonsTurnKeyboardMovementIntoDraggedEvents() throws {
    let runtime = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 100, y: 100))
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.space, at: 1))
    _ = runtime.handle(.keyDown(.l, at: 1.1))

    let response = runtime.handle(.frame(deltaTime: 0.2))
    guard
      case .pointerMoved(to: let point, buttons: let buttons) = response.effects.first(where: {
        if case .pointerMoved = $0 { return true }
        return false
      })
    else { return XCTFail("expected a dragged pointer movement") }

    XCTAssertEqual(buttons, [.left])
    XCTAssertGreaterThan(point.x, 100)
    XCTAssertEqual(runtime.handle(.keyUp(.l, at: 1.3)).effects, [])
    XCTAssertEqual(runtime.handle(.keyUp(.space, at: 1.4)).effects, [.mouseButton(.left, .up)])
  }

  func testEveryHeldButtonProducesItsOwnDraggedEvent() throws {
    for (key, button) in buttonBindings {
      let runtime = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 100, y: 100))
      enterFreeMode(runtime)
      _ = runtime.handle(.keyDown(key, at: 1))
      _ = runtime.handle(.keyDown(.l, at: 1.1))

      let response = runtime.handle(.frame(deltaTime: 0.2))
      guard
        case .pointerMoved(to: _, buttons: let buttons) = response.effects.first(where: {
          if case .pointerMoved = $0 { return true }
          return false
        })
      else { return XCTFail("expected a dragged pointer movement for \(button)") }

      XCTAssertEqual(buttons, [button])
    }
  }

  func testMultipleButtonsRemainIndependentAndSafetyExitBalancesEverySequence() {
    var seed: UInt64 = 0x6_0000_0000_0001
    func nextRandom() -> UInt64 {
      seed = seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
      return seed
    }

    for sequenceIndex in 0..<128 {
      let runtime = MouselessRuntime(permissions: .allGranted)
      enterFreeMode(runtime)
      var effects: [RuntimeEffect] = []
      for step in 0..<32 {
        let (key, _) = buttonBindings[Int(nextRandom() % UInt64(buttonBindings.count))]
        let timestamp = Double(sequenceIndex * 32 + step) + 1
        switch nextRandom() % 3 {
        case 0:
          effects += runtime.handle(.keyDown(key, at: timestamp)).effects
        case 1:
          effects += runtime.handle(.keyDown(key, at: timestamp, isAutoRepeat: true)).effects
        default:
          effects += runtime.handle(.keyUp(key, at: timestamp)).effects
        }
      }
      effects += runtime.handle(.keyDown(.escape, at: 10_000)).effects

      var balances = Dictionary(uniqueKeysWithValues: MouseButton.allCases.map { ($0, 0) })
      for effect in effects {
        guard case .mouseButton(let button, let phase) = effect else { continue }
        balances[button, default: 0] += phase == .down ? 1 : -1
        XCTAssertGreaterThanOrEqual(balances[button, default: 0], 0)
      }
      XCTAssertTrue(balances.values.allSatisfy { $0 == 0 })
      for (key, _) in buttonBindings {
        XCTAssertEqual(runtime.handle(.keyUp(key, at: 10_001)).disposition, .passThrough)
      }

      enterFreeMode(runtime)
      for (key, button) in buttonBindings {
        XCTAssertEqual(
          runtime.handle(.keyDown(key, at: 10_002)).effects, [.mouseButton(button, .down)])
        XCTAssertEqual(
          runtime.handle(.keyUp(key, at: 10_003)).effects, [.mouseButton(button, .up)])
      }
      _ = runtime.handle(.keyDown(.escape, at: 10_004))
    }
  }

  func testButtonReleaseOrderRemainsMappedToEachButton() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    for (index, binding) in buttonBindings.enumerated() {
      _ = runtime.handle(.keyDown(binding.0, at: Double(index) + 1))
    }

    for (index, binding) in buttonBindings.reversed().enumerated() {
      XCTAssertEqual(
        runtime.handle(.keyUp(binding.0, at: Double(index) + 10)).effects,
        [.mouseButton(binding.1, .up)])
    }
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

  func testSafetyEventsReleaseEveryHeldVirtualButton() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    for (index, binding) in buttonBindings.enumerated() {
      _ = runtime.handle(.keyDown(binding.0, at: Double(index) + 1))
    }

    let inactive = runtime.handle(.sessionChanged(.inactive))
    let released = inactive.effects.compactMap { effect -> MouseButton? in
      guard case .mouseButton(let button, .up) = effect else { return nil }
      return button
    }
    XCTAssertEqual(released, MouseButton.allCases)

    let shutdownRuntime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(shutdownRuntime)
    for (index, binding) in buttonBindings.enumerated() {
      _ = shutdownRuntime.handle(.keyDown(binding.0, at: Double(index) + 1))
    }
    let shutdown = shutdownRuntime.handle(.shutdown)
    let shutdownReleased = shutdown.effects.compactMap { effect -> MouseButton? in
      guard case .mouseButton(let button, .up) = effect else { return nil }
      return button
    }
    XCTAssertEqual(shutdownReleased, MouseButton.allCases)
    XCTAssertEqual(Array(shutdown.effects.prefix(MouseButton.allCases.count)),
      MouseButton.allCases.map { .mouseButton($0, .up) })
    for (key, _) in buttonBindings {
      XCTAssertEqual(shutdownRuntime.handle(.keyUp(key, at: 10_001)).disposition, .passThrough)
    }
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
    let response = runtime.handle(.frame(deltaTime: 0.2))

    guard
      case .pointerMoved(to: let point, buttons: _) = response.effects.first(where: {
        if case .pointerMoved = $0 { return true }
        return false
      })
    else { return XCTFail("expected clamped movement") }
    XCTAssertEqual(point.x, 100, accuracy: 0.001)
  }

  func testMovementCrossesAGapBetweenDisplays() {
    let topology = DisplayTopology(regions: [
      DisplayRegion(x: 0, y: 0, width: 100, height: 100),
      DisplayRegion(x: 200, y: 0, width: 100, height: 100),
    ])
    let runtime = MouselessRuntime(
      permissions: .allGranted, topology: topology, pointer: Point(x: 50, y: 50))
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.l, at: 1))

    var lastPoint: Point?
    for _ in 0..<60 {
      if let point = pointer(from: runtime.handle(.frame(deltaTime: 1.0 / 60.0))) {
        lastPoint = point
      }
    }

    guard let point = lastPoint else {
      return XCTFail("expected movement onto the second display")
    }
    XCTAssertEqual(point.x, 300, accuracy: 1)
  }

  func testMovementStopsAtAnOuterEdgeWithoutHiddenDisplacement() throws {
    let topology = DisplayTopology(regions: [
      DisplayRegion(x: 0, y: 0, width: 100, height: 100),
    ])
    let runtime = MouselessRuntime(
      permissions: .allGranted, topology: topology, pointer: Point(x: 50, y: 50))
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.l, at: 1))
    for _ in 0..<120 { _ = runtime.handle(.frame(deltaTime: 1.0 / 60.0)) }
    _ = runtime.handle(.keyUp(.l, at: 3))
    _ = runtime.handle(.keyDown(.j, at: 3.1))

    let response = runtime.handle(.frame(deltaTime: 1.0 / 60.0))
    let point = try XCTUnwrap(pointer(from: response))
    XCTAssertLessThan(point.x, 100)
    XCTAssertEqual(point.y, 50, accuracy: 0.001)
  }

  func testMovementUsesAChangedDisplayTopologyImmediately() throws {
    let runtime = MouselessRuntime(
      permissions: .allGranted,
      topology: DisplayTopology(regions: [DisplayRegion(x: 0, y: 0, width: 100, height: 100)]),
      pointer: Point(x: 50, y: 50))
    enterFreeMode(runtime)
    _ = runtime.handle(.frame(deltaTime: 0))
    _ = runtime.handle(.topologyChanged(DisplayTopology(regions: [
      DisplayRegion(x: 0, y: 0, width: 100, height: 100),
      DisplayRegion(x: 200, y: 0, width: 100, height: 100),
    ])))
    _ = runtime.handle(.keyDown(.l, at: 1))

    var lastPoint: Point?
    for _ in 0..<60 {
      if let point = pointer(from: runtime.handle(.frame(deltaTime: 1.0 / 60.0))) {
        lastPoint = point
      }
    }

    XCTAssertEqual(try XCTUnwrap(lastPoint).x, 300, accuracy: 1)
  }

  func testMovementCrossesAnOffsetDisplayWithADifferentSize() throws {
    let topology = DisplayTopology(regions: [
      DisplayRegion(x: -500, y: -200, width: 500, height: 400),
      DisplayRegion(x: 100, y: -50, width: 800, height: 200),
    ])
    let runtime = MouselessRuntime(
      permissions: .allGranted, topology: topology, pointer: Point(x: -250, y: 0))
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.l, at: 1))

    var lastPoint: Point?
    for _ in 0..<240 {
      if let point = pointer(from: runtime.handle(.frame(deltaTime: 1.0 / 60.0))) {
        lastPoint = point
      }
    }

    XCTAssertEqual(try XCTUnwrap(lastPoint).x, 900, accuracy: 1)
  }

  func testTopologyChangeRepositionsAPointOutsideTheNewDisplays() {
    let runtime = MouselessRuntime(
      permissions: .allGranted,
      topology: DisplayTopology(regions: [DisplayRegion(x: -500, y: -300, width: 500, height: 300)]),
      pointer: Point(x: -100, y: -100))

    let response = runtime.handle(.topologyChanged(DisplayTopology(regions: [
      DisplayRegion(x: 100, y: -200, width: 500, height: 400),
    ])))

    XCTAssertEqual(response.effects, [.pointerPositionChanged(to: Point(x: 100, y: -100))])
  }

  func testMovementSupportsNegativeGlobalCoordinates() throws {
    let topology = DisplayTopology(regions: [
      DisplayRegion(x: -1_280, y: -200, width: 1_280, height: 800),
    ])
    let runtime = MouselessRuntime(
      permissions: .allGranted, topology: topology, pointer: Point(x: -100, y: 0))
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.j, at: 1))

    var lastPoint: Point?
    for _ in 0..<240 {
      if let point = pointer(from: runtime.handle(.frame(deltaTime: 1.0 / 60.0))) {
        lastPoint = point
      }
    }

    let point = try XCTUnwrap(lastPoint)
    XCTAssertEqual(point.x, -1_280, accuracy: 0.2)
    XCTAssertEqual(point.y, 0, accuracy: 0.001)
  }

  func testKeyboardMovementContinuesFromAPhysicalPointerPosition() throws {
    let runtime = MouselessRuntime(permissions: .allGranted)
    let physical = runtime.handle(.pointerMoved(to: Point(x: -240, y: 180)))
    XCTAssertEqual(physical.effects, [.pointerPositionChanged(to: Point(x: -240, y: 180))])

    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.l, at: 1))
    let response = runtime.handle(.frame(deltaTime: 0.2))
    XCTAssertGreaterThan(try XCTUnwrap(pointer(from: response)).x, -240)
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

  private func pointer(from response: RuntimeResponse) -> Point? {
    response.effects.compactMap { effect in
      guard case .pointerMoved(to: let point, buttons: _) = effect else { return nil }
      return point
    }.last
  }

  private func heldMovement(frameDelta: TimeInterval, frameCount: Int) -> Double {
    let runtime = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 0, y: 0))
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.l, at: 1))
    var lastPoint = 0.0
    for _ in 0..<frameCount {
      if let point = pointer(from: runtime.handle(.frame(deltaTime: frameDelta))) {
        lastPoint = point.x
      }
    }
    return lastPoint
  }
}
