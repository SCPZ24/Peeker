import XCTest
import PeekerCore
@testable import TimerFeature

final class TimerTemporaryDomainTests: XCTestCase {
    func testDailyAndTemporaryTasksShareOneRunningSession() throws {
        let day = BusinessDay(
            featureID: .timer,
            start: Date(millisecondsSince1970: 0),
            end: Date(millisecondsSince1970: 86_400_000)
        )
        let template = try TimerTemplate(name: "Daily", targetSeconds: 60, colorHex: "#4F9DFF", position: 0)
        let daily = try TimerTaskInstance(template: template, businessDayID: day.id)
        let temporary = try TimerTemporaryTask(name: "Temp", targetSeconds: 60, colorHex: "#4F9DFF")
        var state = TimerDayState(businessDay: day, tasks: [daily], temporaryTasks: [temporary])

        try state.start(identity: .temporary(taskID: temporary.id), atMilliseconds: 1_000)

        XCTAssertEqual(state.activeSession?.taskKind, .temporary)
        XCTAssertThrowsError(try state.start(taskID: daily.id, atMilliseconds: 2_000)) {
            XCTAssertEqual($0 as? TimerDomainError, .anotherTaskIsRunning)
        }
    }

    func testTemporaryPauseCreditsWallClockAndPreservesIdentity() throws {
        let day = BusinessDay(featureID: .timer, start: Date(millisecondsSince1970: 0), end: Date(millisecondsSince1970: 100_000))
        let task = try TimerTemporaryTask(name: "Temp", targetSeconds: 10, colorHex: "#34C759")
        var state = TimerDayState(businessDay: day, tasks: [], temporaryTasks: [task])
        try state.start(identity: .temporary(taskID: task.id), atMilliseconds: 1_000)

        let completion = try state.pause(atMilliseconds: 5_500)

        XCTAssertEqual(completion?.creditedSeconds, 4)
        XCTAssertEqual(completion?.session.identity, .temporary(taskID: task.id))
        XCTAssertEqual(state.temporaryTasks.first?.accumulatedSeconds, 4)
        XCTAssertEqual(state.temporaryTasks.first?.status, .paused)
    }

    func testTemporaryTaskRequiresPresetColor() {
        XCTAssertThrowsError(try TimerTemporaryTask(
            name: "Temp", targetSeconds: 60, colorHex: "#123456"
        )) { XCTAssertEqual($0 as? TimerDomainError, .invalidPresetColor) }
    }
}
