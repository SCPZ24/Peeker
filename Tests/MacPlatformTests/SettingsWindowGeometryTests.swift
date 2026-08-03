import AppKit
import XCTest
@testable import MacPlatform

final class SettingsWindowGeometryTests: XCTestCase {
    func testFrameCentersAtFortyPercentOfVisibleScreenHeight() {
        let frame = SettingsWindowGeometry.frame(
            windowSize: CGSize(width: 600, height: 500),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(frame.midX, 720)
        XCTAssertEqual(frame.midY, 360)
        XCTAssertEqual(frame.size, CGSize(width: 600, height: 500))
    }

    func testFrameUsesVisibleFrameOriginOnExternalScreen() {
        let frame = SettingsWindowGeometry.frame(
            windowSize: CGSize(width: 500, height: 400),
            visibleFrame: CGRect(x: -1_920, y: 40, width: 1_920, height: 1_000)
        )

        XCTAssertEqual(frame.midX, -960)
        XCTAssertEqual(frame.midY, 440)
    }

    func testFrameClampsToVisibleBoundsWhenFortyPercentAnchorWouldOverflow() {
        let frame = SettingsWindowGeometry.frame(
            windowSize: CGSize(width: 900, height: 700),
            visibleFrame: CGRect(x: 20, y: 50, width: 1_000, height: 800)
        )

        XCTAssertEqual(frame.minX, 70)
        XCTAssertEqual(frame.minY, 50)
        XCTAssertLessThanOrEqual(frame.maxX, 1_020)
        XCTAssertLessThanOrEqual(frame.maxY, 850)
    }

    func testOversizedWindowKeepsSizeAndAlignsToVisibleOrigin() {
        let frame = SettingsWindowGeometry.frame(
            windowSize: CGSize(width: 1_200, height: 900),
            visibleFrame: CGRect(x: 20, y: 50, width: 1_000, height: 800)
        )

        XCTAssertEqual(frame.origin, CGPoint(x: 20, y: 50))
        XCTAssertEqual(frame.size, CGSize(width: 1_200, height: 900))
    }
}

@MainActor
final class SettingsWindowPositionerTests: XCTestCase {
    func testRegisterImmediatelyPositionsTheSettingsWindow() {
        let window = makeWindow()
        let positioner = SettingsWindowPositioner { _ in
            CGRect(x: 0, y: 0, width: 1_440, height: 900)
        }

        positioner.register(window)

        XCTAssertEqual(window.frame.midX, 720)
        XCTAssertEqual(window.frame.midY, 360)
    }

    func testRepositionRestoresRegisteredWindowAfterItMoves() {
        let window = makeWindow()
        let visibleFrame = try! XCTUnwrap(NSScreen.main?.visibleFrame)
        let positioner = SettingsWindowPositioner { _ in visibleFrame }
        positioner.register(window)
        window.setFrameOrigin(CGPoint(x: 200, y: 300))

        positioner.repositionAndBringForward()

        XCTAssertEqual(window.frame.midX, visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(
            window.frame.midY,
            visibleFrame.minY + visibleFrame.height * 0.40,
            accuracy: 0.5
        )
    }

    func testBecomingKeyReappliesPositionAfterWindowRestoration() async {
        let window = makeWindow()
        let visibleFrame = try! XCTUnwrap(NSScreen.main?.visibleFrame)
        let positioner = SettingsWindowPositioner { _ in visibleFrame }
        positioner.register(window)
        window.setFrameOrigin(CGPoint(x: 200, y: 300))

        let mainQueueDrained = expectation(description: "Main queue applied the final settings frame")
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        DispatchQueue.main.async {
            mainQueueDrained.fulfill()
        }
        await fulfillment(of: [mainQueueDrained], timeout: 1)

        XCTAssertEqual(window.frame.midX, visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(
            window.frame.midY,
            visibleFrame.minY + visibleFrame.height * 0.40,
            accuracy: 0.5
        )
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.setFrame(CGRect(x: 200, y: 300, width: 600, height: 500), display: false)
        return window
    }
}
