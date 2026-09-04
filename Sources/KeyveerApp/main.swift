import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import KeyveerRuntime
import OSLog
import QuartzCore

private let synthesizedEventMarker: Int64 = 0x4B45_5956_4545_5200
private let logger = Logger(subsystem: "com.reinerlau.keyveer", category: "runtime")
private let multiClickPointTolerance: CGFloat = 2

private func primaryScreenTop() -> CGFloat {
  CGDisplayBounds(CGMainDisplayID()).maxY
}

private func cocoaPoint(fromQuartz point: CGPoint) -> Point {
  Point(x: point.x, y: primaryScreenTop() - point.y)
}

private func quartzPoint(fromRuntime point: Point) -> CGPoint {
  CGPoint(x: point.x, y: point.y)
}

private struct ClickSequence {
  var count: Int64 = 0
  var lastDownTime: TimeInterval?
  var lastPoint: CGPoint?
}

private final class SystemPermissionProvider {
  func current(prompt: Bool) -> PermissionState {
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    let accessibility = AXIsProcessTrustedWithOptions(options)
    return PermissionState(
      accessibility: accessibility, postEvent: CGPreflightPostEventAccess())
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
  private let queue = DispatchQueue(label: "com.reinerlau.keyveer.effects")
  private var clickSequences: [MouseButton: ClickSequence] = [:]
  private var pointerLocation: CGPoint?

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
      let quartzPoint = quartzPoint(fromRuntime: point)
      pointerLocation = quartzPoint
      if buttons.isEmpty {
        postMouse(type: .mouseMoved, point: quartzPoint, button: .left)
      } else {
        for button in buttons.sorted(by: { $0.rawValue < $1.rawValue }) {
          postMouse(
            type: draggedType(for: button), point: quartzPoint,
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
      // The runtime's pointer is authoritative. Reading the global cursor here can lag behind
      // a just-posted virtual move, which makes a click land on the previously selected item.
      let point = pointerLocation ?? CGEvent(source: nil)?.location ?? .zero
      let metadata = eventMetadata(for: button, phase: phase, point: point)
      postMouse(
        type: type, point: point, button: cgButton(for: button),
        clickState: metadata)
    case .scroll(let pixelX, let pixelY):
      guard
        let event = CGEvent(
          scrollWheelEvent2Source: CGEventSource(stateID: .combinedSessionState), units: .pixel,
          wheelCount: 2, wheel1: Int32(pixelY),
          wheel2: Int32(ScrollEventMapping.coreGraphicsWheel2Value(forHorizontalPixelDelta: pixelX)),
          wheel3: 0)
      else { return }
      event.setIntegerValueField(.eventSourceUserData, value: synthesizedEventMarker)
      event.post(tap: .cghidEventTap)
    default: break
    }
  }

  private func eventMetadata(
    for button: MouseButton, phase: ButtonPhase, point: CGPoint
  ) -> Int64? {
    switch phase {
    case .down:
      var sequence = clickSequences[button] ?? ClickSequence()
      let now = CACurrentMediaTime()
      if let lastDownTime = sequence.lastDownTime,
        let lastPoint = sequence.lastPoint,
        now - lastDownTime <= NSEvent.doubleClickInterval,
        distance(lastPoint, point) <= multiClickPointTolerance
      {
        sequence.count += 1
      } else {
        sequence.count = 1
      }
      sequence.lastDownTime = now
      sequence.lastPoint = point
      clickSequences[button] = sequence
      return sequence.count
    case .up:
      guard let sequence = clickSequences[button] else {
        return nil
      }
      return sequence.count
    }
  }

  private func postMouse(
    type: CGEventType, point: CGPoint, button: CGMouseButton, clickState: Int64? = nil
  ) {
    guard
      let event = CGEvent(
        mouseEventSource: CGEventSource(stateID: .combinedSessionState), mouseType: type,
        mouseCursorPosition: point, mouseButton: button)
    else { return }
    if let clickState {
      event.setIntegerValueField(.mouseEventClickState, value: clickState)
    }
    event.setIntegerValueField(.eventSourceUserData, value: synthesizedEventMarker)
    event.post(tap: .cghidEventTap)
  }

  private func cgButton(for button: MouseButton) -> CGMouseButton {
    CGMouseButton(rawValue: UInt32(button.rawValue))!
  }

  private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
    hypot(lhs.x - rhs.x, lhs.y - rhs.y)
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
          tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
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

private final class CursorHaloController {
  private final class HaloView: NSView {
    override func draw(_ dirtyRect: NSRect) {
      let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
      path.lineWidth = 2
      let shadow = NSShadow()
      shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
      shadow.shadowBlurRadius = 2
      shadow.shadowOffset = .zero
      shadow.set()
      NSColor.white.withAlphaComponent(0.9).setStroke()
      path.stroke()
      NSColor.systemBlue.setStroke()
      path.stroke()
    }
  }
  private let panelFactory: (NSRect) -> NSPanel?
  private var window: NSPanel?
  private var diameter = 28.0
  private var lastPoint: Point?

  init(
    // The default AppKit initializer is non-failable; the optional factory is a narrow seam so
    // presentation failure can be exercised without inventing an impossible runtime condition.
    panelFactory: @escaping (NSRect) -> NSPanel? = { frame in
      NSPanel(
        contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
        defer: false)
    }
  ) {
    self.panelFactory = panelFactory
  }

  @discardableResult
  func show() -> Bool {
    if window == nil {
      guard let panel = panelFactory(NSRect(x: 0, y: 0, width: diameter, height: diameter)) else {
        return false
      }
      panel.level = .floating
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.ignoresMouseEvents = true
      panel.hidesOnDeactivate = false
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
      panel.contentView = HaloView(frame: panel.contentRect(forFrameRect: panel.frame))
      window = panel
    }
    window?.orderFrontRegardless()
    if let lastPoint { move(to: lastPoint) }
    return window != nil
  }

  func setDiameter(_ diameter: Double) {
    self.diameter = diameter
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

private final class BindingReferencePanelController {
  private let panel: NSPanel

  init(reference: BindingReference) {
    panel = NSPanel(
      contentRect: .zero, styleMask: [.titled, .closable, .utilityWindow], backing: .buffered,
      defer: false)
    panel.title = "Key Bindings"
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .utilityWindow
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentView = contentView(for: reference)
    panel.setContentSize(NSSize(width: 600, height: 522))
    panel.setFrameAutosaveName("KeyBindingsPanel")
    if !panel.setFrameUsingName("KeyBindingsPanel") { panel.center() }
  }

  var isVisible: Bool { panel.isVisible }

  func show() {
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  func close() { panel.close() }

  private func contentView(for reference: BindingReference) -> NSView {
    let content = NSView()
    let groups = reference.sections.map(sectionView)
      + [sectionView(BindingReferenceSection(title: "Safety Exit", items: [reference.safetyExit]))]
    let stack = NSStackView(views: groups)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.distribution = .fill
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
    ])
    return content
  }

  private func sectionView(_ section: BindingReferenceSection) -> NSView {
    let title = NSTextField(labelWithString: section.title)
    title.font = .systemFont(ofSize: 12, weight: .semibold)
    title.textColor = .secondaryLabelColor

    let cards = NSStackView(views: section.items.map(cardView))
    cards.orientation = .horizontal
    cards.alignment = .top
    cards.distribution = .fill
    cards.spacing = 10

    let sectionStack = NSStackView(views: [title, cards])
    sectionStack.orientation = .vertical
    sectionStack.alignment = .leading
    sectionStack.spacing = 4
    return sectionStack
  }

  private func cardView(_ item: BindingReferenceItem) -> NSView {
    let key = NSTextField(labelWithString: item.key)
    key.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
    key.alignment = .center
    key.lineBreakMode = .byTruncatingTail
    key.wantsLayer = true
    key.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    key.layer?.cornerRadius = 5

    let action = NSTextField(labelWithString: item.action)
    action.font = .systemFont(ofSize: 11)
    action.textColor = .secondaryLabelColor
    action.alignment = .center
    action.lineBreakMode = .byTruncatingTail

    let stack = NSStackView(views: [key, action])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 4
    stack.setAccessibilityElement(true)
    stack.setAccessibilityRole(.group)
    stack.setAccessibilityLabel("\(item.key), \(item.action)")
    NSLayoutConstraint.activate([
      stack.widthAnchor.constraint(equalToConstant: 104),
      key.widthAnchor.constraint(equalTo: stack.widthAnchor),
      key.heightAnchor.constraint(equalToConstant: 26),
    ])
    return stack
  }
}

private final class KeyveerApplicationController: NSObject {
  private let permissions = SystemPermissionProvider()
  private let executor = CoreGraphicsEffectExecutor()
  private let cursorHalo = CursorHaloController()
  private let diagnostics = DiagnosticCollector()
  private let runtime = KeyveerRuntime()
  private let runtimeLock = NSLock()
  private var eventTap: EventTapHost?
  private let eventTapLock = NSLock()
  private var displayLink: CADisplayLink?
  private var statusItem: NSStatusItem?
  private var bindingReferencePanel: BindingReferencePanelController?
  private var reloadMenuItem: NSMenuItem?
  private var cursorHaloUnavailableMenuItem: NSMenuItem?
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
    // Permission prompts are user-initiated from the menu. Launch only inspects current state so
    // it cannot consume or obscure the first explicit request.
    checkPermissions(prompt: false)
    displayLink = NSScreen.main?.displayLink(target: self, selector: #selector(frame(_:)))
    displayLink?.add(to: .main, forMode: .common)
  }

  func stop() {
    logger.notice("Application stopping")
    displayLink?.invalidate()
    displayLink = nil
    bindingReferencePanel?.close()
    bindingReferencePanel = nil
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
    item.button?.imagePosition = .imageOnly
    item.button?.imageScaling = .scaleNone
    updateStatus(runtime.freeModeStatus)
    let menu = NSMenu()
    menu.addItem(menuItem("Help", #selector(showHelp)))
    menu.addItem(.separator())
    menu.addItem(menuItem("Request Permissions", #selector(requestPermissions)))
    menu.addItem(menuItem("Open System Settings", #selector(openSystemSettings)))
    menu.addItem(menuItem("Recheck Permissions", #selector(recheckPermissions)))
    let reload = menuItem("Reload Configuration", #selector(reloadConfigurationFromMenu))
    menu.addItem(reload)
    reloadMenuItem = reload
    let haloUnavailable = NSMenuItem(title: "Cursor Halo: Unavailable", action: nil, keyEquivalent: "")
    haloUnavailable.isEnabled = false
    haloUnavailable.isHidden = true
    menu.addItem(haloUnavailable)
    cursorHaloUnavailableMenuItem = haloUnavailable
    menu.addItem(menuItem("Copy Diagnostic Summary", #selector(copyDiagnostics)))
    menu.addItem(.separator())
    menu.addItem(menuItem("Quit Keyveer", #selector(quit)))
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
    if state.isReady {
      if currentEventTap() == nil {
        let host = EventTapHost { [weak self] type, event in
          self?.handleTapEvent(type: type, event: event) ?? Unmanaged.passUnretained(event)
        }
        if host.start() {
          setEventTap(host)
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
      eventTapStatus = .healthy
      apply(runtimeResponse(for: .eventTapReady))
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
      case .capabilitiesChanged, .freeModeStatusChanged, .modeChanged, .cursorHalo, .pointerMoved,
        .configurationAccepted,
        .cursorHaloDiameterChanged, .pointerPositionChanged, .configurationRejected,
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
          "Capabilities changed: accessibility=\(state.accessibility), postEvent=\(state.postEvent)"
        )
      case .modeChanged(let isEnabled):
        logger.info("Free mode changed: enabled=\(isEnabled)")
      case .cursorHalo(let isVisible):
        if isVisible {
          if cursorHalo.show() {
            cursorHaloUnavailableMenuItem?.isHidden = true
          } else {
            apply(runtimeResponse(for: .cursorHaloPresentationFailed))
          }
        } else {
          cursorHalo.hide()
          cursorHaloUnavailableMenuItem?.isHidden = true
        }
      case .cursorHaloDiameterChanged(let diameter): cursorHalo.setDiameter(diameter)
      case .pointerPositionChanged(to: let point): cursorHalo.move(to: point)
      case .pointerMoved(to: let point, buttons: _): cursorHalo.move(to: point)
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
      case .diagnostic(.cursorHaloUnavailable):
        cursorHaloUnavailableMenuItem?.isHidden = false
        logger.error("Cursor halo presentation unavailable; free mode remains enabled")
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

  @objc private func requestPermissions() {
    let coordinator = PermissionRequestCoordinator(
      request: { [permissions] in permissions.current(prompt: true) },
      apply: { [weak self] state in
        self?.lastPermissionState = state
        self?.reconcilePermissions(state, clearEventTapFailure: true)
      },
      present: { [weak self] feedback in self?.presentPermissionFeedback(feedback) })
    coordinator.run()
  }
  @objc private func showHelp() {
    if let bindingReferencePanel, bindingReferencePanel.isVisible {
      bindingReferencePanel.show()
      return
    }
    let panel = BindingReferencePanelController(reference: currentBindingReference())
    bindingReferencePanel = panel
    panel.show()
  }
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
      .appendingPathComponent("Keyveer", isDirectory: true).appendingPathComponent("config.json")
  }

  private func currentBindingReference() -> BindingReference {
    runtimeLock.lock()
    defer { runtimeLock.unlock() }
    return runtime.bindingReference
  }

  @objc private func openSystemSettings() {
    openAccessibilitySettings()
  }

  private func presentPermissionFeedback(_ feedback: PermissionRequestFeedback) {
    switch feedback {
    case .allGranted:
      let alert = NSAlert()
      alert.messageText = "Permissions Granted"
      alert.informativeText = "Keyveer has Accessibility access."
      alert.alertStyle = .informational
      alert.addButton(withTitle: "OK")
      NSApp.activate(ignoringOtherApps: true)
      alert.runModal()
    case .openAccessibilitySettings:
      openAccessibilitySettings()
    }
  }

  private func openAccessibilitySettings() {
    let anchor = "Privacy_Accessibility"
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"),
      NSWorkspace.shared.open(url)
    else {
      let alert = NSAlert()
      alert.messageText = "Could Not Open System Settings"
      alert.informativeText =
        "Open Privacy & Security in System Settings and grant Keyveer the requested access."
      alert.alertStyle = .warning
      alert.addButton(withTitle: "OK")
      NSApp.activate(ignoringOtherApps: true)
      alert.runModal()
      return
    }
    logger.notice("Opened System Settings for \(anchor, privacy: .public)")
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
    button.title = ""
    let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
    button.image = NSImage(
      systemSymbolName: status.menuBarSymbolName,
      accessibilityDescription: "Keyveer")?.withSymbolConfiguration(symbolConfiguration)
    button.image?.size = NSSize(width: 15, height: 15)
    button.image?.isTemplate = true
    button.toolTip = status.accessibilityDescription
    button.setAccessibilityLabel(status.accessibilityDescription)
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
    if event.flags.contains(.maskAlphaShift) {
      state.insert(.capsLock)
    } else {
      state.remove(.capsLock)
    }
    if event.flags.contains(.maskSecondaryFn) {
      state.insert(.function)
    } else {
      state.remove(.function)
    }
    keyboardModifiers = state
    return state
  }

  private func modifierPhase(for key: Key, modifiers: KeyboardModifiers) -> KeyboardEventPhase {
    guard let modifier = KeyboardModifiers.modifier(for: key) else { return .down }
    return modifiers.contains(modifier) ? .down : .up
  }
}

@main
struct KeyveerAppMain {
  static func main() {
    let application = NSApplication.shared
    let controller = KeyveerApplicationController()
    let delegate = AppDelegate(controller: controller)
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
    withExtendedLifetime(controller) {}
  }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
  let controller: KeyveerApplicationController
  init(controller: KeyveerApplicationController) { self.controller = controller }
  func applicationDidFinishLaunching(_ notification: Notification) { controller.start() }
  func applicationWillTerminate(_ notification: Notification) { controller.stop() }
}
