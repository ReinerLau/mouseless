import CoreGraphics
import Foundation

private let optionKey: CGKeyCode = 58
private let rightMovementKey: CGKeyCode = 37
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

private func movePointerToCenter() {
  let bounds = CGDisplayBounds(CGMainDisplayID())
  guard
    let event = CGEvent(
      mouseEventSource: eventSource, mouseType: .mouseMoved,
      mouseCursorPosition: CGPoint(x: bounds.midX, y: bounds.midY), mouseButton: .left)
  else { fatalError("Could not create pointer event") }
  event.post(tap: .cghidEventTap)
}

private func pointerLocation() -> CGPoint {
  guard let location = CGEvent(source: nil)?.location else {
    fatalError("Could not read pointer location")
  }
  return location
}

if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "cleanup" {
  postKey(rightMovementKey, isDown: false)
  postKey(optionKey, isDown: true)
  postKey(optionKey, isDown: false)
  exit(0)
}

guard CommandLine.arguments.count == 2, let duration = Double(CommandLine.arguments[1]), duration > 0
else {
  fputs("usage: performance-smoke-test <seconds>\n", stderr)
  exit(2)
}

movePointerToCenter()
Thread.sleep(forTimeInterval: 0.1)
let start = pointerLocation()
tapOption()
postKey(rightMovementKey, isDown: true)
Thread.sleep(forTimeInterval: duration)
postKey(rightMovementKey, isDown: false)
Thread.sleep(forTimeInterval: 0.1)
let end = pointerLocation()
postKey(optionKey, isDown: true)
postKey(optionKey, isDown: false)

guard end.x > start.x + 10 else {
  fputs("Mouseless did not produce measurable rightward movement.\n", stderr)
  exit(1)
}
