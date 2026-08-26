import CoreGraphics
import Foundation

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

private func displacement(for keys: [CGKeyCode], duration: TimeInterval = 0.35) -> Double {
  CGWarpMouseCursorPosition(CGPoint(x: 100, y: 100))
  Thread.sleep(forTimeInterval: 0.1)
  let start = pointerLocation()
  for key in keys { postKey(key, isDown: true) }
  Thread.sleep(forTimeInterval: duration)
  for key in keys.reversed() { postKey(key, isDown: false) }
  Thread.sleep(forTimeInterval: 0.05)
  return pointerLocation().x - start.x
}

func run() -> Int32 {
  print("Starting real-app motion smoke test; free mode must initially be Off.")
  tapOption()

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
