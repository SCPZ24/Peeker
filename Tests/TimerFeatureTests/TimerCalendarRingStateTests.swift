import XCTest
@testable import TimerFeature

final class TimerCalendarRingStateTests: XCTestCase {
    func testRingStateUsesExactColorAndCompletionBoundaries() {
        XCTAssertEqual(TimerCalendarRingState.recorded(ratio: 0), .progress(ratio: 0, color: .yellow))
        XCTAssertEqual(TimerCalendarRingState.recorded(ratio: 0.0001), .progress(ratio: 0.0001, color: .yellow))
        XCTAssertEqual(TimerCalendarRingState.recorded(ratio: 0.25), .progress(ratio: 0.25, color: .yellow))
        XCTAssertEqual(TimerCalendarRingState.recorded(ratio: 0.250001), .progress(ratio: 0.250001, color: .blue))
        XCTAssertEqual(TimerCalendarRingState.recorded(ratio: 0.999999), .progress(ratio: 0.999999, color: .blue))
        XCTAssertEqual(TimerCalendarRingState.recorded(ratio: 1), .completed)
    }

    func testRingStateClampsRatiosAndKeepsSemanticEmptyStatesDistinct() {
        XCTAssertEqual(TimerCalendarRingState.recorded(ratio: -1), .progress(ratio: 0, color: .yellow))
        XCTAssertEqual(TimerCalendarRingState.recorded(ratio: 2), .completed)
        XCTAssertEqual(TimerCalendarRingState.recorded(ratio: nil), .noTasks)
        XCTAssertEqual(TimerCalendarRingState.missing, .missing)
        XCTAssertEqual(TimerCalendarRingState.future, .future)
    }
}
