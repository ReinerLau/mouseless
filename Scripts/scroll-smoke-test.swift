import CoreGraphics
import Foundation

private let optionKey: CGKeyCode = 58
private let mKey: CGKeyCode = 46
private let commaKey: CGKeyCode = 43
private let periodKey: CGKeyCode = 47
private let slashKey: CGKeyCode = 44
private let eventSource = CGEventSource(stateID: .combinedSessionState)

private struct ObservedScroll {
  let vertical: Int
  let horizontal: Int
}

private final class ScrollEventCapture {
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private(set) var events: [ObservedScroll] = []

  func start() -> Bool {
    let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
      eventsOfInterest: mask, callback: captureEvent,
      userInfo: Unmanaged.passUnretained(self).toOpaque())
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

  fileprivate func receive(_ event: CGEvent) -> Unmanaged<CGEvent> {
    events.append(ObservedScroll(
      vertical: Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
      horizontal: Int(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))))
    return Unmanaged.passUnretained(event)
  }
}

private func captureEvent(
  proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard type == .scrollWheel, let userInfo else { return Unmanaged.passUnretained(event) }
  return Unmanaged<ScrollEventCapture>.fromOpaque(userInfo).takeUnretainedValue().receive(event)
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
  Thread.sleep(forTimeInterval: 0.1)
}

private func summedScrollDelta(_ events: [ObservedScroll]) -> ObservedScroll {
  ObservedScroll(
    vertical: events.reduce(0) { $0 + $1.vertical },
    horizontal: events.reduce(0) { $0 + $1.horizontal })
}

private func capturesExpectedDirection(
  _ value: ObservedScroll, verticalSign: Int, horizontalSign: Int
) -> Bool {
  let verticalOK = verticalSign == 0
    ? abs(value.vertical) <= 2
    : value.vertical * verticalSign > 10
  let horizontalOK = horizontalSign == 0
    ? abs(value.horizontal) <= 2
    : value.horizontal * horizontalSign > 10
  return verticalOK && horizontalOK
}

func run() -> Int32 {
  let capture = ScrollEventCapture()
  guard capture.start() else {
    fputs("FAIL: could not create the observing scroll event tap.\n", stderr)
    return 1
  }
  defer { capture.stop() }

  print("Starting real-app scroll smoke test; ensure Mouseless is running, ready, and free mode is off.")
  tapOption()

  let bindings: [(name: String, key: CGKeyCode, verticalSign: Int, horizontalSign: Int)] = [
    ("M/up", mKey, 1, 0),
    ("comma/down", commaKey, -1, 0),
    ("period/left", periodKey, 0, -1),
    ("slash/right", slashKey, 0, 1),
  ]
  for binding in bindings {
    capture.clear()
    postKey(binding.key, isDown: true)
    capture.pump(for: 0.25)
    postKey(binding.key, isDown: false)
    capture.pump(for: 0.2)
    let result = summedScrollDelta(capture.events)
    guard capturesExpectedDirection(
      result, verticalSign: binding.verticalSign, horizontalSign: binding.horizontalSign)
    else {
      fputs(
        "FAIL: \(binding.name) produced unexpected scroll delta (horizontal=\(result.horizontal), vertical=\(result.vertical)).\n",
        stderr)
      tapOption()
      return 1
    }
    print("PASS: \(binding.name) produced the expected scroll direction.")
  }

  tapOption()
  return 0
}

exit(run())
