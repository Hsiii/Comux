import AppKit
import XCTest
@testable import Comux

final class MenuPanelWindowAppearanceTests: XCTestCase {
    @MainActor
    func testApplyRoundsTheWindowSurfaceWithoutChangingItsFrame() {
        let initialFrame = NSRect(x: 0, y: 0, width: 360, height: 540)
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let initialContentFrame = window.contentView?.frame

        MenuPanelWindowAppearance.apply(to: window)

        let surfaceView = window.contentView?.superview ?? window.contentView
        XCTAssertEqual(window.frame.size, initialFrame.size)
        XCTAssertEqual(window.contentView?.frame, initialContentFrame)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertEqual(surfaceView?.layer?.cornerRadius, 26)
        XCTAssertEqual(surfaceView?.layer?.cornerCurve, .continuous)
        XCTAssertEqual(surfaceView?.layer?.masksToBounds, true)
    }
}
