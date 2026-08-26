import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import OSLog

private let logger = Logger(subsystem: "com.reinerlau.mouseless.tcc-spike", category: "prototype")
private let testKeyCode = CGKeyCode(kVK_ANSI_M)
private let requiredFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let controller = Unmanaged<SpikeController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}

final class SpikeController: NSObject {
    private var statusItem: NSStatusItem?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var statusMenuItem: NSMenuItem?
    private var recoveryMenuItem: NSMenuItem?
    private var recoveryCount = 0

    func start() {
        configureStatusItem()
        checkPermissionsAndStartTap(prompt: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recoveryCount += 1
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            refreshRecoveryLabel()
            logger.warning("Event tap was disabled and has been re-enabled")
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        guard keyCode == testKeyCode, flags.contains(requiredFlags) else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown,
           event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            movePointerRight()
        }

        return nil
    }

    @objc private func recheckPermissions() {
        checkPermissionsAndStartTap(prompt: true)
    }

    @objc private func cycleEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        logger.info("Event tap manually cycled")
    }

    @objc private func quit() {
        stop()
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "TCC…"

        let menu = NSMenu()
        let instructions = NSMenuItem(title: "Press ⌃⌥⌘M to move right 40 pt", action: nil, keyEquivalent: "")
        instructions.isEnabled = false
        menu.addItem(instructions)

        let status = NSMenuItem(title: "Checking permissions…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        let recovery = NSMenuItem(title: "Tap recoveries: 0", action: nil, keyEquivalent: "")
        recovery.isEnabled = false
        menu.addItem(recovery)
        recoveryMenuItem = recovery

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Recheck Permissions", action: #selector(recheckPermissions), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Cycle Event Tap", action: #selector(cycleEventTap), keyEquivalent: "c"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Spike", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func checkPermissionsAndStartTap(prompt: Bool) {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary

        let accessibility = AXIsProcessTrustedWithOptions(options)
        let listen = CGPreflightListenEventAccess() || (prompt && CGRequestListenEventAccess())
        let post = CGPreflightPostEventAccess() || (prompt && CGRequestPostEventAccess())

        guard accessibility, listen, post else {
            stop()
            statusItem?.button?.title = "TCC!"
            statusMenuItem?.title = "Missing: \(missingPermissions(accessibility: accessibility, listen: listen, post: post))"
            logger.notice("Permissions incomplete: accessibility=\(accessibility), listen=\(listen), post=\(post)")
            return
        }

        guard installEventTap() else {
            statusItem?.button?.title = "TCC×"
            statusMenuItem?.title = "Permissions granted; event tap creation failed"
            logger.error("Permission checks passed but event tap creation failed")
            return
        }

        statusItem?.button?.title = "TCC✓"
        statusMenuItem?.title = "Ready: active tap + event posting"
        logger.info("TCC signing spike is ready")
    }

    private func installEventTap() -> Bool {
        if eventTap != nil {
            return true
        }

        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func movePointerRight() {
        guard let currentEvent = CGEvent(source: nil) else { return }
        let current = currentEvent.location
        let target = CGPoint(x: current.x + 40, y: current.y)
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let movement = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: target,
            mouseButton: .left
        ) else { return }

        movement.post(tap: .cghidEventTap)
        logger.info("Test chord accepted; pointer movement posted")
    }

    private func missingPermissions(accessibility: Bool, listen: Bool, post: Bool) -> String {
        var missing: [String] = []
        if !accessibility { missing.append("Accessibility") }
        if !listen { missing.append("Listen Event") }
        if !post { missing.append("Post Event") }
        return missing.joined(separator: ", ")
    }

    private func refreshRecoveryLabel() {
        recoveryMenuItem?.title = "Tap recoveries: \(recoveryCount)"
    }
}

final class SpikeAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = SpikeController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}

@main
enum TCCSigningSpikeMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = SpikeAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
