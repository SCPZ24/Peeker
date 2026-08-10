import XCTest
@testable import PusherFeature

final class PusherCalendarMetricsTests: XCTestCase {
    func testGreenIntensityUsesFourCompletionBuckets() {
        XCTAssertEqual(PusherCalendarMetrics.greenOpacity(doneCount: 1, totalCount: 4), 0.16)
        XCTAssertEqual(PusherCalendarMetrics.greenOpacity(doneCount: 1, totalCount: 3), 0.28)
        XCTAssertEqual(PusherCalendarMetrics.greenOpacity(doneCount: 1, totalCount: 2), 0.28)
        XCTAssertEqual(PusherCalendarMetrics.greenOpacity(doneCount: 2, totalCount: 3), 0.43)
        XCTAssertEqual(PusherCalendarMetrics.greenOpacity(doneCount: 3, totalCount: 4), 0.43)
        XCTAssertEqual(PusherCalendarMetrics.greenOpacity(doneCount: 4, totalCount: 4), 0.62)
    }

    func testZeroTotalIsNeutralAndCountsAreClamped() {
        XCTAssertNil(PusherCalendarMetrics.greenOpacity(doneCount: 0, totalCount: 0))
        XCTAssertEqual(PusherCalendarMetrics.greenOpacity(doneCount: -1, totalCount: 4), 0)
        XCTAssertEqual(PusherCalendarMetrics.greenOpacity(doneCount: 9, totalCount: 4), 0.62)
    }
}
