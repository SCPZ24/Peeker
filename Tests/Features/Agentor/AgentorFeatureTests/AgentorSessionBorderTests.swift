import XCTest
@testable import AgentorFeature

final class AgentorSessionBorderTests: XCTestCase {
    func testNormalSweepMovesLeftToRightAndWraps() throws {
        let start = try XCTUnwrap(AgentorSessionBorderAnimation.normal(at: 0, phaseOffset: 0, reduceMotion: false).sweepProgress)
        let quarter = try XCTUnwrap(AgentorSessionBorderAnimation.normal(at: 0.8, phaseOffset: 0, reduceMotion: false).sweepProgress)
        let half = try XCTUnwrap(AgentorSessionBorderAnimation.normal(at: 1.6, phaseOffset: 0, reduceMotion: false).sweepProgress)
        let wrapped = try XCTUnwrap(AgentorSessionBorderAnimation.normal(at: 3.2, phaseOffset: 0, reduceMotion: false).sweepProgress)

        XCTAssertEqual(start, 0, accuracy: 0.0001)
        XCTAssertEqual(quarter, 0.25, accuracy: 0.0001)
        XCTAssertEqual(half, 0.5, accuracy: 0.0001)
        XCTAssertEqual(wrapped, 0, accuracy: 0.0001)
        XCTAssertLessThan(start, quarter)
        XCTAssertLessThan(quarter, half)
    }

    func testNormalIntensityStaysWithinSubtleRange() {
        for step in 0...64 {
            let metrics = AgentorSessionBorderAnimation.normal(
                at: Double(step) * AgentorSessionBorderAnimation.normalPeriod / 64,
                phaseOffset: 0,
                reduceMotion: false
            )
            XCTAssertNotNil(metrics.sweepProgress)
            XCTAssertTrue((0.38...0.72).contains(metrics.strokeOpacity))
            XCTAssertTrue((0.10...0.22).contains(metrics.glowOpacity))
        }
    }

    func testWaitingPulseContainsDarkBrightAndWrappedStates() {
        let dark = AgentorSessionBorderAnimation.waiting(at: 0, reduceMotion: false)
        let bright = AgentorSessionBorderAnimation.waiting(at: 0.9, reduceMotion: false)
        let wrapped = AgentorSessionBorderAnimation.waiting(at: 1.8, reduceMotion: false)

        XCTAssertEqual(dark.strokeOpacity, 0.38, accuracy: 0.0001)
        XCTAssertEqual(bright.strokeOpacity, 0.92, accuracy: 0.0001)
        XCTAssertEqual(wrapped.strokeOpacity, dark.strokeOpacity, accuracy: 0.0001)
        XCTAssertEqual(wrapped.glowOpacity, dark.glowOpacity, accuracy: 0.0001)
        XCTAssertGreaterThan(bright.glowOpacity, dark.glowOpacity)
    }

    func testGreenTransitionPhasesAndExpires() throws {
        let start = try XCTUnwrap(AgentorSessionBorderAnimation.transition(at: 0, reduceMotion: false))
        let appeared = try XCTUnwrap(AgentorSessionBorderAnimation.transition(at: 0.12, reduceMotion: false))
        let peak = try XCTUnwrap(AgentorSessionBorderAnimation.transition(at: 0.35, reduceMotion: false))
        let fading = try XCTUnwrap(AgentorSessionBorderAnimation.transition(at: 0.60, reduceMotion: false))

        XCTAssertEqual(start.strokeOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(appeared.strokeOpacity, 0.95, accuracy: 0.0001)
        XCTAssertEqual(peak.strokeOpacity, 0.95, accuracy: 0.0001)
        XCTAssertEqual(fading.strokeOpacity, 0.475, accuracy: 0.0001)
        XCTAssertEqual(fading.glowOpacity, 0.14, accuracy: 0.0001)
        XCTAssertNil(AgentorSessionBorderAnimation.transition(at: 0.85, reduceMotion: false))
    }

    func testTransitionPolicyOnlyFlashesForApprovedVisibleChanges() {
        XCTAssertTrue(AgentorSessionBorderTransitionPolicy.shouldFlash(from: .thinking, to: .runningTool))
        XCTAssertTrue(AgentorSessionBorderTransitionPolicy.shouldFlash(from: .runningTool, to: .thinking))
        XCTAssertTrue(AgentorSessionBorderTransitionPolicy.shouldFlash(from: .waitingForAnswer, to: .thinking))
        XCTAssertTrue(AgentorSessionBorderTransitionPolicy.shouldFlash(from: .waitingForAnswer, to: .runningTool))

        XCTAssertFalse(AgentorSessionBorderTransitionPolicy.shouldFlash(from: .thinking, to: .waitingForAnswer))
        XCTAssertFalse(AgentorSessionBorderTransitionPolicy.shouldFlash(from: .runningTool, to: .waitingForAnswer))
        XCTAssertFalse(AgentorSessionBorderTransitionPolicy.shouldFlash(from: .thinking, to: .thinking))
        XCTAssertFalse(AgentorSessionBorderTransitionPolicy.shouldFlash(from: nil, to: .thinking))
        XCTAssertFalse(AgentorSessionBorderTransitionPolicy.shouldFlash(
            from: .thinking, to: .runningTool, generationChanged: true
        ))
    }

    func testReduceMotionProducesStaticSnapshots() throws {
        let normal = AgentorSessionBorderAnimation.normal(at: 1.4, phaseOffset: 0.4, reduceMotion: true)
        let waiting = AgentorSessionBorderAnimation.waiting(at: 1.4, reduceMotion: true)
        let transition = try XCTUnwrap(AgentorSessionBorderAnimation.transition(at: 0.4, reduceMotion: true))

        XCTAssertNil(normal.sweepProgress)
        XCTAssertEqual(normal.strokeOpacity, 0)
        XCTAssertEqual(normal.glowOpacity, 0)
        XCTAssertEqual(waiting.strokeOpacity, 0.78)
        XCTAssertEqual(waiting.glowOpacity, 0)
        XCTAssertEqual(transition.strokeOpacity, 0.85)
        XCTAssertEqual(transition.glowOpacity, 0)
    }
}
