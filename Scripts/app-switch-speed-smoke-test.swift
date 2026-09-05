import AppKit
import CoreGraphics
import Foundation

private let leftOption: CGKeyCode = 58
private let a: CGKeyCode = 0
private let l: CGKeyCode = 37
private let eventSource = CGEventSource(stateID: .hidSystemState)
private var postedFlags: CGEventFlags = []

private func postKey(_ key: CGKeyCode, isDown: Bool) {
  if key == leftOption {
    if isDown { postedFlags.insert(.maskAlternate) } else { postedFlags.remove(.maskAlternate) }
  }
  guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: isDown)
  else { fatalError("Could not create keyboard event") }
  event.flags = postedFlags
  event.post(tap: .cghidEventTap)
}

private func tap(_ key: CGKeyCode) {
  postKey(key, isDown: true)
  Thread.sleep(forTimeInterval: 0.05)
  postKey(key, isDown: false)
  Thread.sleep(forTimeInterval: 0.05)
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
  Thread.sleep(forTimeInterval: 0.1)
}

private func displacement(duration: TimeInterval = 0.35) -> Double {
  movePointerToTestOrigin()
  let start = pointerLocation()
  postKey(l, isDown: true)
  Thread.sleep(forTimeInterval: duration)
  postKey(l, isDown: false)
  Thread.sleep(forTimeInterval: 0.2)
  return pointerLocation().x - start.x
}

private func switchApplication() -> Bool {
  let before = NSWorkspace.shared.frontmostApplication?.processIdentifier
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
  process.arguments = [
    "-e",
    "tell application \"System Events\" to key down command",
    "-e",
    "delay 0.01",
    "-e",
    "tell application \"System Events\" to key code 48",
    "-e",
    "delay 0.01",
    "-e",
    "tell application \"System Events\" to key up command",
  ]
  do {
    try process.run()
    process.waitUntilExit()
  } catch {
    return false
  }
  Thread.sleep(forTimeInterval: 0.2)
  return NSWorkspace.shared.frontmostApplication?.processIdentifier != before
}

private func run() -> Int32 {
  guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.reinerlau.keyveer").count == 1
  else {
    fputs("ERROR: run exactly one built Keyveer app before this smoke test.\n", stderr)
    return 2
  }

  print("Starting app-switch speed smoke test; assuming free mode is off.")
  tap(leftOption)
  defer { tap(leftOption) }

  let activationProbe = displacement(duration: 0.15)
  guard activationProbe > 5 else {
    fputs("ERROR: free mode did not produce pointer motion after activation.\n", stderr)
    return 2
  }

  let baseline = displacement()
  guard switchApplication() else {
    fputs("ERROR: Command-Tab did not change the frontmost application.\n", stderr)
    return 2
  }
  let afterSwitch = displacement()
  tap(a)
  let afterA = displacement()

  print(
    String(
      format: "Measured rightward displacement: baseline=%.1f, after-switch=%.1f, after-A=%.1f pt",
      baseline, afterSwitch, afterA))
  guard baseline > 0, afterSwitch >= baseline * 0.75 else {
    fputs("FAIL: Command-Tab reduced free-mode default pointer speed.\n", stderr)
    return 1
  }
  print("PASS: Command-Tab preserved free-mode default pointer speed.")
  return 0
}

exit(run())
