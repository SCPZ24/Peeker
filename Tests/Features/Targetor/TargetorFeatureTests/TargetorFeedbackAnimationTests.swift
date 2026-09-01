import XCTest
@testable import TargetorFeature

final class TargetorFeedbackAnimationTests: XCTestCase {
    func testStartedFeedbackFlashesOnlyBorderThenFades() {
        let initial = snapshot(state: .started, elapsed: 0)
        let held = snapshot(state: .started, elapsed: 0.12)
        let middle = snapshot(state: .started, elapsed: 0.5)
        let ending = snapshot(state: .started, elapsed: 0.9)

        XCTAssertEqual(initial.borderOpacity, 0.95, accuracy: 0.0001)
        XCTAssertEqual(held.borderOpacity, 0.95, accuracy: 0.0001)
        XCTAssertGreaterThan(held.borderOpacity, middle.borderOpacity)
        XCTAssertGreaterThan(middle.borderOpacity, ending.borderOpacity)
        XCTAssertEqual(initial.fillOpacity, 0)
        XCTAssertTrue(initial.bands.isEmpty)
        XCTAssertEqual(snapshot(state: .started, elapsed: 1), .empty)
    }

    func testProgressingFeedbackMovesTwoBandsLeftToRightWithStagger() throws {
        XCTAssertTrue(snapshot(state: .progressing, elapsed: 0.04).bands.isEmpty)

        let firstEarly = try band(index: 0, at: 0.15)
        let firstLater = try band(index: 0, at: 0.45)
        XCTAssertLessThan(firstEarly.center, firstLater.center)

        let beforeSecond = snapshot(state: .progressing, elapsed: 0.24)
        XCTAssertNil(beforeSecond.bands.first(where: { $0.index == 1 }))

        let overlapping = snapshot(state: .progressing, elapsed: 0.45)
        let first = try XCTUnwrap(overlapping.bands.first(where: { $0.index == 0 }))
        let second = try XCTUnwrap(overlapping.bands.first(where: { $0.index == 1 }))
        XCTAssertGreaterThan(first.center, second.center)
        XCTAssertGreaterThan(first.opacity, 0)
        XCTAssertGreaterThan(second.opacity, 0)

        for step in 0...100 {
            let value = snapshot(state: .progressing, elapsed: Double(step) / 100)
            XCTAssertEqual(value.borderOpacity, 0)
            XCTAssertEqual(value.fillOpacity, 0)
            for band in value.bands {
                XCTAssertTrue((-0.12...1.12).contains(band.center))
                XCTAssertTrue((0...0.78).contains(band.opacity))
            }
        }
        XCTAssertTrue(snapshot(state: .progressing, elapsed: 0.96).bands.isEmpty)
        XCTAssertEqual(snapshot(state: .progressing, elapsed: 1), .empty)
    }

    func testCompletedFeedbackFlashesOnlyFillThenFades() {
        let initial = snapshot(state: .completed, elapsed: 0)
        let held = snapshot(state: .completed, elapsed: 0.12)
        let middle = snapshot(state: .completed, elapsed: 0.5)
        let ending = snapshot(state: .completed, elapsed: 0.9)

        XCTAssertEqual(initial.fillOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(held.fillOpacity, 0.5, accuracy: 0.0001)
        XCTAssertGreaterThan(held.fillOpacity, middle.fillOpacity)
        XCTAssertGreaterThan(middle.fillOpacity, ending.fillOpacity)
        XCTAssertEqual(initial.borderOpacity, 0)
        XCTAssertTrue(initial.bands.isEmpty)
        XCTAssertEqual(snapshot(state: .completed, elapsed: 1), .empty)
    }

    func testReduceMotionUsesStaticHighlightAndFinalFadeWithoutBands() {
        for state in [TargetorCheckinState.started, .progressing, .completed] {
            let initial = snapshot(state: state, elapsed: 0, reduceMotion: true)
            let held = snapshot(state: state, elapsed: 0.7, reduceMotion: true)
            let fading = snapshot(state: state, elapsed: 0.85, reduceMotion: true)

            XCTAssertEqual(initial.borderOpacity, 0.8, accuracy: 0.0001)
            XCTAssertEqual(initial.fillOpacity, 0.16, accuracy: 0.0001)
            XCTAssertEqual(held, initial)
            XCTAssertGreaterThan(held.borderOpacity, fading.borderOpacity)
            XCTAssertGreaterThan(held.fillOpacity, fading.fillOpacity)
            XCTAssertTrue(initial.bands.isEmpty)
            XCTAssertTrue(fading.bands.isEmpty)
            XCTAssertEqual(snapshot(state: state, elapsed: 1, reduceMotion: true), .empty)
        }
    }

    func testOutOfRangeTimesAndNotStartedStateHaveNoEffect() {
        XCTAssertEqual(snapshot(state: .started, elapsed: -0.001), .empty)
        XCTAssertEqual(snapshot(state: .started, elapsed: 1.001), .empty)
        XCTAssertEqual(snapshot(state: .notStarted, elapsed: 0.5), .empty)
        XCTAssertEqual(TargetorFeedbackAnimation.duration, 1)
    }

    private func snapshot(
        state: TargetorCheckinState,
        elapsed: TimeInterval,
        reduceMotion: Bool = false
    ) -> TargetorFeedbackAnimationSnapshot {
        TargetorFeedbackAnimation.snapshot(
            state: state,
            elapsed: elapsed,
            reduceMotion: reduceMotion
        )
    }

    private func band(index: Int, at elapsed: TimeInterval) throws -> TargetorFeedbackBandSnapshot {
        try XCTUnwrap(
            snapshot(state: .progressing, elapsed: elapsed)
                .bands.first(where: { $0.index == index })
        )
    }
}
