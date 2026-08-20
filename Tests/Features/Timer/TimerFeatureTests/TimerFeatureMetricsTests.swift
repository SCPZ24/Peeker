import XCTest
@testable import TimerFeature

@MainActor
final class TimerFeatureMetricsTests: XCTestCase {
    func testCompactSurfaceUsesRoomyRunningTaskLayout() {
        let metrics = TimerFeatureFactory.metrics

        XCTAssertEqual(metrics.compactWidth, 340)
        XCTAssertEqual(metrics.compactHeight, 32)
        XCTAssertEqual(metrics.compactLeadingWidth, 208)
        XCTAssertEqual(metrics.compactTrailingWidth, 136)
    }

    func testExpandedSurfaceKeepsItsWidthAndUsesFiveSeventhsOfThePreviousHeight() {
        let metrics = TimerFeatureFactory.metrics

        XCTAssertEqual(metrics.expandedWidth, 800)
        XCTAssertEqual(
            metrics.expandedHeight,
            328.571_428_571_428_56,
            accuracy: 0.000_001
        )
    }
}
