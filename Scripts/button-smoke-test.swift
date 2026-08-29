import CoreGraphics
import Foundation

private let optionKey: CGKeyCode = 58
private let spaceKey: CGKeyCode = 49
private let rKey: CGKeyCode = 15
private let eKey: CGKeyCode = 14
private let qKey: CGKeyCode = 12
private let wKey: CGKeyCode = 13
private let lKey: CGKeyCode = 37
private let eventSource = CGEventSource(stateID: .combinedSessionState)
private let doubleClickGap =
  Double(ProcessInfo.processInfo.environment["KEYVEER_DOUBLE_CLICK_GAP"] ?? "0.05") ?? 0.05

private enum SmokeButton: Int, CaseIterable {
  case left = 0
  case right = 1
  case middle = 2
  case back = 3
  case forward = 4
}

private struct ObservedMouseEvent {
  let type: CGEventType
  let button: Int
  let clickState: Int
}

private struct SmokeBinding {
  let name: String
  let key: CGKeyCode
  let button: SmokeButton
}

private final class MouseEventCapture {
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private(set) var events: [ObservedMouseEvent] = []

  func start() -> Bool {
    let types: [CGEventType] = [
      .leftMouseDown, .leftMouseUp, .leftMouseDragged,
      .rightMouseDown, .rightMouseUp, .rightMouseDragged,
      .otherMouseDown, .otherMouseUp, .otherMouseDragged,
    ]
    let mask = types.reduce(CGEventMask(0)) { mask, type in
      mask | (CGEventMask(1) << type.rawValue)
    }
    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
      eventsOfInterest: mask, callback: captureEvent, userInfo: Unmanaged.passUnretained(self).toOpaque())
    else { return false }
    guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return false }
    self.tap = tap
    self.source = source
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }

  func clear() { events.removeAll() }

  func pump(for duration: TimeInterval) {
    let deadline = Date().addingTimeInterval(duration)
    repeat {
      CFRunLoopRunInMode(.defaultMode, 0.01, false)
    } while Date() < deadline
  }

  func stop() {
    guard let tap else { return }
    CGEvent.tapEnable(tap: tap, enable: false)
    if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
    self.source = nil
    self.tap = nil
  }

  fileprivate func receive(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
    let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
    let clickState = Int(event.getIntegerValueField(.mouseEventClickState))
    events.append(
      ObservedMouseEvent(type: type, button: button, clickState: clickState))
    return Unmanaged.passUnretained(event)
  }
}

private func captureEvent(
  proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  return Unmanaged<MouseEventCapture>.fromOpaque(userInfo).takeUnretainedValue().receive(type, event: event)
}

private func postKey(_ key: CGKeyCode, isDown: Bool) {
  guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: isDown)
  else { fatalError("Could not create keyboard event") }
  event.post(tap: .cghidEventTap)
}

private func tapOption() {
  postKey(optionKey, isDown: true)
  Thread.sleep(forTimeInterval: 0.05)
  postKey(optionKey, isDown: false)
}

private func movePointerToTestOrigin() {
  let bounds = CGDisplayBounds(CGMainDisplayID())
  let point = CGPoint(x: bounds.midX, y: bounds.midY)
  guard
    let event = CGEvent(
      mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: point,
      mouseButton: .left)
  else { fatalError("Could not create pointer event") }
  event.post(tap: .cghidEventTap)
}

private func buttonEventType(button: SmokeButton, down: Bool) -> CGEventType {
  switch button {
  case .left: return down ? .leftMouseDown : .leftMouseUp
  case .right: return down ? .rightMouseDown : .rightMouseUp
  default: return down ? .otherMouseDown : .otherMouseUp
  }
}

private func hasPair(
  _ events: [ObservedMouseEvent], button: SmokeButton, down: CGEventType, up: CGEventType
) -> Bool {
  let types = events.filter { $0.button == button.rawValue }.map(\.type)
  return types == [down, up]
}

private func draggedEventType(for button: SmokeButton) -> CGEventType {
  switch button {
  case .left: return .leftMouseDragged
  case .right: return .rightMouseDragged
  default: return .otherMouseDragged
  }
}

private func hasDoubleClick(_ events: [ObservedMouseEvent]) -> Bool {
  let leftEvents = events.filter { $0.button == SmokeButton.left.rawValue }
  guard leftEvents.count == 4 else { return false }
  return leftEvents.map(\.type) == [.leftMouseDown, .leftMouseUp, .leftMouseDown, .leftMouseUp]
    && leftEvents.map(\.clickState) == [1, 1, 2, 2]
}

func run() -> Int32 {
  let capture = MouseEventCapture()
  guard capture.start() else {
    fputs("FAIL: could not create the observing mouse event tap.\n", stderr)
    return 1
  }
  defer { capture.stop() }

  movePointerToTestOrigin()
  Thread.sleep(forTimeInterval: 0.1)
  tapOption()
  capture.pump(for: 0.1)

  capture.clear()
  for _ in 0..<2 {
    postKey(spaceKey, isDown: true)
    capture.pump(for: doubleClickGap)
    postKey(spaceKey, isDown: false)
    capture.pump(for: doubleClickGap)
  }
  guard hasDoubleClick(capture.events) else {
    let observed = capture.events.map {
      "\($0.type.rawValue)/\($0.button)/\($0.clickState)"
    }
      .joined(separator: ",")
    fputs("Observed double-click events: [\(observed)]\n", stderr)
    fputs("FAIL: two space presses did not produce a system-recognizable double click.\n", stderr)
    tapOption()
    return 1
  }
  print("PASS: two space presses produced a system-recognizable double click.")

  let buttons: [SmokeBinding] = [
    SmokeBinding(name: "left", key: spaceKey, button: .left),
    SmokeBinding(name: "right", key: rKey, button: .right),
    SmokeBinding(name: "middle", key: eKey, button: .middle),
    SmokeBinding(name: "back", key: qKey, button: .back),
    SmokeBinding(name: "forward", key: wKey, button: .forward),
  ]
  for binding in buttons {
    let name = binding.name
    let key = binding.key
    let button = binding.button
    capture.clear()
    postKey(key, isDown: true)
    capture.pump(for: 0.1)
    postKey(key, isDown: false)
    capture.pump(for: 0.1)
    guard
      hasPair(
        capture.events, button: button,
        down: buttonEventType(button: button, down: true),
        up: buttonEventType(button: button, down: false))
    else {
      let observed = capture.events.map { "\($0.type.rawValue)/\($0.button)" }.joined(separator: ",")
      fputs("Observed events: [\(observed)]\n", stderr)
      fputs("FAIL: missing paired \(name) mouse events.\n", stderr)
      tapOption()
      return 1
    }
    print("PASS: \(name) click produced paired mouse events.")
  }

  for binding in buttons {
    let name = binding.name
    let key = binding.key
    let button = binding.button
    capture.clear()
    postKey(key, isDown: true)
    capture.pump(for: 0.1)
    postKey(lKey, isDown: true)
    capture.pump(for: 0.3)
    postKey(lKey, isDown: false)
    postKey(key, isDown: false)
    capture.pump(for: 0.2)
    guard capture.events.contains(where: {
      $0.type == draggedEventType(for: button) && $0.button == button.rawValue
    }) else {
      fputs("FAIL: holding the \(name) button did not produce a dragged event.\n", stderr)
      tapOption()
      return 1
    }
    print("PASS: \(name)-button drag produced dragged events.")
  }
  tapOption()
  return 0
}

exit(run())
