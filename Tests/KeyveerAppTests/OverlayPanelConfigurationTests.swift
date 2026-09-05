import AppKit
import XCTest

@testable import KeyveerApp

final class OverlayPanelConfigurationTests: XCTestCase {
  @MainActor
  func testOverlayPanelDisablesTheSystemWindowShadow() {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)

    XCTAssertTrue(panel.hasShadow)

    configureOverlayPanel(panel)

    XCTAssertFalse(panel.hasShadow)
  }
}
