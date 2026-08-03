import XCTest
import CoreGraphics
@testable import MacPlatform

final class IslandPanelGeometryTests: XCTestCase {
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
