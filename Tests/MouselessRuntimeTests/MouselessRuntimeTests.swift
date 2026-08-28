import XCTest

@testable import MouselessRuntime

private let buttonBindings: [(Key, MouseButton)] = [
  (.space, .left), (.r, .right), (.e, .middle), (.q, .back), (.w, .forward),
]

private struct ScrollBinding {
  let key: Key
  let horizontalSign: Int
  let verticalSign: Int
}

private let scrollBindings = [
  ScrollBinding(key: .m, horizontalSign: 0, verticalSign: 1),
  ScrollBinding(key: .comma, horizontalSign: 0, verticalSign: -1),
  ScrollBinding(key: .period, horizontalSign: -1, verticalSign: 0),
  ScrollBinding(key: .slash, horizontalSign: 1, verticalSign: 0),
]

private let protectedCharacterKeys: [Key] = [
  .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r, .s, .t, .u, .v,
  .w, .x, .y, .z,
  .digit0, .digit1, .digit2, .digit3, .digit4, .digit5, .digit6, .digit7, .digit8, .digit9,
  .minus, .equal, .leftBracket, .rightBracket, .backslash, .semicolon, .quote, .grave,
  .comma, .period, .slash, .space,
  .keypad0, .keypad1, .keypad2, .keypad3, .keypad4, .keypad5, .keypad6, .keypad7, .keypad8,
  .keypad9, .keypadDecimal, .keypadMultiply, .keypadPlus, .keypadDivide,
  .keypadMinus, .keypadEquals, .isoSection, .jisYen, .jisUnderscore, .jisKeypadComma, .jisEisu,
  .jisKana,
]

private let reservedPassThroughKeys: [Key] = [
  .returnKey, .keypadEnter, .keypadClear, .delete, .forwardDelete, .tab, .escape, .arrowUp, .arrowDown,
  .arrowLeft, .arrowRight, .home, .end, .pageUp, .pageDown, .functionKey(1), .mediaKey(1),
  .other(999),
]

final class MouselessRuntimeTests: XCTestCase {
  func testStartupPublishesAvailableStatusAfterPermissionsAndEventTapAreReady() {
    let runtime = MouselessRuntime()

    XCTAssertEqual(runtime.freeModeStatus, .unavailable)
    XCTAssertFalse(
      runtime.handle(.permissionsChanged(.allGranted)).effects.contains(
        .freeModeStatusChanged(.available)))

    let response = runtime.handle(.eventTapReady)

    XCTAssertTrue(response.effects.contains(.freeModeStatusChanged(.available)))
  }

  func testFreeModeStatusUsesDistinctSymbolsAndAccessibilityDescriptions() {
    XCTAssertEqual(FreeModeStatus.available.menuBarTitle, "Mouseless ○")
    XCTAssertEqual(FreeModeStatus.enabled.menuBarTitle, "Mouseless ●")
    XCTAssertEqual(FreeModeStatus.unavailable.menuBarTitle, "Mouseless !")
    XCTAssertTrue(FreeModeStatus.available.accessibilityDescription.contains("off"))
    XCTAssertTrue(FreeModeStatus.enabled.accessibilityDescription.contains("on"))
    XCTAssertTrue(FreeModeStatus.unavailable.accessibilityDescription.contains("unavailable"))
  }

  func testEnteringAndLeavingFreeModePublishesAuthoritativeStatus() {
    let runtime = MouselessRuntime(permissions: .allGranted)

    _ = runtime.handle(.keyDown(.leftOption, at: 0))
    let entered = runtime.handle(.keyUp(.leftOption, at: 0.1))
    XCTAssertEqual(runtime.freeModeStatus, .enabled)
    XCTAssertTrue(entered.effects.contains(.freeModeStatusChanged(.enabled)))

    let exited = runtime.handle(.keyDown(.leftOption, at: 1))
    XCTAssertEqual(runtime.freeModeStatus, .available)
    XCTAssertTrue(exited.effects.contains(.freeModeStatusChanged(.available)))
  }

  func testPermissionRevocationAndRecoveryNeverAutomaticallyReenableFreeMode() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    _ = runtime.handle(.keyDown(.leftOption, at: 0))
    _ = runtime.handle(.keyUp(.leftOption, at: 0.1))

    let revoked = runtime.handle(.permissionsChanged(.none))
    XCTAssertEqual(runtime.freeModeStatus, .unavailable)
    XCTAssertTrue(revoked.effects.contains(.freeModeStatusChanged(.unavailable)))

    _ = runtime.handle(.permissionsChanged(.allGranted))
    let restored = runtime.handle(.eventTapReady)
    XCTAssertEqual(runtime.freeModeStatus, .available)
    XCTAssertTrue(restored.effects.contains(.freeModeStatusChanged(.available)))
  }

  func testEventTapRecoveryStatesPublishStatusAndRejectActivationWhileUnavailable() {
    let runtime = MouselessRuntime(permissions: .allGranted)

    let disabled = runtime.handle(.eventTapDisabled)
    XCTAssertEqual(runtime.freeModeStatus, .unavailable)
    XCTAssertTrue(disabled.effects.contains(.freeModeStatusChanged(.unavailable)))

    let permissionRecheck = runtime.handle(.permissionsChanged(.allGranted))
    XCTAssertEqual(runtime.freeModeStatus, .unavailable)
    XCTAssertFalse(permissionRecheck.effects.contains(.freeModeStatusChanged(.available)))

    _ = runtime.handle(.keyDown(.leftOption, at: 1))
    let rejected = runtime.handle(.keyUp(.leftOption, at: 1.1))
    XCTAssertEqual(runtime.freeModeStatus, .unavailable)
    XCTAssertFalse(rejected.effects.contains(.modeChanged(isEnabled: true)))

    let recovered = runtime.handle(.eventTapReenabled)
    XCTAssertEqual(runtime.freeModeStatus, .available)
    XCTAssertTrue(recovered.effects.contains(.freeModeStatusChanged(.available)))

    let failed = runtime.handle(.eventTapRecoveryFailed)
    XCTAssertEqual(runtime.freeModeStatus, .unavailable)
    XCTAssertTrue(failed.effects.contains(.freeModeStatusChanged(.unavailable)))
  }

  func testKeyboardEventPublicInterfaceCarriesPhysicalKeyLifecycleAndModifiers() {
    let event = KeyboardEvent(
      key: .i, phase: .down, timestamp: 12.5, isAutoRepeat: true,
      modifiers: [.leftCommand, .rightShift])

    XCTAssertEqual(event.key, .i)
    XCTAssertEqual(event.phase, .down)
    XCTAssertEqual(event.timestamp, 12.5)
    XCTAssertTrue(event.isAutoRepeat)
    XCTAssertEqual(event.modifiers, [.leftCommand, .rightShift])
  }

  func testCommandAndControlShortcutsPassThroughMappedKeysForEntireLifecycle() {
    let shortcutModifiers: [KeyboardModifiers] = [
      .leftCommand, .rightCommand, .leftControl, .rightControl,
      [.leftCommand, .rightShift], [.rightControl, .rightOption],
    ]

    for modifiers in shortcutModifiers {
      let runtime = MouselessRuntime(permissions: .allGranted)
      enterFreeMode(runtime)

      let down = runtime.handle(
        .keyboard(
          KeyboardEvent(
            key: .space, phase: .down, timestamp: 1, isAutoRepeat: false,
            modifiers: modifiers)))
      let repeated = runtime.handle(
        .keyboard(
          KeyboardEvent(
            key: .space, phase: .down, timestamp: 1.1, isAutoRepeat: true,
            modifiers: modifiers)))
      let up = runtime.handle(
        .keyboard(
          KeyboardEvent(
            key: .space, phase: .up, timestamp: 1.2, isAutoRepeat: false,
            modifiers: [])))

      XCTAssertEqual(down.disposition, .passThrough, "down with \(modifiers)")
      XCTAssertEqual(repeated.disposition, .passThrough, "repeat with \(modifiers)")
      XCTAssertEqual(up.disposition, .passThrough, "up with \(modifiers)")
      XCTAssertTrue(down.effects.isEmpty)
      XCTAssertTrue(repeated.effects.isEmpty)
      XCTAssertTrue(up.effects.isEmpty)
    }
  }

  func testShiftCapsLockAndRightOptionKeepMappedKeysConsumed() {
    let modifiers: [KeyboardModifiers] = [
      .leftShift, .rightShift, .capsLock, .rightOption,
      [.leftShift, .rightOption], [.capsLock, .rightShift],
    ]

    for modifierState in modifiers {
      let runtime = MouselessRuntime(permissions: .allGranted)
      enterFreeMode(runtime)

      let down = runtime.handle(
        .keyboard(
          KeyboardEvent(
            key: .space, phase: .down, timestamp: 1, isAutoRepeat: false,
            modifiers: modifierState)))
      let repeated = runtime.handle(
        .keyboard(
          KeyboardEvent(
            key: .space, phase: .down, timestamp: 1.1, isAutoRepeat: true,
            modifiers: modifierState)))
      let up = runtime.handle(
        .keyboard(
          KeyboardEvent(
            key: .space, phase: .up, timestamp: 1.2, isAutoRepeat: false,
            modifiers: [])))

      XCTAssertEqual(down.disposition, .consume, "down with \(modifierState)")
      XCTAssertEqual(down.effects, [.mouseButton(.left, .down)])
      XCTAssertEqual(repeated.disposition, .consume, "repeat with \(modifierState)")
      XCTAssertTrue(repeated.effects.isEmpty)
      XCTAssertEqual(up.disposition, .consume, "up with \(modifierState)")
      XCTAssertEqual(up.effects, [.mouseButton(.left, .up)])
    }
  }

  func testACommandMappedKeyNeverStartsMovementOrAButtonEvenWhenModifiersChangeBeforeRelease() {
    let runtime = MouselessRuntime(permissions: .allGranted, pointer: Point(x: 100, y: 100))
    enterFreeMode(runtime)

    let down = runtime.handle(
      .keyboard(
        KeyboardEvent(
          key: .l, phase: .down, timestamp: 1, isAutoRepeat: false,
          modifiers: .leftCommand)))
    let repeatDown = runtime.handle(
      .keyboard(
        KeyboardEvent(
          key: .l, phase: .down, timestamp: 1.1, isAutoRepeat: true,
          modifiers: .leftCommand)))
    let frame = runtime.handle(.frame(deltaTime: 1))
    let up = runtime.handle(
      .keyboard(
        KeyboardEvent(
          key: .l, phase: .up, timestamp: 2, isAutoRepeat: false, modifiers: [])))

    XCTAssertEqual(down.disposition, .passThrough)
    XCTAssertEqual(repeatDown.disposition, .passThrough)
    XCTAssertTrue(frame.effects.isEmpty)
    XCTAssertEqual(up.disposition, .passThrough)
    XCTAssertTrue(up.effects.isEmpty)
  }

  func testAlwaysOnKeyboardProtectionConsumesCharacterKeysAndPassesReservedKeys() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)

    for (index, key) in protectedCharacterKeys.enumerated() {
      let isMapped = buttonBindings.contains(where: { $0.0 == key })
        || scrollBindings.contains(where: { $0.key == key })
        || [.i, .j, .k, .l, .a, .s, .d, .f].contains(key)
      let down = runtime.handle(.keyDown(key, at: Double(index) + 1))
      let repeated = runtime.handle(.keyDown(key, at: Double(index) + 1.1, isAutoRepeat: true))
      let up = runtime.handle(.keyUp(key, at: Double(index) + 1.2))

      let label = String(describing: key)
      XCTAssertEqual(down.disposition, .consume, "down for " + label)
      XCTAssertEqual(repeated.disposition, .consume, "repeat for " + label)
      XCTAssertEqual(up.disposition, .consume, "up for " + label)
      XCTAssertTrue(repeated.effects.isEmpty, "repeat effects for " + label)
      if !isMapped {
        XCTAssertTrue(down.effects.isEmpty, "down effects for " + label)
        XCTAssertTrue(up.effects.isEmpty, "up effects for " + label)
      }
    }

    for (index, key) in reservedPassThroughKeys.enumerated() {
      let down = runtime.handle(.keyDown(key, at: Double(index) + 100))
      let repeated = runtime.handle(.keyDown(key, at: Double(index) + 100.1, isAutoRepeat: true))
      let up = runtime.handle(.keyUp(key, at: Double(index) + 100.2))

      let label = String(describing: key)
      XCTAssertEqual(down.disposition, .passThrough, "down for " + label)
      XCTAssertEqual(repeated.disposition, .passThrough, "repeat for " + label)
      XCTAssertEqual(up.disposition, .passThrough, "up for " + label)
      XCTAssertTrue(down.effects.isEmpty)
      XCTAssertTrue(repeated.effects.isEmpty)
      XCTAssertTrue(up.effects.isEmpty)
    }
  }

  func testConfiguredCharacterBindingStillPerformsItsMouseAction() {
    let runtime = MouselessRuntime(
      configuration: RuntimeConfiguration(
        bindings: KeyBindings(leftClick: "digit1")), permissions: .allGranted)
    enterFreeMode(runtime)

    XCTAssertEqual(
      runtime.handle(.keyDown(.digit1, at: 1)).effects,
      [.mouseButton(.left, .down)])
    XCTAssertEqual(
      runtime.handle(.keyUp(.digit1, at: 1.1)).effects,
      [.mouseButton(.left, .up)])
  }

  func testCommandAndControlShortcutsPassThroughUnmappedProtectedKeys() {
    let shortcutModifiers: [KeyboardModifiers] = [
      .leftCommand, .rightCommand, .leftControl, .rightControl,
      [.leftCommand, .rightShift], [.rightControl, .rightOption],
    ]

    for modifiers in shortcutModifiers {
      let runtime = MouselessRuntime(permissions: .allGranted)
      enterFreeMode(runtime)
      let down = runtime.handle(
        .keyboard(
          KeyboardEvent(
            key: .digit1, phase: .down, timestamp: 1, isAutoRepeat: false,
            modifiers: modifiers)))
      let repeated = runtime.handle(
        .keyboard(
          KeyboardEvent(
            key: .digit1, phase: .down, timestamp: 1.1, isAutoRepeat: true,
            modifiers: modifiers)))
      let up = runtime.handle(.keyUp(.digit1, at: 1.2))

      XCTAssertEqual(down.disposition, .passThrough)
      XCTAssertEqual(repeated.disposition, .passThrough)
      XCTAssertEqual(up.disposition, .passThrough)
      XCTAssertTrue(down.effects.isEmpty)
      XCTAssertTrue(repeated.effects.isEmpty)
      XCTAssertTrue(up.effects.isEmpty)
    }
  }

  func testShiftCapsOptionAndFunctionDoNotBypassCharacterProtection() {
    let modifiers: [KeyboardModifiers] = [
      [], .leftShift, .rightShift, .capsLock, .rightOption, .function,
      [.leftShift, .rightOption], [.capsLock, .function],
    ]

    for modifierState in modifiers {
      let runtime = MouselessRuntime(permissions: .allGranted)
      enterFreeMode(runtime)

      let down = runtime.handle(
        .keyboard(
          KeyboardEvent(
            key: .digit1, phase: .down, timestamp: 1, isAutoRepeat: false,
            modifiers: modifierState)))
      let repeated = runtime.handle(
        .keyboard(
          KeyboardEvent(
            key: .digit1, phase: .down, timestamp: 1.1, isAutoRepeat: true,
            modifiers: modifierState)))
      let up = runtime.handle(
        .keyboard(
          KeyboardEvent(
            key: .digit1, phase: .up, timestamp: 1.2, isAutoRepeat: false, modifiers: [])))

      XCTAssertEqual(down.disposition, .consume, "down with (modifierState)")
      XCTAssertEqual(repeated.disposition, .consume, "repeat with (modifierState)")
      XCTAssertEqual(up.disposition, .consume, "up with (modifierState)")
      XCTAssertTrue(down.effects.isEmpty)
      XCTAssertTrue(repeated.effects.isEmpty)
      XCTAssertTrue(up.effects.isEmpty)
    }
  }

  func testKeyboardDispositionSurvivesEntryNormalExitAndLeftOptionReleaseBoundary() {
    let runtime = MouselessRuntime(permissions: .allGranted)

    let outsideDown = runtime.handle(.keyDown(.digit1, at: 1))
    _ = runtime.handle(.keyDown(.leftOption, at: 1.1))
    _ = runtime.handle(.keyUp(.leftOption, at: 1.2))
    let outsideRepeat = runtime.handle(.keyDown(.digit1, at: 1.3, isAutoRepeat: true))
    let outsideUp = runtime.handle(.keyUp(.digit1, at: 1.4))
    XCTAssertEqual(outsideDown.disposition, .passThrough)
    XCTAssertEqual(outsideRepeat.disposition, .passThrough)
    XCTAssertEqual(outsideUp.disposition, .passThrough)

    let insideDown = runtime.handle(.keyDown(.digit2, at: 2))
    let exit = runtime.handle(.keyDown(.leftOption, at: 2.1))
    let insideRepeat = runtime.handle(.keyDown(.digit2, at: 2.2, isAutoRepeat: true))
    let insideUp = runtime.handle(.keyUp(.digit2, at: 2.3))
    XCTAssertEqual(insideDown.disposition, .consume)
    XCTAssertTrue(exit.effects.contains(.modeChanged(isEnabled: false)))
    XCTAssertEqual(insideRepeat.disposition, .consume)
    XCTAssertEqual(insideUp.disposition, .consume)
    XCTAssertTrue(insideRepeat.effects.isEmpty)
    XCTAssertTrue(insideUp.effects.isEmpty)

    let heldExitDown = runtime.handle(.keyDown(.digit3, at: 2.4))
    let heldExitRepeat = runtime.handle(.keyDown(.digit3, at: 2.5, isAutoRepeat: true))
    let heldExitUp = runtime.handle(.keyUp(.digit3, at: 2.6))
    XCTAssertEqual(heldExitDown.disposition, .consume)
    XCTAssertEqual(heldExitRepeat.disposition, .consume)
    XCTAssertEqual(heldExitUp.disposition, .consume)
    XCTAssertTrue(heldExitDown.effects.isEmpty)
    XCTAssertTrue(heldExitRepeat.effects.isEmpty)
    XCTAssertTrue(heldExitUp.effects.isEmpty)

    XCTAssertEqual(runtime.handle(.keyUp(.leftOption, at: 2.7)).disposition, .passThrough)
    XCTAssertEqual(runtime.handle(.keyDown(.digit4, at: 2.8)).disposition, .passThrough)
    XCTAssertEqual(runtime.handle(.keyUp(.digit4, at: 2.9)).disposition, .passThrough)
  }

  func testFaultBoundaryDropsPendingKeyboardDispositionBeforeRecovery() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    XCTAssertEqual(runtime.handle(.keyDown(.digit1, at: 1)).disposition, .consume)

    let disabled = runtime.handle(.eventTapDisabled)
    XCTAssertTrue(disabled.effects.contains(.diagnostic(.safetyExit)))
    XCTAssertEqual(runtime.handle(.keyDown(.digit1, at: 1.1, isAutoRepeat: true)).disposition, .passThrough)
    XCTAssertEqual(runtime.handle(.keyUp(.digit1, at: 1.2)).disposition, .passThrough)

    _ = runtime.handle(.eventTapReenabled)
    XCTAssertEqual(runtime.handle(.keyDown(.digit2, at: 2)).disposition, .passThrough)
    XCTAssertEqual(runtime.handle(.keyUp(.digit2, at: 2.1)).disposition, .passThrough)
  }

  func testFixedSafetyExitReleasesButtonsAndFinishesKeyboardDispositions() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    XCTAssertEqual(runtime.handle(.keyDown(.l, at: 1)).disposition, .consume)

    let exit = runtime.handle(.keyDown(.leftOption, at: 2))
    _ = runtime.handle(.keyUp(.leftOption, at: 2.1))
    let up = runtime.handle(.keyUp(.l, at: 2.2))

    XCTAssertTrue(exit.effects.contains(.modeChanged(isEnabled: false)))
    XCTAssertEqual(up.disposition, .consume)
    XCTAssertTrue(up.effects.isEmpty)
  }

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

  func testRightOptionEntersWhenConfiguredAsActivationAndLeftOptionIsFixedSafetyExit() {
    let runtime = MouselessRuntime(
      configuration: RuntimeConfiguration(bindings: KeyBindings(activation: "rightOption")),
      permissions: .allGranted)

    XCTAssertEqual(runtime.handle(.keyDown(.rightOption, at: 0)).disposition, .passThrough)
    let entered = runtime.handle(.keyUp(.rightOption, at: 0.1))
    XCTAssertTrue(entered.effects.contains(.modeChanged(isEnabled: true)))

    let leftDown = runtime.handle(.keyDown(.leftOption, at: 1))
    XCTAssertEqual(leftDown.disposition, .passThrough)
    XCTAssertTrue(leftDown.effects.contains(.modeChanged(isEnabled: false)))
    XCTAssertTrue(leftDown.effects.contains(.indicator(isVisible: false)))
    XCTAssertEqual(runtime.handle(.keyUp(.leftOption, at: 1.5)).disposition, .passThrough)
  }

  func testConfiguredActivationDoesNotExitFreeModeAndModifiersCancelItsTap() {
    let runtime = MouselessRuntime(
      configuration: RuntimeConfiguration(bindings: KeyBindings(activation: "rightOption")),
      permissions: .allGranted)

    _ = runtime.handle(.keyDown(.rightOption, at: 0))
    let canceled = runtime.handle(
      .keyboard(
        KeyboardEvent(
          key: .rightCommand, phase: .down, timestamp: 0.01, isAutoRepeat: false,
          modifiers: [.rightCommand, .rightOption])))
    XCTAssertEqual(canceled.disposition, .passThrough)
    XCTAssertFalse(
      runtime.handle(.keyUp(.rightOption, at: 0.1)).effects.contains(.modeChanged(isEnabled: true)))

    _ = runtime.handle(.keyDown(.rightOption, at: 1))
    _ = runtime.handle(.keyUp(.rightOption, at: 1.1))
    XCTAssertTrue(runtime.handle(.keyDown(.rightOption, at: 2)).effects.isEmpty)
    let stillOn = runtime.handle(.keyUp(.rightOption, at: 2.1))
    XCTAssertFalse(stillOn.effects.contains(.modeChanged(isEnabled: false)))
  }

  func testEscapeAlwaysPassesThroughWithoutChangingFreeMode() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)

    let unmapped = runtime.handle(.keyDown(.other(99), at: 1))
    let mapped = runtime.handle(.keyDown(.i, at: 1.1))
    let escapeDown = runtime.handle(.keyDown(.escape, at: 1.2))
    let escapeRepeat = runtime.handle(.keyDown(.escape, at: 1.3, isAutoRepeat: true))
    let escapeUp = runtime.handle(.keyUp(.escape, at: 1.4))

    XCTAssertEqual(unmapped.disposition, .passThrough)
    XCTAssertEqual(mapped.disposition, .consume)
    XCTAssertEqual(escapeDown.disposition, .passThrough)
    XCTAssertEqual(escapeRepeat.disposition, .passThrough)
    XCTAssertEqual(escapeUp.disposition, .passThrough)
    XCTAssertTrue(escapeDown.effects.isEmpty)
    XCTAssertTrue(escapeRepeat.effects.isEmpty)
    XCTAssertTrue(escapeUp.effects.isEmpty)
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
    let exit = runtime.handle(.keyDown(.leftOption, at: 2.1))
    XCTAssertTrue(exit.effects.contains(.mouseButton(.right, .up)))

    let second = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(second)
    _ = second.handle(.keyDown(.space, at: 3))
    let tapExit = second.handle(.keyDown(.leftOption, at: 4))
    _ = second.handle(.keyUp(.leftOption, at: 4.1))
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
      var pendingConsumedKeys: Set<Key> = []
      for step in 0..<32 {
        let (key, _) = buttonBindings[Int(nextRandom() % UInt64(buttonBindings.count))]
        let timestamp = Double(sequenceIndex * 32 + step) + 1
        switch nextRandom() % 3 {
        case 0:
          let response = runtime.handle(.keyDown(key, at: timestamp))
          effects += response.effects
          if response.disposition == .consume { pendingConsumedKeys.insert(key) }
        case 1:
          effects += runtime.handle(.keyDown(key, at: timestamp, isAutoRepeat: true)).effects
        default:
          effects += runtime.handle(.keyUp(key, at: timestamp)).effects
          pendingConsumedKeys.remove(key)
        }
      }
      effects += runtime.handle(.keyDown(.leftOption, at: 10_000)).effects

      var balances = Dictionary(uniqueKeysWithValues: MouseButton.allCases.map { ($0, 0) })
      for effect in effects {
        guard case .mouseButton(let button, let phase) = effect else { continue }
        balances[button, default: 0] += phase == .down ? 1 : -1
        XCTAssertGreaterThanOrEqual(balances[button, default: 0], 0)
      }
      XCTAssertTrue(balances.values.allSatisfy { $0 == 0 })
      for (key, _) in buttonBindings {
        let expected: EventDisposition = pendingConsumedKeys.contains(key) ? .consume : .passThrough
        XCTAssertEqual(runtime.handle(.keyUp(key, at: 10_001)).disposition, expected)
      }
      _ = runtime.handle(.keyUp(.leftOption, at: 10_001.1))

      enterFreeMode(runtime)
      for (key, button) in buttonBindings {
        XCTAssertEqual(
          runtime.handle(.keyDown(key, at: 10_002)).effects, [.mouseButton(button, .down)])
        XCTAssertEqual(
          runtime.handle(.keyUp(key, at: 10_003)).effects, [.mouseButton(button, .up)])
      }
      _ = runtime.handle(.keyDown(.leftOption, at: 10_004))
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
    XCTAssertEqual(runtime.handle(.keyDown(.l, at: 2)).disposition, .passThrough)

    let inactive = runtime.handle(.sessionChanged(.inactive))
    XCTAssertTrue(inactive.effects.contains(.diagnostic(.safetyExit)))
  }

  func testSleepAndWakeKeepFreeModeOffUntilExplicitlyReenabled() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.space, at: 1))

    let sleeping = runtime.handle(.sessionChanged(.sleeping))
    XCTAssertTrue(sleeping.effects.contains(.mouseButton(.left, .up)))
    XCTAssertTrue(sleeping.effects.contains(.modeChanged(isEnabled: false)))

    XCTAssertTrue(runtime.handle(.sessionChanged(.waking)).effects.isEmpty)
    XCTAssertEqual(runtime.handle(.keyDown(.l, at: 2)).disposition, .passThrough)
    XCTAssertEqual(runtime.handle(.sessionChanged(.active)).effects, [])
    XCTAssertEqual(runtime.handle(.keyDown(.l, at: 3)).disposition, .passThrough)

    enterFreeMode(runtime)
    XCTAssertEqual(runtime.handle(.keyDown(.l, at: 4)).disposition, .consume)
  }

  func testLockedAndUnlockedSessionKeepsFreeModeOff() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.space, at: 1))

    let locked = runtime.handle(.sessionChanged(.locked))
    XCTAssertTrue(locked.effects.contains(.mouseButton(.left, .up)))
    XCTAssertTrue(locked.effects.contains(.modeChanged(isEnabled: false)))
    XCTAssertEqual(runtime.handle(.sessionChanged(.active)).effects, [])
    XCTAssertEqual(runtime.handle(.keyDown(.l, at: 2)).disposition, .passThrough)
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

  func testScrollBindingsProduceTheSpecifiedFourDirectionsAt960PointsPerSecond() throws {
    for binding in scrollBindings {
      let runtime = scrollingRuntime()
      enterFreeMode(runtime)
      _ = runtime.handle(.keyDown(binding.key, at: 1))

      let scroll = try XCTUnwrap(scroll(from: runtime.handle(.frame(deltaTime: 1))))
      XCTAssertEqual(
        Double(scroll.x), Double(binding.horizontalSign) * 960 * (1 - 0.001), accuracy: 1,
        "unexpected horizontal scroll for \(binding.key)")
      XCTAssertEqual(
        Double(scroll.y), Double(binding.verticalSign) * 960 * (1 - 0.001), accuracy: 1,
        "unexpected vertical scroll for \(binding.key)")
    }
  }

  func testScrollUsesQuarterPrecisionAndStacksThreeFourTimesFastKeys() throws {
    let keySets: [[Key]] = [[], [.s], [.d], [.f], [.s, .d], [.s, .f], [.d, .f], [.s, .d, .f]]

    for precision in [false, true] {
      for fastKeys in keySets {
        let runtime = scrollingRuntime()
        enterFreeMode(runtime)
        _ = runtime.handle(.keyDown(.m, at: 1))
        if precision { _ = runtime.handle(.keyDown(.a, at: 1.1)) }
        for key in fastKeys { _ = runtime.handle(.keyDown(key, at: 1.2)) }

        let scroll = try XCTUnwrap(scroll(from: runtime.handle(.frame(deltaTime: 1))))
        let expected = 960.0 * (precision ? 0.25 : 1) * pow(4, Double(fastKeys.count))
        XCTAssertEqual(Double(scroll.y), expected * (1 - 0.001), accuracy: 1)
      }
    }
  }

  func testScrollOpposingDirectionsCancelAndDiagonalInputIsNormalized() throws {
    let opposing = scrollingRuntime()
    enterFreeMode(opposing)
    _ = opposing.handle(.keyDown(.m, at: 1))
    _ = opposing.handle(.keyDown(.comma, at: 1.1))
    XCTAssertNil(scroll(from: opposing.handle(.frame(deltaTime: 1))))

    let diagonal = scrollingRuntime()
    enterFreeMode(diagonal)
    _ = diagonal.handle(.keyDown(.m, at: 1))
    _ = diagonal.handle(.keyDown(.slash, at: 1.1))
    let result = try XCTUnwrap(scroll(from: diagonal.handle(.frame(deltaTime: 1))))
    let expected = 960.0 / sqrt(2)
    XCTAssertEqual(Double(result.x), expected, accuracy: 1)
    XCTAssertEqual(Double(result.y), expected, accuracy: 1)
  }

  func testScrollSmoothingUsesTheConfigured47MillisecondTimeConstant() throws {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.m, at: 1))

    let alpha = 1 - exp(-1.0)
    let first = try XCTUnwrap(scroll(from: runtime.handle(.frame(deltaTime: 0.047))))
    let firstDisplacement = 960 * 0.047 * (1 - alpha)
    XCTAssertEqual(Double(first.y), firstDisplacement, accuracy: 1)

    _ = runtime.handle(.keyDown(.a, at: 1.047))
    let changed = try XCTUnwrap(scroll(from: runtime.handle(.frame(deltaTime: 0.047))))
    let firstVelocity = 960 * alpha
    let changedDisplacement = 240 * 0.047 + (firstVelocity - 240) * 0.047 * alpha
    XCTAssertEqual(Double(first.y + changed.y), firstDisplacement + changedDisplacement, accuracy: 1)
    XCTAssertEqual(runtime.handle(.frame(deltaTime: 0)).effects, [])
  }

  func testScrollRetainsSubpixelRemainderAndDoesNotDependOnRefreshRate() {
    let fine = scrollingTotal(frameDelta: 0.001, frameCount: 1_000)
    let sixtyHertz = scrollingTotal(frameDelta: 1.0 / 60.0, frameCount: 60)
    let oneTwentyHertz = scrollingTotal(frameDelta: 1.0 / 120.0, frameCount: 120)

    XCTAssertGreaterThan(fine, 0)
    XCTAssertEqual(fine, sixtyHertz, accuracy: 1)
    XCTAssertEqual(sixtyHertz, oneTwentyHertz, accuracy: 1)
  }

  func testScrollReleaseDeceleratesToZeroWithoutFurtherEvents() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.m, at: 1))
    _ = runtime.handle(.frame(deltaTime: 0.2))
    _ = runtime.handle(.keyUp(.m, at: 1.2))

    var releasedTotal = 0
    for _ in 0..<10 { releasedTotal += abs(scroll(from: runtime.handle(.frame(deltaTime: 0.2)))?.y ?? 0) }
    XCTAssertGreaterThan(releasedTotal, 0)
    XCTAssertNil(scroll(from: runtime.handle(.frame(deltaTime: 1))))
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
    XCTAssertTrue(rejected.effects.contains(where: { effect in
      if case .configurationRejected = effect { return true }
      return false
    }))
  }

  func testDefaultConfigurationUsesSchemaV2ActivationWithoutEscapeBinding() throws {
    let object = try configurationObject()
    XCTAssertEqual(object["schemaVersion"] as? Int, 2)
    let bindings = try XCTUnwrap(object["bindings"] as? [String: Any])
    XCTAssertEqual(bindings["activation"] as? String, "leftOption")
    XCTAssertNil(bindings["toggle"])
    XCTAssertNil(bindings["escape"])
  }

  func testSchemaV2AcceptsOnlyLeftOrRightOptionAsActivation() throws {
    for activation in ["leftOption", "rightOption"] {
      var object = try configurationObject()
      var bindings = try XCTUnwrap(object["bindings"] as? [String: Any])
      bindings["activation"] = activation
      object["bindings"] = bindings

      let response = MouselessRuntime(permissions: .allGranted).handle(
        .configuration(try JSONSerialization.data(withJSONObject: object)))
      XCTAssertTrue(response.effects.contains(.configurationAccepted), activation)
    }

    var invalid = try configurationObject()
    var bindings = try XCTUnwrap(invalid["bindings"] as? [String: Any])
    bindings["activation"] = "space"
    invalid["bindings"] = bindings
    let response = MouselessRuntime(permissions: .allGranted).handle(
      .configuration(try JSONSerialization.data(withJSONObject: invalid)))
    XCTAssertTrue(response.effects.contains(where: { effect in
      if case .configurationRejected(let reason) = effect {
        return reason.contains("activation") && reason.contains("leftOption")
          && reason.contains("rightOption")
      }
      return false
    }))
  }

  func testSchemaV2RejectsRemovedEscapeAndEscapeAsAnyAction() throws {
    var withRemovedField = try configurationObject()
    var bindings = try XCTUnwrap(withRemovedField["bindings"] as? [String: Any])
    bindings["escape"] = "escape"
    withRemovedField["bindings"] = bindings
    let removedResponse = MouselessRuntime(permissions: .allGranted).handle(
      .configuration(try JSONSerialization.data(withJSONObject: withRemovedField)))
    XCTAssertTrue(removedResponse.effects.contains(where: { effect in
      if case .configurationRejected(let reason) = effect { return reason.contains("unknown field") }
      return false
    }))

    var asAction = try configurationObject()
    var actionBindings = try XCTUnwrap(asAction["bindings"] as? [String: Any])
    actionBindings["moveUp"] = "escape"
    asAction["bindings"] = actionBindings
    let actionResponse = MouselessRuntime(permissions: .allGranted).handle(
      .configuration(try JSONSerialization.data(withJSONObject: asAction)))
    XCTAssertTrue(actionResponse.effects.contains(where: { effect in
      if case .configurationRejected(let reason) = effect {
        return reason.contains("Escape") || reason.contains("escape")
      }
      return false
    }))
  }

  func testSchemaV1MigratesOptionToggleAndDropsEscapeBinding() throws {
    var object = try configurationObject()
    object["schemaVersion"] = 1
    var bindings = try XCTUnwrap(object["bindings"] as? [String: Any])
    bindings.removeValue(forKey: "activation")
    bindings["toggle"] = "rightOption"
    bindings["escape"] = "escape"
    bindings["moveUp"] = "l"
    bindings["moveRight"] = "i"
    object["bindings"] = bindings

    let runtime = MouselessRuntime(permissions: .allGranted)
    let response = runtime.handle(
      .configuration(try JSONSerialization.data(withJSONObject: object)))
    XCTAssertTrue(response.effects.contains(.configurationAccepted))

    _ = runtime.handle(.keyDown(.rightOption, at: 0))
    XCTAssertTrue(runtime.handle(.keyUp(.rightOption, at: 0.1)).effects.contains(.modeChanged(isEnabled: true)))
    XCTAssertEqual(runtime.handle(.keyDown(.escape, at: 1)).disposition, .passThrough)
    XCTAssertEqual(runtime.handle(.keyDown(.l, at: 2)).disposition, .consume)
  }

  func testSchemaV1RejectsNonOptionToggleWithExplicitActivationError() throws {
    for toggle in ["i", "space", "escape"] {
      var object = try configurationObject()
      object["schemaVersion"] = 1
      var bindings = try XCTUnwrap(object["bindings"] as? [String: Any])
      bindings.removeValue(forKey: "activation")
      bindings["toggle"] = toggle
      bindings["escape"] = "escape"
      object["bindings"] = bindings

      let response = MouselessRuntime(permissions: .allGranted).handle(
        .configuration(try JSONSerialization.data(withJSONObject: object)))
      XCTAssertTrue(response.effects.contains(where: { effect in
        if case .configurationRejected(let reason) = effect {
          return reason.contains("activation") && reason.contains("leftOption")
            && reason.contains("rightOption")
        }
        return false
      }), toggle)
    }
  }

  func testRejectedMigrationLeavesPreviousV2ConfigurationActive() throws {
    let runtime = MouselessRuntime(permissions: .allGranted)
    _ = runtime.handle(.configuration(RuntimeConfiguration.defaultJSON))

    var invalid = try configurationObject()
    invalid["schemaVersion"] = 1
    var bindings = try XCTUnwrap(invalid["bindings"] as? [String: Any])
    bindings.removeValue(forKey: "activation")
    bindings["toggle"] = "space"
    bindings["escape"] = "escape"
    invalid["bindings"] = bindings
    let rejected = runtime.handle(
      .configuration(try JSONSerialization.data(withJSONObject: invalid)))
    XCTAssertTrue(rejected.effects.contains(where: { effect in
      if case .configurationRejected = effect { return true }
      return false
    }))

    _ = runtime.handle(.keyDown(.leftOption, at: 0))
    XCTAssertTrue(runtime.handle(.keyUp(.leftOption, at: 0.1)).effects.contains(.modeChanged(isEnabled: true)))
  }

  func testAcceptedConfigurationReleasesButtonsBeforeReplacingBindings() throws {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.space, at: 1))

    var object = try configurationObject()
    var bindings = try XCTUnwrap(object["bindings"] as? [String: Any])
    bindings["leftClick"] = "r"
    bindings["rightClick"] = "space"
    object["bindings"] = bindings

    let response = runtime.handle(
      .configuration(try JSONSerialization.data(withJSONObject: object)))
    XCTAssertEqual(response.effects.first, .mouseButton(.left, .up))
    XCTAssertTrue(response.effects.contains(.configurationAccepted))
  }

  func testDefaultConfigurationJSONContainsTheConfirmedDefaultsAndSchemaVersion() throws {
    let accepted = MouselessRuntime(permissions: .allGranted).handle(
      .configuration(RuntimeConfiguration.defaultJSON))

    XCTAssertTrue(accepted.effects.contains(.configurationAccepted))
  }

  func testValidConfigurationChangesBindingsThresholdScrollAndIndicator() throws {
    let runtime = MouselessRuntime(permissions: .allGranted)
    var object = try configurationObject()
    var bindings = try XCTUnwrap(object["bindings"] as? [String: Any])
    bindings["moveUp"] = "l"
    bindings["moveRight"] = "i"
    object["bindings"] = bindings
    object["optionTapMilliseconds"] = 100.0
    var scrolling = try XCTUnwrap(object["scrolling"] as? [String: Any])
    scrolling["baseSpeed"] = 100.0
    scrolling["precisionMultiplier"] = 0.5
    scrolling["fastMultiplier"] = 2.0
    scrolling["smoothingMilliseconds"] = 1.0
    object["scrolling"] = scrolling
    var indicator = try XCTUnwrap(object["indicator"] as? [String: Any])
    indicator["enabled"] = false
    object["indicator"] = indicator

    let accepted = runtime.handle(
      .configuration(try JSONSerialization.data(withJSONObject: object)))
    XCTAssertTrue(accepted.effects.contains(.configurationAccepted))

    _ = runtime.handle(.keyDown(.leftOption, at: 0))
    let timedOut = runtime.handle(.keyUp(.leftOption, at: 0.101))
    XCTAssertFalse(timedOut.effects.contains(.modeChanged(isEnabled: true)))
    _ = runtime.handle(.keyDown(.leftOption, at: 1))
    let entered = runtime.handle(.keyUp(.leftOption, at: 1.05))
    XCTAssertTrue(entered.effects.contains(.indicator(isVisible: false)))

    _ = runtime.handle(.keyDown(.i, at: 2))
    let right = try XCTUnwrap(pointer(from: runtime.handle(.frame(deltaTime: 1))))
    XCTAssertEqual(right.x, 300, accuracy: 0.5)
    XCTAssertEqual(right.y, 0, accuracy: 0.5)

    _ = runtime.handle(.keyUp(.i, at: 3))
    _ = runtime.handle(.keyDown(.m, at: 3.1))
    _ = runtime.handle(.keyDown(.a, at: 3.2))
    _ = runtime.handle(.keyDown(.s, at: 3.3))
    let scroll = try XCTUnwrap(scroll(from: runtime.handle(.frame(deltaTime: 1))))
    XCTAssertEqual(scroll.y, 100, accuracy: 1)
  }

  func testValidConfigurationChangesRuntimeBehaviorAndIndicatorSize() throws {
    let runtime = MouselessRuntime(permissions: .allGranted)
    var object = try configurationObject()
    var movement = try XCTUnwrap(object["movement"] as? [String: Any])
    movement["baseSpeed"] = 600.0
    object["movement"] = movement
    var indicator = try XCTUnwrap(object["indicator"] as? [String: Any])
    indicator["size"] = 12.0
    object["indicator"] = indicator

    let accepted = runtime.handle(.configuration(try JSONSerialization.data(withJSONObject: object)))
    XCTAssertTrue(accepted.effects.contains(.configurationAccepted))

    _ = runtime.handle(.keyDown(.leftOption, at: 0))
    let entered = runtime.handle(.keyUp(.leftOption, at: 0.1))
    XCTAssertTrue(containsIndicatorSize(12, in: entered))
    _ = runtime.handle(.keyDown(.l, at: 1))
    XCTAssertEqual(try XCTUnwrap(pointer(from: runtime.handle(.frame(deltaTime: 1)))).x, 600, accuracy: 0.5)
  }

  func testRejectedConfigurationPreservesThePreviousValidBehavior() throws {
    let runtime = MouselessRuntime(permissions: .allGranted)
    var validObject = try configurationObject()
    var movement = try XCTUnwrap(validObject["movement"] as? [String: Any])
    movement["baseSpeed"] = 600.0
    validObject["movement"] = movement
    _ = runtime.handle(.configuration(try JSONSerialization.data(withJSONObject: validObject)))

    var invalidObject = validObject
    invalidObject["unexpected"] = true
    let rejected = runtime.handle(.configuration(try JSONSerialization.data(withJSONObject: invalidObject)))
    XCTAssertTrue(rejected.effects.contains(where: { effect in
      if case .configurationRejected(let reason) = effect { return reason.contains("unknown field") }
      return false
    }))

    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.l, at: 1))
    XCTAssertEqual(try XCTUnwrap(pointer(from: runtime.handle(.frame(deltaTime: 1)))).x, 600, accuracy: 0.5)
  }

  func testConfigurationRejectsMalformedJSONWithAReadableReason() {
    let response = MouselessRuntime(permissions: .allGranted).handle(
      .configuration(Data("{not json".utf8)))

    XCTAssertTrue(response.effects.contains(where: { effect in
      if case .configurationRejected(let reason) = effect { return reason.contains("invalid JSON") }
      return false
    }))
  }

  func testConfigurationRejectsUnsupportedSchemaVersion() throws {
    var object = try configurationObject()
    object["schemaVersion"] = 3

    let response = MouselessRuntime(permissions: .allGranted).handle(
      .configuration(try JSONSerialization.data(withJSONObject: object)))

    XCTAssertTrue(response.effects.contains(where: { effect in
      if case .configurationRejected(let reason) = effect {
        return reason.contains("schema version") && reason.contains("3")
      }
      return false
    }))
  }

  func testConfigurationRejectsDuplicateBindings() throws {
    var object = try configurationObject()
    var bindings = try XCTUnwrap(object["bindings"] as? [String: Any])
    bindings["moveDown"] = bindings["moveUp"]
    object["bindings"] = bindings

    let response = MouselessRuntime(permissions: .allGranted).handle(
      .configuration(try JSONSerialization.data(withJSONObject: object)))

    XCTAssertTrue(response.effects.contains(where: { effect in
      if case .configurationRejected(let reason) = effect { return reason.contains("duplicate binding") }
      return false
    }))
  }

  func testConfigurationRejectsOutOfRangeParameters() throws {
    var object = try configurationObject()
    var scrolling = try XCTUnwrap(object["scrolling"] as? [String: Any])
    scrolling["smoothingMilliseconds"] = 0.0
    object["scrolling"] = scrolling

    let response = MouselessRuntime(permissions: .allGranted).handle(
      .configuration(try JSONSerialization.data(withJSONObject: object)))

    XCTAssertTrue(response.effects.contains(where: { effect in
      if case .configurationRejected(let reason) = effect {
        return reason.contains("scrolling.smoothingMilliseconds")
      }
      return false
    }))
  }

  func testDiagnosticSummaryContainsApprovedFieldsWithoutSensitiveHistory() {
    var counters = DiagnosticCounters()
    counters.callbackCount = 12
    counters.frameCount = 60
    counters.modeChangeCount = 2
    counters.safetyExitCount = 1
    counters.pointerEffectCount = 24

    let summary = DiagnosticSummary(
      version: "0.1.0", buildIdentity: "Debug", permissions: .allGranted,
      configuration: .valid, eventTap: .healthy, counters: counters)

    XCTAssertTrue(summary.text.contains("version: 0.1.0"))
    XCTAssertTrue(summary.text.contains("buildIdentity: Debug"))
    XCTAssertTrue(summary.text.contains("permissions: accessibility=true"))
    XCTAssertTrue(summary.text.contains("configuration: valid"))
    XCTAssertTrue(summary.text.contains("eventTap: healthy"))
    XCTAssertTrue(summary.text.contains("callbacks: 12"))
    XCTAssertTrue(summary.text.contains("frames: 60"))
    XCTAssertTrue(summary.text.contains("pointerEffects: 24"))

    for sensitiveField in [
      "keyHistory", "inputText", "applicationName", "windowTitle", "pointerHistory", "Chrome",
      "hello", "leftOption", "space",
    ] {
      XCTAssertFalse(summary.text.contains(sensitiveField), "unexpected field: \(sensitiveField)")
    }
  }

  func testDiagnosticSummaryDistinguishesConfigurationAndEventTapFailures() {
    let counters = DiagnosticCounters()
    let valid = DiagnosticSummary(
      version: "0.1.0", buildIdentity: "Release", permissions: .allGranted,
      configuration: .valid, eventTap: .healthy, counters: counters)
    let failed = DiagnosticSummary(
      version: "0.1.0", buildIdentity: "Release", permissions: .none,
      configuration: .invalid, eventTap: .recoveryFailed, counters: counters)

    XCTAssertTrue(valid.text.contains("configuration: valid"))
    XCTAssertTrue(valid.text.contains("eventTap: healthy"))
    XCTAssertTrue(failed.text.contains("configuration: invalid"))
    XCTAssertTrue(failed.text.contains("eventTap: recoveryFailed"))
    XCTAssertNotEqual(valid.text, failed.text)
  }

  func testDiagnosticCountersAggregateOnlyPublicEffects() {
    var counters = DiagnosticCounters()
    counters.record([
      .diagnostic(.configurationRejected), .diagnostic(.eventTapDisabled),
      .diagnostic(.eventTapRecovered), .diagnostic(.eventTapRecoveryFailed),
      .diagnostic(.safetyExit), .modeChanged(isEnabled: true),
      .pointerMoved(to: Point(x: 100, y: 200), buttons: []),
      .mouseButton(.left, .down), .scroll(pixelX: 1, pixelY: -1),
    ])

    XCTAssertEqual(counters.configurationRejectedCount, 1)
    XCTAssertEqual(counters.eventTapDisabledCount, 1)
    XCTAssertEqual(counters.eventTapRecoveryCount, 1)
    XCTAssertEqual(counters.eventTapRecoveryFailureCount, 1)
    XCTAssertEqual(counters.safetyExitCount, 1)
    XCTAssertEqual(counters.modeChangeCount, 1)
    XCTAssertEqual(counters.pointerEffectCount, 1)
    XCTAssertEqual(counters.mouseButtonEffectCount, 1)
    XCTAssertEqual(counters.scrollEffectCount, 1)
  }

  func testEventTapFailureSafelyExitsBeforeRequestingRecovery() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.space, at: 1))
    let response = runtime.handle(.eventTapDisabled)

    XCTAssertEqual(response.disposition, .passThrough)
    XCTAssertTrue(response.effects.contains(.eventTapShouldBeReenabled))
    XCTAssertTrue(response.effects.contains(.diagnostic(.eventTapDisabled)))
    XCTAssertTrue(response.effects.contains(.mouseButton(.left, .up)))
    XCTAssertTrue(response.effects.contains(.modeChanged(isEnabled: false)))

    let recovered = runtime.handle(.eventTapReenabled)
    XCTAssertEqual(
      recovered.effects,
      [.diagnostic(.eventTapRecovered), .freeModeStatusChanged(.available)])
  }

  func testEventTapRecoveryFailureExitsAndReturnsAllKeyboardEvents() {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.space, at: 1))

    let failed = runtime.handle(.eventTapRecoveryFailed)
    XCTAssertEqual(failed.disposition, .passThrough)
    XCTAssertTrue(failed.effects.contains(.mouseButton(.left, .up)))
    XCTAssertTrue(failed.effects.contains(.modeChanged(isEnabled: false)))
    XCTAssertTrue(failed.effects.contains(.diagnostic(.eventTapRecoveryFailed)))
    XCTAssertEqual(runtime.handle(.keyDown(.l, at: 2)).disposition, .passThrough)
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

  private func scrollingRuntime() -> MouselessRuntime {
    MouselessRuntime(
      configuration: RuntimeConfiguration(
        scrolling: ScrollSettings(smoothingMilliseconds: 1)), permissions: .allGranted)
  }

  private func scroll(from response: RuntimeResponse) -> (x: Int, y: Int)? {
    response.effects.compactMap { effect in
      guard case .scroll(let pixelX, let pixelY) = effect else { return nil }
      return (pixelX, pixelY)
    }.last
  }

  private func scrollingTotal(frameDelta: TimeInterval, frameCount: Int) -> Int {
    let runtime = MouselessRuntime(permissions: .allGranted)
    enterFreeMode(runtime)
    _ = runtime.handle(.keyDown(.m, at: 1))
    var total = 0
    for _ in 0..<frameCount { total += scroll(from: runtime.handle(.frame(deltaTime: frameDelta)))?.y ?? 0 }
    return total
  }

  private func configurationObject() throws -> [String: Any] {
    try XCTUnwrap(
      JSONSerialization.jsonObject(with: RuntimeConfiguration.defaultJSON) as? [String: Any])
  }

  private func containsIndicatorSize(_ size: Double, in response: RuntimeResponse) -> Bool {
    response.effects.contains(where: { effect in
      if case .indicatorSizeChanged(let actualSize) = effect {
        return actualSize == size
      }
      return false
    })
  }
}
