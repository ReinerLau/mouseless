import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import MouselessRuntime
import OSLog
import QuartzCore

private let synthesizedEventMarker: Int64 = 0x4D4F_5553_4C45_5353
private let logger = Logger(subsystem: "com.reinerlau.mouseless", category: "runtime")

private func primaryScreenTop() -> CGFloat {
  CGDisplayBounds(CGMainDisplayID()).maxY
}

private func cocoaPoint(fromQuartz point: CGPoint) -> Point {
  Point(x: point.x, y: primaryScreenTop() - point.y)
}

private func quartzPoint(fromRuntime point: Point) -> CGPoint {
  CGPoint(x: point.x, y: point.y)
}

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

private final class DiagnosticCollector {
  private let lock = NSLock()
  private var counters = DiagnosticCounters()

  func recordCallback(duration: TimeInterval) -> Int? {
    lock.lock()
    defer { lock.unlock() }
    return counters.recordCallback(duration: duration)
  }

  func recordFrame() {
    lock.lock()
    counters.recordFrame()
    lock.unlock()
  }

  func record(_ response: RuntimeResponse) {
    lock.lock()
    counters.record(response.effects)
    lock.unlock()
  }

  func recordConfigurationReadFailure() {
    lock.lock()
    counters.configurationRejectedCount += 1
    lock.unlock()
  }

  func snapshot() -> DiagnosticCounters {
    lock.lock()
    defer { lock.unlock() }
    return counters
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
      if buttons.isEmpty {
        postMouse(type: .mouseMoved, point: quartzPoint(fromRuntime: point), button: .left)
      } else {
        for button in buttons.sorted(by: { $0.rawValue < $1.rawValue }) {
          postMouse(
            type: draggedType(for: button), point: quartzPoint(fromRuntime: point),
            button: cgButton(for: button))
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
  private let stateLock = NSLock()
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
        | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        | (CGEventMask(1) << CGEventType.mouseMoved.rawValue)
        | (CGEventMask(1) << CGEventType.leftMouseDragged.rawValue)
        | (CGEventMask(1) << CGEventType.rightMouseDragged.rawValue)
        | (CGEventMask(1) << CGEventType.otherMouseDragged.rawValue)
      guard
        let tap = CGEvent.tapCreate(
          tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
          eventsOfInterest: mask, callback: eventTapCallback,
          userInfo: Unmanaged.passUnretained(self).toOpaque()),
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
      else {
        self.finished.signal()
        ready.signal()
        return
      }
      self.stateLock.lock()
      self.tap = tap
      self.runLoop = CFRunLoopGetCurrent()
      self.stateLock.unlock()
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
    stateLock.lock()
    guard !stopped else {
      stateLock.unlock()
      return
    }
    stopped = true
    let tap = self.tap
    let runLoop = self.runLoop
    stateLock.unlock()
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    if let runLoop {
      CFRunLoopStop(runLoop)
      CFRunLoopWakeUp(runLoop)
    }
    finished.wait()
    stateLock.lock()
    self.tap = nil
    self.runLoop = nil
    stateLock.unlock()
  }

  func reenable() -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard let tap, !stopped else { return false }
    CGEvent.tapEnable(tap: tap, enable: true)
    return CGEvent.tapIsEnabled(tap: tap)
  }

  fileprivate func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
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
  private var diameter = 16.0
  private var lastPoint: Point?

  func show() {
    if window == nil {
      let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: diameter, height: diameter),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.level = .statusBar
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.ignoresMouseEvents = true
      panel.hidesOnDeactivate = false
      panel.contentView = IndicatorView(frame: panel.contentRect(forFrameRect: panel.frame))
      window = panel
    }
    window?.orderFrontRegardless()
    if let lastPoint { move(to: lastPoint) }
  }

  func setSize(_ radius: Double) {
    diameter = radius * 2
    window?.setContentSize(NSSize(width: diameter, height: diameter))
  }

  func hide() { window?.orderOut(nil) }
  func move(to point: Point) {
    lastPoint = point
    guard window != nil else { return }
    let cocoa = cocoaPoint(fromQuartz: CGPoint(x: point.x, y: point.y))
    window?.setFrameOrigin(NSPoint(x: cocoa.x - diameter / 2, y: cocoa.y - diameter / 2))
  }
}

private final class MouselessApplicationController: NSObject {
  private let permissions = SystemPermissionProvider()
  private let executor = CoreGraphicsEffectExecutor()
  private let indicator = IndicatorController()
  private let diagnostics = DiagnosticCollector()
  private let runtime = MouselessRuntime()
  private let runtimeLock = NSLock()
  private var eventTap: EventTapHost?
  private let eventTapLock = NSLock()
  private var displayLink: CADisplayLink?
  private var statusItem: NSStatusItem?
  private var reloadMenuItem: NSMenuItem?
  private var configurationValid = true
  private var configurationError: String?
  private var eventTapStatus: DiagnosticEventTapStatus = .unknown
  private var lastFrameTime: TimeInterval?
  private var workspaceObservers: [NSObjectProtocol] = []
  private var distributedObservers: [NSObjectProtocol] = []
  private var applicationObservers: [NSObjectProtocol] = []
  private var lastPermissionState: PermissionState?
  private var lastKnownTopology = DisplayTopology.unrestricted
  private var keyboardModifiers: KeyboardModifiers = []

  private func currentEventTap() -> EventTapHost? {
    eventTapLock.lock()
    defer { eventTapLock.unlock() }
    return eventTap
  }

  private func setEventTap(_ host: EventTapHost?) {
    eventTapLock.lock()
    eventTap = host
    eventTapLock.unlock()
  }

  private func takeEventTap() -> EventTapHost? {
    eventTapLock.lock()
    let host = eventTap
    eventTap = nil
    eventTapLock.unlock()
    return host
  }

  func start() {
    logger.notice("Application started")
    executor.releaseAllButtons(waitUntilPosted: true)
    configureMenu()
    reloadConfiguration(createIfMissing: true)
    apply(runtimeResponse(for: .topologyChanged(currentTopology())))
    let initialPointer = CGEvent(source: nil)?.location ?? .zero
    apply(runtimeResponse(for: .pointerMoved(to: Point(x: initialPointer.x, y: initialPointer.y))))
    registerLifecycleObservers()
    checkPermissions(prompt: true)
    displayLink = NSScreen.main?.displayLink(target: self, selector: #selector(frame(_:)))
    displayLink?.add(to: .main, forMode: .common)
  }

  func stop() {
    logger.notice("Application stopping")
    displayLink?.invalidate()
    displayLink = nil
    takeEventTap()?.stop()
    for observer in workspaceObservers {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    workspaceObservers.removeAll()
    let distributedCenter = DistributedNotificationCenter.default()
    for observer in distributedObservers { distributedCenter.removeObserver(observer) }
    distributedObservers.removeAll()
    for observer in applicationObservers { NotificationCenter.default.removeObserver(observer) }
    applicationObservers.removeAll()
    apply(runtimeResponse(for: .shutdown))
    executor.releaseAllButtons(waitUntilPosted: true)
  }

  private func configureMenu() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem = item
    updateStatus(runtime.freeModeStatus)
    let menu = NSMenu()
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
  }

  private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  private func checkPermissions(prompt: Bool) {
    let state = permissions.current(prompt: prompt)
    lastPermissionState = state
    reconcilePermissions(state, clearEventTapFailure: true)
  }

  private func pollPermissions() {
    let state = permissions.current(prompt: false)
    guard state != lastPermissionState || currentEventTap() == nil else { return }
    lastPermissionState = state
    reconcilePermissions(state)
  }

  private func reconcilePermissions(_ state: PermissionState, clearEventTapFailure: Bool = false) {
    var effectiveState = state
    var systemPathIsReady = false
    var startedEventTap = false
    if state.isReady {
      if currentEventTap() == nil {
        let host = EventTapHost { [weak self] type, event in
          self?.handleTapEvent(type: type, event: event) ?? Unmanaged.passUnretained(event)
        }
        if host.start() {
          setEventTap(host)
          startedEventTap = true
        }
      }
      systemPathIsReady = currentEventTap() != nil && executor.postProbe()
      if !systemPathIsReady { effectiveState.postEvent = false }
    } else {
      takeEventTap()?.stop()
    }
    if state.isReady && systemPathIsReady {
      if clearEventTapFailure || eventTapStatus != .recoveryFailed {
        eventTapStatus = .healthy
      }
    } else if !state.isReady || eventTapStatus != .recoveryFailed {
      eventTapStatus = .unavailable
    }
    apply(runtimeResponse(for: .permissionsChanged(effectiveState)))
    if systemPathIsReady {
      updateStatus(
        state: state,
        message: eventTapStatus == .recoveryFailed ? "Event tap recovery failed" : "Ready")
    } else if state.isReady {
      updateStatus(state: state, message: "Permissions granted; event tap unavailable")
    } else {
      updateStatus(state: state, message: "Missing: \(missingPermissions(state))")
    }
  }

  private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    let callbackStarted = CACurrentMediaTime()
    defer { _ = diagnostics.recordCallback(duration: CACurrentMediaTime() - callbackStarted) }
    if event.getIntegerValueField(.eventSourceUserData) == synthesizedEventMarker {
      return Unmanaged.passUnretained(event)
    }
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      keyboardModifiers = []
      let response = runtimeResponse(for: .eventTapDisabled)
      enqueue(response)
      guard response.effects.contains(.eventTapShouldBeReenabled) else {
        return Unmanaged.passUnretained(event)
      }
      let host = currentEventTap()
      let recovered = host?.reenable() ?? false
      enqueue(runtimeResponse(for: recovered ? .eventTapReenabled : .eventTapRecoveryFailed))
      if !recovered {
        // EventTapHost.stop waits for its run-loop thread, so stop the failed host after this
        // callback returns instead of blocking the tap callback itself.
        DispatchQueue.main.async { [weak self, weak host] in
          host?.stop()
          if let self, self.currentEventTap() === host { _ = self.takeEventTap() }
        }
      }
      return Unmanaged.passUnretained(event)
    }
    let response: RuntimeResponse
    switch type {
    case .keyDown, .keyUp:
      let key = key(for: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)))
      let timestamp = Double(event.timestamp) / 1_000_000_000
      response = runtimeResponse(for: .keyboard(
        KeyboardEvent(
          key: key,
          phase: type == .keyDown ? .down : .up,
          timestamp: timestamp,
          isAutoRepeat: type == .keyDown
            && event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
          modifiers: modifierState(for: event))))
    case .flagsChanged:
      let key = key(for: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)))
      let timestamp = Double(event.timestamp) / 1_000_000_000
      let modifiers = modifierState(for: event, key: key)
      response = runtimeResponse(for: .keyboard(
        KeyboardEvent(
          key: key,
          phase: modifierPhase(for: key, modifiers: modifiers),
          timestamp: timestamp,
          isAutoRepeat: false,
          modifiers: modifiers)))
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
      response = runtimeResponse(
        for: .pointerMoved(to: Point(x: event.location.x, y: event.location.y)))
    default: response = RuntimeResponse(disposition: .passThrough)
    }
    enqueue(response)
    if response.disposition == .consume {
      // Returning nil did not suppress keyboard delivery on macOS 26; a null event preserves
      // active-filter semantics while preventing AppKit and input methods from producing text.
      event.type = .null
    }
    return Unmanaged.passUnretained(event)
  }

  private func runtimeResponse(for event: RuntimeEvent) -> RuntimeResponse {
    runtimeLock.lock()
    defer { runtimeLock.unlock() }
    return runtime.handle(event)
  }

  private func enqueue(_ response: RuntimeResponse) {
    DispatchQueue.main.async { [weak self] in self?.apply(response) }
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
        logger.notice("Session changed: \(self.sessionLabel(state))")
        self.apply(self.runtimeResponse(for: .sessionChanged(state)))
        if state == .active { self.checkPermissions(prompt: false) }
      }
    }
    applicationObservers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        self.apply(self.runtimeResponse(for: .topologyChanged(self.currentTopology())))
      })
    let distributedCenter = DistributedNotificationCenter.default()
    distributedObservers.append(
      distributedCenter.addObserver(
        forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        self.apply(self.runtimeResponse(for: .sessionChanged(.locked)))
      })
    distributedObservers.append(
      distributedCenter.addObserver(
        forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
      ) { [weak self] _ in
        guard let self else { return }
        self.apply(self.runtimeResponse(for: .sessionChanged(.active)))
        self.checkPermissions(prompt: false)
      })
  }

  private func currentTopology() -> DisplayTopology {
    var displayCount: UInt32 = 0
    let maxDisplays: UInt32 = 32
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
    guard CGGetActiveDisplayList(maxDisplays, &displays, &displayCount) == .success else {
      logger.error("Could not read active display topology; retaining the last known topology")
      return lastKnownTopology
    }
    let topology = DisplayTopology(
      regions: displays.prefix(Int(displayCount)).map { display in
        let bounds = CGDisplayBounds(display)
        return DisplayRegion(
          x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height)
      })
    lastKnownTopology = topology
    return topology
  }

  private func apply(_ response: RuntimeResponse) {
    diagnostics.record(response)
    let uiEffects = response.effects.filter { effect in
      switch effect {
      case .capabilitiesChanged, .freeModeStatusChanged, .modeChanged, .indicator, .pointerMoved,
        .configurationAccepted,
        .indicatorSizeChanged, .pointerPositionChanged, .configurationRejected,
        .eventTapShouldBeReenabled, .diagnostic:
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
      case .freeModeStatusChanged(let status): updateStatus(status)
      case .capabilitiesChanged(let state):
        logger.notice(
          "Capabilities changed: accessibility=\(state.accessibility), listenEvent=\(state.listenEvent), postEvent=\(state.postEvent)"
        )
      case .modeChanged(let isEnabled):
        logger.info("Free mode changed: enabled=\(isEnabled)")
      case .indicator(let isVisible): isVisible ? indicator.show() : indicator.hide()
      case .indicatorSizeChanged(let size): indicator.setSize(size)
      case .pointerPositionChanged(to: let point): indicator.move(to: point)
      case .pointerMoved(to: let point, buttons: _): indicator.move(to: point)
      case .configurationAccepted:
        configurationValid = true
        configurationError = nil
        reloadMenuItem?.title = "Reload Configuration"
        reloadMenuItem?.toolTip = nil
        logger.info("Configuration accepted")
      case .configurationRejected(let reason):
        showConfigurationError(reason)
      case .eventTapShouldBeReenabled:
        eventTapStatus = .recovering
        logger.warning("Event tap disabled; attempting recovery")
      case .diagnostic(.eventTapDisabled):
        eventTapStatus = .recovering
      case .diagnostic(.eventTapRecovered):
        eventTapStatus = .healthy
        logger.notice("Event tap recovered")
      case .diagnostic(.eventTapRecoveryFailed):
        eventTapStatus = .recoveryFailed
        logger.error("Event tap recovery failed; free mode remains disabled")
      case .diagnostic(.safetyExit):
        logger.notice("Safety cleanup completed")
      case .diagnostic(.configurationRejected):
        logger.warning("Configuration rejected")
      default: break
      }
    }
  }

  @objc private func frame(_ link: CADisplayLink) {
    diagnostics.recordFrame()
    let elapsed = link.timestamp - (lastFrameTime ?? link.timestamp)
    let delta = elapsed.isFinite ? max(elapsed, 0) : 0
    lastFrameTime = link.timestamp
    apply(runtimeResponse(for: .frame(deltaTime: delta)))
    // TCC has no reliable change notification. Poll on every display frame so a permission
    // revocation can end free mode before the next user-visible frame, without touching the tap
    // callback's latency-sensitive path.
    pollPermissions()
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
      diagnostics.recordConfigurationReadFailure()
      showConfigurationError("could not read configuration: \(error.localizedDescription)")
    }
  }

  private func showConfigurationError(_ message: String) {
    configurationValid = false
    configurationError = message
    reloadMenuItem?.title = "Reload Configuration: \(configurationMenuMessage(message))"
    reloadMenuItem?.toolTip = message
    logger.error("Configuration unavailable")
  }

  private func configurationMenuMessage(_ message: String) -> String {
    let limit = 64
    return message.count <= limit ? message : String(message.prefix(limit - 1)) + "…"
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
    let counters = diagnostics.snapshot()
    let summary = DiagnosticSummary(
      version: applicationVersion(), buildIdentity: buildIdentity(), permissions: state,
      configuration: configurationValid ? .valid : .invalid, eventTap: eventTapStatus,
      counters: counters).text
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(summary, forType: .string)
#if DEBUG
    logger.debug(
      "Diagnostic metrics: callbacks=\(counters.callbackCount), frames=\(counters.frameCount), pointerEffects=\(counters.pointerEffectCount), mouseButtonEffects=\(counters.mouseButtonEffectCount), scrollEffects=\(counters.scrollEffectCount), safetyExits=\(counters.safetyExitCount)"
    )
#endif
    logger.info("Diagnostic summary copied")
  }

  @objc private func quit() { NSApp.terminate(nil) }

  private func updateStatus(_ status: FreeModeStatus) {
    guard let button = statusItem?.button else { return }
    button.title = status.menuBarTitle
    button.toolTip = status.accessibilityDescription
    button.setAccessibilityLabel(status.menuBarTitle)
    button.setAccessibilityHelp(status.accessibilityDescription)
  }

  private func applicationVersion() -> String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
  }

  private func buildIdentity() -> String {
#if DEBUG
    let configuration = "Debug"
#else
    let configuration = "Release"
#endif
    let number = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    return "\(configuration) \(number)"
  }

  private func sessionLabel(_ state: SessionState) -> String {
    switch state {
    case .active: return "active"
    case .inactive: return "inactive"
    case .locked: return "locked"
    case .sleeping: return "sleeping"
    case .waking: return "waking"
    }
  }

  private func key(for code: CGKeyCode) -> Key {
    switch code {
    case CGKeyCode(kVK_Command): return .leftCommand
    case CGKeyCode(kVK_RightCommand): return .rightCommand
    case CGKeyCode(kVK_Control): return .leftControl
    case CGKeyCode(kVK_RightControl): return .rightControl
    case CGKeyCode(kVK_Option): return .leftOption
    case CGKeyCode(kVK_RightOption): return .rightOption
    case CGKeyCode(kVK_Shift): return .leftShift
    case CGKeyCode(kVK_RightShift): return .rightShift
    case CGKeyCode(kVK_CapsLock): return .capsLock
    case CGKeyCode(kVK_Function): return .function
    case CGKeyCode(kVK_Escape): return .escape
    case CGKeyCode(kVK_Return): return .returnKey
    case CGKeyCode(kVK_Tab): return .tab
    case CGKeyCode(kVK_Delete): return .delete
    case CGKeyCode(kVK_ForwardDelete): return .forwardDelete
    case CGKeyCode(kVK_Home): return .home
    case CGKeyCode(kVK_End): return .end
    case CGKeyCode(kVK_PageUp): return .pageUp
    case CGKeyCode(kVK_PageDown): return .pageDown
    case CGKeyCode(kVK_LeftArrow): return .arrowLeft
    case CGKeyCode(kVK_RightArrow): return .arrowRight
    case CGKeyCode(kVK_UpArrow): return .arrowUp
    case CGKeyCode(kVK_DownArrow): return .arrowDown
    case CGKeyCode(kVK_F1): return .functionKey(1)
    case CGKeyCode(kVK_F2): return .functionKey(2)
    case CGKeyCode(kVK_F3): return .functionKey(3)
    case CGKeyCode(kVK_F4): return .functionKey(4)
    case CGKeyCode(kVK_F5): return .functionKey(5)
    case CGKeyCode(kVK_F6): return .functionKey(6)
    case CGKeyCode(kVK_F7): return .functionKey(7)
    case CGKeyCode(kVK_F8): return .functionKey(8)
    case CGKeyCode(kVK_F9): return .functionKey(9)
    case CGKeyCode(kVK_F10): return .functionKey(10)
    case CGKeyCode(kVK_F11): return .functionKey(11)
    case CGKeyCode(kVK_F12): return .functionKey(12)
    case CGKeyCode(kVK_F13): return .functionKey(13)
    case CGKeyCode(kVK_F14): return .functionKey(14)
    case CGKeyCode(kVK_F15): return .functionKey(15)
    case CGKeyCode(kVK_F16): return .functionKey(16)
    case CGKeyCode(kVK_F17): return .functionKey(17)
    case CGKeyCode(kVK_F18): return .functionKey(18)
    case CGKeyCode(kVK_F19): return .functionKey(19)
    case CGKeyCode(kVK_F20): return .functionKey(20)
    case CGKeyCode(kVK_ANSI_A): return .a
    case CGKeyCode(kVK_ANSI_B): return .b
    case CGKeyCode(kVK_ANSI_C): return .c
    case CGKeyCode(kVK_ANSI_D): return .d
    case CGKeyCode(kVK_ANSI_E): return .e
    case CGKeyCode(kVK_ANSI_F): return .f
    case CGKeyCode(kVK_ANSI_G): return .g
    case CGKeyCode(kVK_ANSI_H): return .h
    case CGKeyCode(kVK_ANSI_I): return .i
    case CGKeyCode(kVK_ANSI_J): return .j
    case CGKeyCode(kVK_ANSI_K): return .k
    case CGKeyCode(kVK_ANSI_L): return .l
    case CGKeyCode(kVK_ANSI_M): return .m
    case CGKeyCode(kVK_ANSI_N): return .n
    case CGKeyCode(kVK_ANSI_O): return .o
    case CGKeyCode(kVK_ANSI_P): return .p
    case CGKeyCode(kVK_ANSI_Q): return .q
    case CGKeyCode(kVK_ANSI_R): return .r
    case CGKeyCode(kVK_ANSI_S): return .s
    case CGKeyCode(kVK_ANSI_T): return .t
    case CGKeyCode(kVK_ANSI_U): return .u
    case CGKeyCode(kVK_ANSI_V): return .v
    case CGKeyCode(kVK_ANSI_W): return .w
    case CGKeyCode(kVK_ANSI_X): return .x
    case CGKeyCode(kVK_ANSI_Y): return .y
    case CGKeyCode(kVK_ANSI_Z): return .z
    case CGKeyCode(kVK_ANSI_0): return .digit0
    case CGKeyCode(kVK_ANSI_1): return .digit1
    case CGKeyCode(kVK_ANSI_2): return .digit2
    case CGKeyCode(kVK_ANSI_3): return .digit3
    case CGKeyCode(kVK_ANSI_4): return .digit4
    case CGKeyCode(kVK_ANSI_5): return .digit5
    case CGKeyCode(kVK_ANSI_6): return .digit6
    case CGKeyCode(kVK_ANSI_7): return .digit7
    case CGKeyCode(kVK_ANSI_8): return .digit8
    case CGKeyCode(kVK_ANSI_9): return .digit9
    case CGKeyCode(kVK_ANSI_Minus): return .minus
    case CGKeyCode(kVK_ANSI_Equal): return .equal
    case CGKeyCode(kVK_ANSI_LeftBracket): return .leftBracket
    case CGKeyCode(kVK_ANSI_RightBracket): return .rightBracket
    case CGKeyCode(kVK_ANSI_Backslash): return .backslash
    case CGKeyCode(kVK_ANSI_Semicolon): return .semicolon
    case CGKeyCode(kVK_ANSI_Quote): return .quote
    case CGKeyCode(kVK_ANSI_Grave): return .grave
    case CGKeyCode(kVK_ANSI_Comma): return .comma
    case CGKeyCode(kVK_ANSI_Period): return .period
    case CGKeyCode(kVK_ANSI_Slash): return .slash
    case CGKeyCode(kVK_Space): return .space
    case CGKeyCode(kVK_ANSI_Keypad0): return .keypad0
    case CGKeyCode(kVK_ANSI_Keypad1): return .keypad1
    case CGKeyCode(kVK_ANSI_Keypad2): return .keypad2
    case CGKeyCode(kVK_ANSI_Keypad3): return .keypad3
    case CGKeyCode(kVK_ANSI_Keypad4): return .keypad4
    case CGKeyCode(kVK_ANSI_Keypad5): return .keypad5
    case CGKeyCode(kVK_ANSI_Keypad6): return .keypad6
    case CGKeyCode(kVK_ANSI_Keypad7): return .keypad7
    case CGKeyCode(kVK_ANSI_Keypad8): return .keypad8
    case CGKeyCode(kVK_ANSI_Keypad9): return .keypad9
    case CGKeyCode(kVK_ANSI_KeypadDecimal): return .keypadDecimal
    case CGKeyCode(kVK_ANSI_KeypadMultiply): return .keypadMultiply
    case CGKeyCode(kVK_ANSI_KeypadPlus): return .keypadPlus
    case CGKeyCode(kVK_ANSI_KeypadClear): return .keypadClear
    case CGKeyCode(kVK_ANSI_KeypadDivide): return .keypadDivide
    case CGKeyCode(kVK_ANSI_KeypadEnter): return .keypadEnter
    case CGKeyCode(kVK_ANSI_KeypadMinus): return .keypadMinus
    case CGKeyCode(kVK_ANSI_KeypadEquals): return .keypadEquals
    case CGKeyCode(kVK_ISO_Section): return .isoSection
    case CGKeyCode(kVK_JIS_Yen): return .jisYen
    case CGKeyCode(kVK_JIS_Underscore): return .jisUnderscore
    case CGKeyCode(kVK_JIS_KeypadComma): return .jisKeypadComma
    case CGKeyCode(kVK_JIS_Eisu): return .jisEisu
    case CGKeyCode(kVK_JIS_Kana): return .jisKana
    default: return .other(Int(code))
    }
  }

  private func modifierState(for event: CGEvent, key: Key? = nil) -> KeyboardModifiers {
    var state = keyboardModifiers
    if let key, let modifier = KeyboardModifiers.modifier(for: key) {
      switch key {
      case .capsLock:
        if event.flags.contains(.maskAlphaShift) {
          state.insert(modifier)
        } else {
          state.remove(modifier)
        }
      case .function:
        if event.flags.contains(.maskSecondaryFn) {
          state.insert(modifier)
        } else {
          state.remove(modifier)
        }
      default:
        if state.contains(modifier) {
          state.remove(modifier)
        } else {
          state.insert(modifier)
        }
      }
    }
    if !event.flags.contains(.maskCommand) { state.subtract(.command) }
    if !event.flags.contains(.maskControl) { state.subtract(.control) }
    if !event.flags.contains(.maskAlternate) { state.subtract(.option) }
    if !event.flags.contains(.maskShift) { state.subtract(.shift) }
    keyboardModifiers = state
    return state
  }

  private func modifierPhase(for key: Key, modifiers: KeyboardModifiers) -> KeyboardEventPhase {
    guard let modifier = KeyboardModifiers.modifier(for: key) else { return .down }
    return modifiers.contains(modifier) ? .down : .up
  }
}

@main
struct MouselessAppMain {
  static func main() {
    let application = NSApplication.shared
    let controller = MouselessApplicationController()
    let delegate = AppDelegate(controller: controller)
    application.delegate = delegate
    application.setActivationPolicy(.regular)
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
