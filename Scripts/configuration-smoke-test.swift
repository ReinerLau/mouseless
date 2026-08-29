import Foundation
import CoreGraphics

private let eventSource = CGEventSource(stateID: .combinedSessionState)
private let optionKey: CGKeyCode = 58
private let rightMovementKey: CGKeyCode = 37

private let fileManager = FileManager.default
private let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
private let configurationURL = applicationSupport
  .appendingPathComponent("Keyveer", isDirectory: true)
  .appendingPathComponent("config.json")

private func ask(_ message: String) -> Bool {
  print(message + " [y/N]", terminator: " ")
  return readLine()?.lowercased() == "y"
}

private func waitForConfiguration() -> Bool {
  for _ in 0..<20 {
    if fileManager.fileExists(atPath: configurationURL.path) { return true }
    Thread.sleep(forTimeInterval: 0.25)
  }
  return false
}

private func readObject() throws -> [String: Any] {
  let data = try Data(contentsOf: configurationURL)
  guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    throw NSError(domain: "KeyveerConfigurationSmoke", code: 1, userInfo: [
      NSLocalizedDescriptionKey: "configuration root is not a JSON object"
    ])
  }
  return object
}

private func writeObject(_ object: [String: Any]) throws {
  let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
  try data.write(to: configurationURL, options: .atomic)
}

private func postKey(_ key: CGKeyCode, isDown: Bool) {
  guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: key, keyDown: isDown)
  else { return }
  event.post(tap: .cghidEventTap)
}

private func tapOption() {
  postKey(optionKey, isDown: true)
  Thread.sleep(forTimeInterval: 0.05)
  postKey(optionKey, isDown: false)
  Thread.sleep(forTimeInterval: 0.1)
}

private func pointerLocation() -> CGPoint {
  CGEvent(source: nil)?.location ?? .zero
}

private func movePointerToMainDisplayCenter() {
  let bounds = CGDisplayBounds(CGMainDisplayID())
  guard
    let event = CGEvent(
      mouseEventSource: eventSource, mouseType: .mouseMoved,
      mouseCursorPosition: CGPoint(x: bounds.midX, y: bounds.midY), mouseButton: .left)
  else { return }
  event.post(tap: .cghidEventTap)
}

private func verifyReloadedMovementSpeed() -> Bool {
  movePointerToMainDisplayCenter()
  Thread.sleep(forTimeInterval: 0.1)
  let start = pointerLocation()
  tapOption()
  postKey(rightMovementKey, isDown: true)
  Thread.sleep(forTimeInterval: 0.25)
  postKey(rightMovementKey, isDown: false)
  Thread.sleep(forTimeInterval: 0.05)
  let end = pointerLocation()
  tapOption()
  let displacement = end.x - start.x
  let passed = displacement > 80 && displacement < 135
  if passed {
    print(String(format: "PASS: reloaded movement speed produced %.1f points.", displacement))
  } else {
    print(String(format: "FAIL: expected reloaded 600 pt/s movement, observed %.1f points.", displacement))
  }
  return passed
}

func run() -> Int32 {
  guard ask("Quit Keyveer first, then continue to test first-launch generation.") else {
    print("Aborted.")
    return 1
  }

  let backupURL = fileManager.temporaryDirectory
    .appendingPathComponent("keyveer-config-smoke-\(UUID().uuidString).json")
  let hadOriginal = fileManager.fileExists(atPath: configurationURL.path)
  do {
    if hadOriginal { try fileManager.moveItem(at: configurationURL, to: backupURL) }
    defer {
      try? fileManager.removeItem(at: configurationURL)
      if hadOriginal { try? fileManager.moveItem(at: backupURL, to: configurationURL) }
      else { try? fileManager.removeItem(at: backupURL) }
    }

    guard CommandLine.arguments.count > 1 else {
      print("Run this test through configuration-smoke-test.sh with the app path.")
      return 1
    }
    let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let launch = Process()
    launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    launch.arguments = [appURL.path]
    try launch.run()
    launch.waitUntilExit()
    guard launch.terminationStatus == 0 else {
      print("FAIL: could not launch Keyveer.")
      return 1
    }
    guard waitForConfiguration() else {
      print("FAIL: Keyveer did not generate its Application Support configuration.")
      return 1
    }
    let generated = try readObject()
    guard let schemaVersion = generated["schemaVersion"] as? Int, schemaVersion == 2 else {
      print("FAIL: generated configuration has no schemaVersion 2.")
      return 1
    }
    print("PASS: first launch generated config.json with schemaVersion 2.")
    Thread.sleep(forTimeInterval: 1)

    var valid = generated
    var movement = valid["movement"] as? [String: Any] ?? [:]
    movement["baseSpeed"] = 600.0
    valid["movement"] = movement
    try writeObject(valid)
    guard ask("Select Keyveer > Reload Configuration, then confirm it shows no error and the app remains usable.") else {
      print("FAIL: valid configuration reload was not confirmed.")
      return 1
    }
    guard verifyReloadedMovementSpeed() else { return 1 }

    var invalid = valid
    invalid["unexpected"] = true
    try writeObject(invalid)
    guard ask("Select Reload Configuration again, then confirm the menu shows an error and the previous behavior remains active.") else {
      print("FAIL: invalid configuration fallback was not confirmed.")
      return 1
    }
    guard verifyReloadedMovementSpeed() else { return 1 }
    print("PASS: invalid reload preserved the previous valid behavior.")
    print("The original configuration was restored. Reload once more, or restart Keyveer, to leave the app on it.")
    return 0
  } catch {
    print("FAIL: \(error.localizedDescription)")
    return 1
  }
}

exit(run())
