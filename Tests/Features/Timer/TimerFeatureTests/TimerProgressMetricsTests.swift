import XCTest
@testable import TimerFeature

final class TimerProgressMetricsTests: XCTestCase {
    func testTaskRatioUsesElapsedFractionAndClampsBounds() {
        XCTAssertEqual(
            TimerProgressSnapshot(targetSeconds: 100, remainingSeconds: 75).ratio,
            0.25,
            accuracy: 0.000_001
        )
        XCTAssertEqual(TimerProgressSnapshot(targetSeconds: 100, remainingSeconds: 100).ratio, 0)
        XCTAssertEqual(TimerProgressSnapshot(targetSeconds: 100, remainingSeconds: 0).ratio, 1)
        XCTAssertEqual(TimerProgressSnapshot(targetSeconds: 100, remainingSeconds: -20).ratio, 1)
        XCTAssertEqual(TimerProgressSnapshot(targetSeconds: 100, remainingSeconds: 120).ratio, 0)
        XCTAssertEqual(TimerProgressSnapshot(targetSeconds: 0, remainingSeconds: 0).ratio, 0)
    }

    func testTotalRatioIsWeightedByTargetSeconds() throws {
        let snapshots = [
            TimerProgressSnapshot(targetSeconds: 100, remainingSeconds: 50),
            TimerProgressSnapshot(targetSeconds: 300, remainingSeconds: 225),
        ]
        let ratio = try XCTUnwrap(TimerProgressMetrics.totalRatio(snapshots))

        XCTAssertEqual(ratio, 0.3125, accuracy: 0.000_001)
    }

    func testTotalRatioIsNilWithoutPositiveTargets() {
        XCTAssertNil(TimerProgressMetrics.totalRatio([]))
        XCTAssertNil(
            TimerProgressMetrics.totalRatio([
                TimerProgressSnapshot(targetSeconds: 0, remainingSeconds: 0),
                TimerProgressSnapshot(targetSeconds: -10, remainingSeconds: 0),
            ])
        )
    }

    func testTotalRatioClampsRemainingAndIgnoresNonpositiveTargets() throws {
        let ratio = try XCTUnwrap(
            TimerProgressMetrics.totalRatio([
                TimerProgressSnapshot(targetSeconds: 100, remainingSeconds: -20),
                TimerProgressSnapshot(targetSeconds: 200, remainingSeconds: 250),
                TimerProgressSnapshot(targetSeconds: 0, remainingSeconds: 0),
                TimerProgressSnapshot(targetSeconds: -50, remainingSeconds: -50),
            ])
        )

        XCTAssertEqual(ratio, 1.0 / 3.0, accuracy: 0.000_001)
    }

    func testCompletedIdleAndPausedSnapshotsHaveStableRatios() {
        XCTAssertEqual(TimerProgressSnapshot(targetSeconds: 60, remainingSeconds: 0).ratio, 1)
        XCTAssertEqual(TimerProgressSnapshot(targetSeconds: 60, remainingSeconds: 60).ratio, 0)
        XCTAssertEqual(TimerProgressSnapshot(targetSeconds: 60, remainingSeconds: 45).ratio, 0.25)
    }

    func testRatioIncreasesAsRunningTaskRemainingTimeFalls() {
        let earlier = TimerProgressSnapshot(targetSeconds: 60, remainingSeconds: 45).ratio
        let later = TimerProgressSnapshot(targetSeconds: 60, remainingSeconds: 44).ratio

        XCTAssertGreaterThan(later, earlier)
    }
}
