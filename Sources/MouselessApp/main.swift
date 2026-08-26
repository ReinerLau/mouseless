import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import MouselessRuntime
import OSLog
import QuartzCore

private let synthesizedEventMarker: Int64 = 0x4D4F_5553_4C45_5353
private let logger = Logger(subsystem: "com.reinerlau.mouseless", category: "runtime")

private final class SystemPermissionProvider {
  func current(prompt: Bool) -> PermissionState {
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    let accessibility = AXIsProcessTrustedWithOptions(options)
    let listen = CGPreflightListenEventAccess() || (prompt && CGRequestListenEventAccess())
    let post = CGPreflightPostEventAccess() || (prompt && CGRequestPostEventAccess())
    return PermissionState(accessibility: accessibility, listenEvent: listen, postEvent: post)
  }
}

private final class CoreGraphicsEffectExecutor {
  private let queue = DispatchQueue(label: "com.reinerlau.mouseless.effects")

  func submit(_ effects: [RuntimeEffect], completion: @escaping () -> Void = {}) {
    queue.async { [weak self] in
      guard let self else { return }
      for effect in effects { self.execute(effect) }
      completion()
    }
  }

  func releaseAllButtons(waitUntilPosted: Bool = false) {
    let effects = MouseButton.allCases.map { RuntimeEffect.mouseButton($0, .up) }
    if waitUntilPosted {
      queue.sync {
        for effect in effects { execute(effect) }
      }
    } else {
      submit(effects)
    }
  }

  func postProbe() -> Bool {
    queue.sync {
      guard
        let event = CGEvent(
          mouseEventSource: CGEventSource(stateID: .combinedSessionState), mouseType: .mouseMoved,
          mouseCursorPosition: CGEvent(source: nil)?.location ?? .zero, mouseButton: .left)
      else { return false }
      event.setIntegerValueField(.eventSourceUserData, value: synthesizedEventMarker)
      event.post(tap: .cghidEventTap)
      return true
    }
  }

  private func execute(_ effect: RuntimeEffect) {
    switch effect {
    case .pointerMoved(to: let point, let buttons):
      let cgPoint = CGPoint(x: point.x, y: point.y)
      if buttons.isEmpty {
        postMouse(type: .mouseMoved, point: cgPoint, button: .left)
      } else {
        for button in buttons.sorted(by: { $0.rawValue < $1.rawValue }) {
          postMouse(type: draggedType(for: button), point: cgPoint, button: cgButton(for: button))
        }
      }
    case .mouseButton(let button, let phase):
      let type: CGEventType
      switch (button, phase) {
      case (.left, .down): type = .leftMouseDown
      case (.left, .up): type = .leftMouseUp
      case (.right, .down): type = .rightMouseDown
      case (.right, .up): type = .rightMouseUp
      default: type = phase == .down ? .otherMouseDown : .otherMouseUp
      }
      postMouse(
        type: type, point: CGEvent(source: nil)?.location ?? .zero, button: cgButton(for: button))
    case .scroll(let pixelX, let pixelY):
      guard
        let event = CGEvent(
          scrollWheelEvent2Source: CGEventSource(stateID: .combinedSessionState), units: .pixel,
          wheelCount: 2, wheel1: Int32(pixelY), wheel2: Int32(pixelX), wheel3: 0)
      else { return }
      event.setIntegerValueField(.eventSourceUserData, value: synthesizedEventMarker)
      event.post(tap: .cghidEventTap)
    default: break
    }
  }

  private func postMouse(type: CGEventType, point: CGPoint, button: CGMouseButton) {
    guard
      let event = CGEvent(
        mouseEventSource: CGEventSource(stateID: .combinedSessionState), mouseType: type,
        mouseCursorPosition: point, mouseButton: button)
    else { return }
    event.setIntegerValueField(.eventSourceUserData, value: synthesizedEventMarker)
    event.post(tap: .cghidEventTap)
  }

  private func cgButton(for button: MouseButton) -> CGMouseButton {
    CGMouseButton(rawValue: UInt32(button.rawValue))!
  }
  private func draggedType(for button: MouseButton) -> CGEventType {
    switch button {
    case .left: return .leftMouseDragged
    case .right: return .rightMouseDragged
    default: return .otherMouseDragged
    }
  }
}

private final class EventTapHost {
  private var thread: Thread?
  private var runLoop: CFRunLoop?
  private var tap: CFMachPort?
  private var stopped = false
  private let finished = DispatchSemaphore(value: 0)
  private let callback: (CGEventType, CGEvent) -> Unmanaged<CGEvent>?

  init(callback: @escaping (CGEventType, CGEvent) -> Unmanaged<CGEvent>?) {
    self.callback = callback
  }

  func start() -> Bool {
    let ready = DispatchSemaphore(value: 0)
    var created = false
    thread = Thread { [weak self] in
      guard let self else {
        ready.signal()
        return
      }
      let mask =
        (CGEventMask(1) << CGEventType.keyDown.rawValue)
        | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        | (CGEventMask(1) << CGEventType.mouseMoved.rawValue)
        | (CGEventMask(1) << CGEventType.leftMouseDragged.rawValue)
        | (CGEventMask(1) << CGEventType.rightMouseDragged.rawValue)
        | (CGEventMask(1) << CGEventType.otherMouseDragged.rawValue)
      guard
        let tap = CGEvent.tapCreate(
          tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
          eventsOfInterest: mask, callback: eventTapCallback,
          userInfo: Unmanaged.passUnretained(self).toOpaque()),
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
      else {
        self.finished.signal()
        ready.signal()
        return
      }
      self.tap = tap
      self.runLoop = CFRunLoopGetCurrent()
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)
      created = true
      ready.signal()
      CFRunLoopRun()
      CGEvent.tapEnable(tap: tap, enable: false)
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
      self.finished.signal()
    }
    thread?.qualityOfService = .userInteractive
    thread?.start()
    ready.wait()
    return created
  }

  func stop() {
    guard !stopped else { return }
    stopped = true
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    if let runLoop {
      CFRunLoopStop(runLoop)
      CFRunLoopWakeUp(runLoop)
    }
    finished.wait()
    tap = nil
    runLoop = nil
  }

  func reenable() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }

  fileprivate func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { reenable() }
    return callback(type, event)
  }
}

private func eventTapCallback(
  proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  return Unmanaged<EventTapHost>.fromOpaque(userInfo).takeUnretainedValue().receive(
    type: type, event: event)
}

private final class IndicatorController {
  private final class IndicatorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
      NSColor.systemBlue.withAlphaComponent(0.9).setFill()
      NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).fill()
    }
  }
  private var window: NSPanel?
  private var size = 16.0

  func show(size: Double) {
    self.size = size * 2
    if window == nil {
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: self.size, height: self.size),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.level = .statusBar
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.ignoresMouseEvents = true
      panel.hidesOnDeactivate = false
      panel.contentView = IndicatorView(frame: panel.contentRect(forFrameRect: panel.frame))
      window = panel
    }
    window?.setContentSize(NSSize(width: size * 2, height: size * 2))
    window?.orderFrontRegardless()
  }

  func hide() { window?.orderOut(nil) }
  func move(to point: Point) {
    window?.setFrameOrigin(NSPoint(x: point.x - size / 2, y: point.y - size / 2))
  }
}

private final class MouselessApplicationController: NSObject {
  private let permissions = SystemPermissionProvider()
  private let executor = CoreGraphicsEffectExecutor()
  private let indicator = IndicatorController()
  private let runtime = MouselessRuntime()
  private let runtimeLock = NSLock()
  private var eventTap: EventTapHost?
  private var displayLink: CADisplayLink?
  private var statusItem: NSStatusItem?
  private var statusMenuItem: NSMenuItem?
  private var modeMenuItem: NSMenuItem?
  private var reloadMenuItem: NSMenuItem?
  private var configurationValid = true
  private var recoveryCount = 0
  private var lastFrameTime: TimeInterval?
  private var workspaceObservers: [NSObjectProtocol] = []
  private var permissionCheckTime = 0.0

  func start() {
    executor.releaseAllButtons(waitUntilPosted: true)
    configureMenu()
    reloadConfiguration(createIfMissing: true)
    apply(runtimeResponse(for: .topologyChanged(currentTopology())))
    registerLifecycleObservers()
    checkPermissions(prompt: true)
    displayLink = NSScreen.main?.displayLink(target: self, selector: #selector(frame(_:)))
    displayLink?.add(to: .main, forMode: .common)
  }

  func stop() {
    displayLink?.invalidate()
    displayLink = nil
    eventTap?.stop()
    eventTap = nil
    for observer in workspaceObservers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    workspaceObservers.removeAll()
    apply(runtimeResponse(for: .shutdown))
    executor.releaseAllButtons(waitUntilPosted: true)
  }

  private func configureMenu() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "Mouseless"
    let menu = NSMenu()
    let status = NSMenuItem(title: "Permissions: checking…", action: nil, keyEquivalent: "")
    status.isEnabled = false
    menu.addItem(status)
    statusMenuItem = status
    let mode = NSMenuItem(title: "Free mode: Off", action: nil, keyEquivalent: "")
    mode.isEnabled = false
    menu.addItem(mode)
    modeMenuItem = mode
    menu.addItem(.separator())
    menu.addItem(menuItem("Request Permissions", #selector(requestPermissions)))
    menu.addItem(menuItem("Open System Settings", #selector(openSystemSettings)))
    menu.addItem(menuItem("Recheck Permissions", #selector(recheckPermissions)))
    let reload = menuItem("Reload Configuration", #selector(reloadConfigurationFromMenu))
    menu.addItem(reload)
    reloadMenuItem = reload
    menu.addItem(menuItem("Copy Diagnostic Summary", #selector(copyDiagnostics)))
    menu.addItem(.separator())
    menu.addItem(menuItem("Quit Mouseless", #selector(quit)))
    item.menu = menu
    statusItem = item
  }

  private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  private func checkPermissions(prompt: Bool) {
    let state = permissions.current(prompt: prompt)
    var effectiveState = state
    var systemPathIsReady = false
    if state.isReady {
      if eventTap == nil {
        let host = EventTapHost { [weak self] type, event in
          self?.handleTapEvent(type: type, event: event) ?? Unmanaged.passUnretained(event)
        }
        if host.start() { eventTap = host }
      }
      systemPathIsReady = eventTap != nil && executor.postProbe()
      if !systemPathIsReady { effectiveState.postEvent = false }
    } else {
      eventTap?.stop()
      eventTap = nil
    }
    apply(runtimeResponse(for: .permissionsChanged(effectiveState)))
    if systemPathIsReady {
      updateStatus(state: state, message: "Ready")
    } else if state.isReady {
      updateStatus(state: state, message: "Permissions granted; event tap unavailable")
    } else {
      updateStatus(state: state, message: "Missing: \(missingPermissions(state))")
    }
  }

  private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if event.getIntegerValueField(.eventSourceUserData) == synthesizedEventMarker {
      return Unmanaged.passUnretained(event)
    }
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      apply(runtimeResponse(for: .eventTapDisabled))
      return Unmanaged.passUnretained(event)
    }
    let response: RuntimeResponse
    switch type {
    case .keyDown, .keyUp:
      let key = key(for: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)))
      let timestamp = Double(event.timestamp) / 1_000_000_000
      response = runtimeResponse(
        for: type == .keyDown
          ? .keyDown(
            key, at: timestamp,
            isAutoRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
          : .keyUp(key, at: timestamp))
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
      response = runtimeResponse(
        for: .pointerMoved(to: Point(x: event.location.x, y: event.location.y)))
    default: response = RuntimeResponse(disposition: .passThrough)
    }
    apply(response)
    return response.disposition == .consume ? nil : Unmanaged.passUnretained(event)
  }

  private func runtimeResponse(for event: RuntimeEvent) -> RuntimeResponse {
    runtimeLock.lock()
    defer { runtimeLock.unlock() }
    return runtime.handle(event)
  }

  private func registerLifecycleObservers() {
    let center = NSWorkspace.shared.notificationCenter
    let names: [(Notification.Name, SessionState)] = [
      (NSWorkspace.willSleepNotification, .sleeping),
      (NSWorkspace.sessionDidResignActiveNotification, .inactive),
      (NSWorkspace.didWakeNotification, .waking),
      (NSWorkspace.sessionDidBecomeActiveNotification, .active),
    ]
    workspaceObservers = names.map { name, state in
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        guard let self else { return }
        self.apply(self.runtimeResponse(for: .sessionChanged(state)))
        if state == .active { self.checkPermissions(prompt: false) }
      }
    }
    workspaceObservers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        self.apply(self.runtimeResponse(for: .topologyChanged(self.currentTopology())))
      })
  }

  private func currentTopology() -> DisplayTopology {
    DisplayTopology(
      regions: NSScreen.screens.map { screen in
        DisplayRegion(
          x: screen.frame.origin.x, y: screen.frame.origin.y, width: screen.frame.width,
          height: screen.frame.height)
      })
  }

  private func apply(_ response: RuntimeResponse) {
    let uiEffects = response.effects.filter { effect in
      switch effect {
      case .capabilitiesChanged, .modeChanged, .indicator, .pointerMoved, .configurationAccepted,
        .configurationRejected, .eventTapShouldBeReenabled:
        return true
      default: return false
      }
    }
    if Thread.isMainThread {
      applyUI(uiEffects)
    } else {
      DispatchQueue.main.async { [weak self] in self?.applyUI(uiEffects) }
    }

    let executable = response.effects.filter { effect in
      switch effect {
      case .pointerMoved, .mouseButton, .scroll: return true
      default: return false
      }
    }
    if !executable.isEmpty { executor.submit(executable) }
  }

  private func applyUI(_ effects: [RuntimeEffect]) {
    for effect in effects {
      switch effect {
      case .capabilitiesChanged(let state):
        updateStatus(state: state, message: state.isReady ? "Ready" : "Permissions required")
        logger.notice(
          "Capabilities changed: accessibility=\(state.accessibility), listenEvent=\(state.listenEvent), postEvent=\(state.postEvent)"
        )
      case .modeChanged(let isEnabled):
        modeMenuItem?.title = "Free mode: \(isEnabled ? "On" : "Off")"
        logger.info("Free mode changed: enabled=\(isEnabled)")
      case .indicator(let isVisible): isVisible ? indicator.show(size: 8) : indicator.hide()
      case .pointerMoved(to: let point, buttons: _): indicator.move(to: point)
      case .configurationAccepted:
        configurationValid = true
        reloadMenuItem?.title = "Reload Configuration"
        logger.info("Configuration accepted")
      case .configurationRejected:
        configurationValid = false
        reloadMenuItem?.title = "Reload Configuration (invalid)"
        logger.error("Configuration rejected")
      case .eventTapShouldBeReenabled:
        recoveryCount += 1
        eventTap?.reenable()
        logger.warning("Event tap re-enabled after disable")
      default: break
      }
    }
  }

  @objc private func frame(_ link: CADisplayLink) {
    let delta = min(max(link.timestamp - (lastFrameTime ?? link.timestamp), 0), 0.25)
    lastFrameTime = link.timestamp
    apply(runtimeResponse(for: .frame(deltaTime: delta)))
    permissionCheckTime += delta
    if permissionCheckTime >= 0.5 {
      permissionCheckTime = 0
      checkPermissions(prompt: false)
    }
  }

  @objc private func requestPermissions() { checkPermissions(prompt: true) }
  @objc private func recheckPermissions() { checkPermissions(prompt: false) }
  @objc private func reloadConfigurationFromMenu() { reloadConfiguration(createIfMissing: false) }

  private func reloadConfiguration(createIfMissing: Bool) {
    let url = configurationURL()
    do {
      if !FileManager.default.fileExists(atPath: url.path), createIfMissing {
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RuntimeConfiguration.defaultJSON.write(to: url, options: .atomic)
      }
      apply(runtimeResponse(for: .configuration(try Data(contentsOf: url))))
    } catch {
      configurationValid = false
      reloadMenuItem?.title = "Reload Configuration (unreadable)"
    }
  }

  private func configurationURL() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Mouseless", isDirectory: true).appendingPathComponent("config.json")
  }

  @objc private func openSystemSettings() {
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
  }

  @objc private func copyDiagnostics() {
    let state = permissions.current(prompt: false)
    let summary =
      "Mouseless\npermissions: accessibility=\(state.accessibility), listenEvent=\(state.listenEvent), postEvent=\(state.postEvent)\nconfigurationValid: \(configurationValid)\neventTapRecoveries: \(recoveryCount)"
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(summary, forType: .string)
  }

  @objc private func quit() { NSApp.terminate(nil) }

  private func updateStatus(state: PermissionState, message: String) {
    statusMenuItem?.title = "Permissions: \(message)"
    statusItem?.button?.title = state.isReady ? "Mouseless ✓" : "Mouseless !"
  }

  private func missingPermissions(_ state: PermissionState) -> String {
    var missing: [String] = []
    if !state.accessibility { missing.append("Accessibility") }
    if !state.listenEvent { missing.append("Listen Event") }
    if !state.postEvent { missing.append("Post Event") }
    return missing.joined(separator: ", ")
  }

  private func key(for code: CGKeyCode) -> Key {
    switch code {
    case CGKeyCode(kVK_Option): return .leftOption
    case CGKeyCode(kVK_RightOption): return .rightOption
    case CGKeyCode(kVK_Escape): return .escape
    case CGKeyCode(kVK_ANSI_I): return .i
    case CGKeyCode(kVK_ANSI_J): return .j
    case CGKeyCode(kVK_ANSI_K): return .k
    case CGKeyCode(kVK_ANSI_L): return .l
    case CGKeyCode(kVK_Space): return .space
    case CGKeyCode(kVK_ANSI_R): return .r
    case CGKeyCode(kVK_ANSI_E): return .e
    case CGKeyCode(kVK_ANSI_Q): return .q
    case CGKeyCode(kVK_ANSI_W): return .w
    case CGKeyCode(kVK_ANSI_M): return .m
    case CGKeyCode(kVK_ANSI_Comma): return .comma
    case CGKeyCode(kVK_ANSI_Period): return .period
    case CGKeyCode(kVK_ANSI_Slash): return .slash
    case CGKeyCode(kVK_ANSI_A): return .a
    case CGKeyCode(kVK_ANSI_S): return .s
    case CGKeyCode(kVK_ANSI_D): return .d
    case CGKeyCode(kVK_ANSI_F): return .f
    default: return .other(Int(code))
    }
  }
}

@main
struct MouselessAppMain {
  static func main() {
    let application = NSApplication.shared
    let controller = MouselessApplicationController()
    let delegate = AppDelegate(controller: controller)
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
    withExtendedLifetime(controller) {}
  }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
  let controller: MouselessApplicationController
  init(controller: MouselessApplicationController) { self.controller = controller }
  func applicationDidFinishLaunching(_ notification: Notification) { controller.start() }
  func applicationWillTerminate(_ notification: Notification) { controller.stop() }
}
