import XCTest
@testable import TimerFeature

@MainActor
final class TimerFeatureMetricsTests: XCTestCase {
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
