import CoreGraphics
import Foundation
import AppKit

private let optionKey: CGKeyCode = 58
private let aKey: CGKeyCode = 0
private let sKey: CGKeyCode = 1
private let dKey: CGKeyCode = 2
private let fKey: CGKeyCode = 3
private let lKey: CGKeyCode = 37

private let eventSource = CGEventSource(stateID: .combinedSessionState)

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

private func pointerLocation() -> CGPoint {
  guard let location = CGEvent(source: nil)?.location else {
    fatalError("Could not read pointer location")
  }
  return location
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

private func activeDisplayBounds() -> [CGRect] {
  var count: UInt32 = 0
  let maxDisplays: UInt32 = 32
  var displays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
  guard CGGetActiveDisplayList(maxDisplays, &displays, &count) == .success else { return [] }
  return displays.prefix(Int(count)).map { CGDisplayBounds($0) }
}

private func verifyHorizontalMultiDisplayMotion() -> Bool {
  let bounds = activeDisplayBounds()
  guard let pair = bounds
    .flatMap({ left in bounds.compactMap { right -> (CGRect, CGRect)? in
      guard right.origin.x >= left.maxX,
        right.minY < left.maxY, left.minY < right.maxY
      else { return nil }
      return (left, right)
    }})
    .min(by: { $0.1.origin.x - $0.0.maxX < $1.1.origin.x - $1.0.maxX })
  else {
    print("Skipping multi-display topology motion: no horizontally reachable display pair.")
    return true
  }

  let left = pair.0
  let right = pair.1
  let overlapMinY = max(left.minY, right.minY)
  let overlapMaxY = min(left.maxY, right.maxY)
  let y = (overlapMinY + overlapMaxY) / 2
  let start = CGPoint(x: left.maxX - 16, y: y)
  guard
    let event = CGEvent(
      mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: start,
      mouseButton: .left)
  else { return false }
  event.post(tap: .cghidEventTap)
  Thread.sleep(forTimeInterval: 0.1)

  postKey(optionKey, isDown: true)
  Thread.sleep(forTimeInterval: 0.05)
  postKey(optionKey, isDown: false)
  Thread.sleep(forTimeInterval: 0.1)
  postKey(lKey, isDown: true)
  Thread.sleep(forTimeInterval: min(max((right.maxX - start.x) / 250 + 1, 1), 8))
  postKey(lKey, isDown: false)
  Thread.sleep(forTimeInterval: 0.1)
  let end = pointerLocation()
  tapOption()

  guard end.x >= right.minX - 16 else {
    fputs(
      String(format: "FAIL: pointer did not cross into the adjacent display (x=%.1f, boundary=%.1f).\n", end.x, right.minX),
      stderr)
    return false
  }
  print("PASS: keyboard motion crossed the detected multi-display boundary.")
  return true
}

private func indicatorCenter() -> CGPoint? {
  guard
    let process = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.reinerlau.mouseless").first
  else { return nil }
  let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
  return windows?.compactMap { window in
    guard
      let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
      ownerPID == Int(process.processIdentifier),
      let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
      let x = bounds["X"], let y = bounds["Y"],
      let width = bounds["Width"], let height = bounds["Height"],
      width >= 8, width <= 32, height >= 8, height <= 32
    else { return nil }
    return CGPoint(x: x + width / 2, y: y + height / 2)
  }.first
}

private func displacement(for keys: [CGKeyCode], duration: TimeInterval = 0.35) -> Double {
  movePointerToTestOrigin()
  Thread.sleep(forTimeInterval: 0.1)
  let start = pointerLocation()
  for key in keys { postKey(key, isDown: true) }
  Thread.sleep(forTimeInterval: duration)
  for key in keys.reversed() { postKey(key, isDown: false) }
  Thread.sleep(forTimeInterval: 0.05)
  let end = pointerLocation()
  return end.x - start.x
}

func run() -> Int32 {
  print("Starting real-app motion smoke test; normalizing free mode state.")
  if indicatorCenter() != nil { tapOption() }
  guard verifyHorizontalMultiDisplayMotion() else { return 1 }
  tapOption()

  let pointer = pointerLocation()
  guard let indicator = indicatorCenter() else {
    fputs("FAIL: could not find the local app's visible indicator window.\n", stderr)
    tapOption()
    return 1
  }
  let indicatorDistance = hypot(indicator.x - pointer.x, indicator.y - pointer.y)
  guard indicatorDistance <= 32 else {
    fputs(
      String(format: "FAIL: indicator is %.1f pt from the pointer immediately after entering free mode.\n", indicatorDistance),
      stderr)
    tapOption()
    return 1
  }

  let base = displacement(for: [lKey])
  tapOption()
  tapOption()
  let precision = displacement(for: [aKey, lKey])
  tapOption()
  tapOption()
  let fast = displacement(for: [sKey, lKey])
  tapOption()
  tapOption()
  let fastest = displacement(for: [sKey, dKey, fKey, lKey])
  tapOption()

  print(String(format: "Measured rightward displacement: A=%.1f, base=%.1f, S=%.1f, S+D+F=%.1f pt", precision, base, fast, fastest))
  guard precision > 0, base > precision * 1.8, fast > base * 1.8, fastest > fast * 1.8 else {
    fputs("FAIL: motion layers did not produce the expected ordered displacement.\n", stderr)
    return 1
  }
  print("PASS: the running app exposes usable precision and fast movement layers.")
  return 0
}

exit(run())
