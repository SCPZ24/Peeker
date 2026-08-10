import XCTest
@testable import PusherFeature

@MainActor
final class PusherFeatureMetricsTests: XCTestCase {
    func testExpandedSurfaceKeepsItsWidthAndUsesFiveSeventhsOfThePreviousHeight() {
        let metrics = PusherFeatureFactory.metrics

        XCTAssertEqual(metrics.expandedWidth, 960)
        XCTAssertEqual(
            metrics.expandedHeight,
            371.428_571_428_571_44,
            accuracy: 0.000_001
        )
    }
}
