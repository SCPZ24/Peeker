import XCTest
import PeekerCore
@testable import TimerFeature

final class TimerDomainTests: XCTestCase {
    func testTemplateRejectsBlankNameAndInvalidDuration() {
        XCTAssertThrowsError(try TimerTemplate(name: "  ", targetSeconds: 60, colorHex: "#FF0000", position: 0))
        XCTAssertThrowsError(try TimerTemplate(name: "Read", targetSeconds: 86_400, colorHex: "#FF0000", position: 0))
    }

    func testStartingSecondTaskWhileAnotherRunsIsRejected() throws {
        let day = makeDay()
        let first = try TimerTaskInstance(template: TimerTemplate(name: "Read", targetSeconds: 60, colorHex: "#00AAFF", position: 0), businessDayID: day.id)
        let second = try TimerTaskInstance(template: TimerTemplate(name: "Move", targetSeconds: 60, colorHex: "#22CC66", position: 1), businessDayID: day.id)
        var timer = TimerDayState(businessDay: day, tasks: [first, second])

        try timer.start(taskID: first.id, atMilliseconds: 1000)
        XCTAssertThrowsError(try timer.start(taskID: second.id, atMilliseconds: 2000))
    }

    func testPauseAccumulatesWallClockTimeAndCapsAtTarget() throws {
        let day = makeDay()
        let template = try TimerTemplate(name: "Read", targetSeconds: 10, colorHex: "#00AAFF", position: 0)
        let task = try TimerTaskInstance(template: template, businessDayID: day.id)
        var timer = TimerDayState(businessDay: day, tasks: [task])

        try timer.start(taskID: task.id, atMilliseconds: 1_000)
        let completion = try timer.pause(atMilliseconds: 21_000)

        XCTAssertEqual(timer.tasks[0].accumulatedSeconds, 10)
        XCTAssertEqual(timer.tasks[0].status, .completed)
        XCTAssertEqual(completion?.endReason, .targetReached)
    }

    private func makeDay() -> BusinessDay {
        BusinessDay(
            featureID: FeatureID(rawValue: "timer"),
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86_400)
        )
    }
}
