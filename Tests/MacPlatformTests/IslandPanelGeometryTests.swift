import XCTest
import CoreGraphics
@testable import MacPlatform

final class IslandPanelGeometryTests: XCTestCase {
    func testCompactAndExpandedFramesShareTopCenterAnchor() {
        let screenFrame = CGRect(x: -1_600, y: 120, width: 1_440, height: 900)
        let compact = IslandPanelGeometry.frame(
            requestedSize: CGSize(width: 340, height: 38),
            screenFrame: screenFrame,
            safeTopInset: 32,
            margin: 16
        )
        let expanded = IslandPanelGeometry.frame(
            requestedSize: CGSize(width: 760, height: 420),
            screenFrame: screenFrame,
            safeTopInset: 32,
            margin: 16
        )

        XCTAssertEqual(compact.midX, -880)
        XCTAssertEqual(expanded.midX, -880)
        XCTAssertEqual(compact.maxY, 1_004)
        XCTAssertEqual(expanded.maxY, 1_004)
    }

    func testAnimationPolicyDisablesMotionForInitialDisplayAndReduceMotion() {
        XCTAssertNil(
            IslandPanelAnimation.duration(
                requested: false,
                isExpanded: true,
                reduceMotion: false,
                panelIsVisible: true
            )
        )
        XCTAssertNil(
            IslandPanelAnimation.duration(
                requested: true,
                isExpanded: true,
                reduceMotion: false,
                panelIsVisible: false
            )
        )
        XCTAssertNil(
            IslandPanelAnimation.duration(
                requested: true,
                isExpanded: true,
                reduceMotion: true,
                panelIsVisible: true
            )
        )
    }

    func testAnimationPolicyUsesStateSpecificDurationsForVisiblePanel() {
        XCTAssertEqual(
            IslandPanelAnimation.duration(
                requested: true,
                isExpanded: true,
                reduceMotion: false,
                panelIsVisible: true
            ),
            0.22
        )
        XCTAssertEqual(
            IslandPanelAnimation.duration(
                requested: true,
                isExpanded: false,
                reduceMotion: false,
                panelIsVisible: true
            ),
            0.18
        )
    }

    func testPanelIsTopCenteredAndClampedToVisibleWidth() {
        let frame = IslandPanelGeometry.frame(
            requestedSize: CGSize(width: 920, height: 480),
            screenFrame: CGRect(x: 100, y: 40, width: 800, height: 600),
            safeTopInset: 28,
            margin: 16
        )

        XCTAssertEqual(frame.width, 768)
        XCTAssertEqual(frame.midX, 500)
        XCTAssertEqual(frame.maxY, 624)
    }

    func testCompactPanelKeepsRequestedSizeWhenItFits() {
        let frame = IslandPanelGeometry.frame(
            requestedSize: CGSize(width: 340, height: 38),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            safeTopInset: 0,
            margin: 16
        )

        XCTAssertEqual(frame.size, CGSize(width: 340, height: 38))
        XCTAssertEqual(frame.minX, 550)
        XCTAssertEqual(frame.maxY, 884)
    }
}
