import XCTest
import PeekerCore
@testable import PusherFeature

final class PusherDomainTests: XCTestCase {
    func testTaskRejectsBlankTitle() {
        XCTAssertThrowsError(try PusherTask(title: "  ", urgency: .planning, businessDayID: makeDay().id))
    }

    func testNewTaskIsAppendedToPlannedColumn() throws {
        var board = PusherBoard(businessDay: makeDay(), tasks: [])
        let task = try PusherTask(title: "Ship", urgency: .urgent, businessDayID: board.businessDay.id)

        try board.insert(task)

        XCTAssertEqual(board.tasks(in: .planned).map(\.id), [task.id])
        XCTAssertEqual(board.tasks(in: .planned)[0].position, 0)
    }

    func testMoveChangesStatusAndNormalizesBothColumns() throws {
        var board = PusherBoard(businessDay: makeDay(), tasks: [])
        let a = try PusherTask(title: "A", urgency: .planning, businessDayID: board.businessDay.id)
        let b = try PusherTask(title: "B", urgency: .progress, businessDayID: board.businessDay.id)
        try board.insert(a)
        try board.insert(b)

        try board.move(taskID: a.id, to: .processing, at: 0)

        XCTAssertEqual(board.tasks(in: .planned).map(\.position), [0])
        XCTAssertEqual(board.tasks(in: .processing).map(\.id), [a.id])
        XCTAssertEqual(board.summary, PusherSummary(planned: 1, processing: 1, done: 0))
    }

    func testCompactSummaryBreaksDownUrgencyOnlyInsideProcessing() throws {
        let day = makeDay()
        let tasks = [
            try PusherTask(title: "Planned urgent", urgency: .urgent, status: .planned, businessDayID: day.id),
            try PusherTask(title: "Processing urgent", urgency: .urgent, status: .processing, businessDayID: day.id),
            try PusherTask(title: "Processing progress", urgency: .progress, status: .processing, businessDayID: day.id),
            try PusherTask(title: "Processing planning", urgency: .planning, status: .processing, businessDayID: day.id),
            try PusherTask(title: "Done planning", urgency: .planning, status: .done, businessDayID: day.id),
        ]
        let board = PusherBoard(businessDay: day, tasks: tasks)

        XCTAssertEqual(
            board.compactSummary,
            PusherCompactSummary(
                planned: 1,
                processing: 3,
                done: 1,
                urgentProcessing: 1,
                progressProcessing: 1,
                planningProcessing: 1
            )
        )
    }

    func testCompactSummaryIsAllZeroForAnEmptyBoard() {
        let board = PusherBoard(businessDay: makeDay(), tasks: [])

        XCTAssertEqual(
            board.compactSummary,
            PusherCompactSummary(
                planned: 0,
                processing: 0,
                done: 0,
                urgentProcessing: 0,
                progressProcessing: 0,
                planningProcessing: 0
            )
        )
    }

    func testCompactSummaryUpdatesAfterMovingATaskIntoProcessing() throws {
        let day = makeDay()
        let task = try PusherTask(
            title: "Ship",
            urgency: .urgent,
            status: .planned,
            businessDayID: day.id
        )
        var board = PusherBoard(businessDay: day, tasks: [task])

        try board.move(taskID: task.id, to: .processing, at: 0)

        XCTAssertEqual(board.compactSummary.processing, 1)
        XCTAssertEqual(board.compactSummary.urgentProcessing, 1)
        XCTAssertEqual(
            board.compactSummary.urgentProcessing
                + board.compactSummary.progressProcessing
                + board.compactSummary.planningProcessing,
            board.compactSummary.processing
        )
    }

    func testCompactSummaryUpdatesAfterInsertionAndDeletion() throws {
        let day = makeDay()
        var board = PusherBoard(businessDay: day, tasks: [])
        let task = try PusherTask(
            title: "Advance",
            urgency: .progress,
            status: .planned,
            businessDayID: day.id
        )

        try board.insert(task)
        XCTAssertEqual(board.compactSummary.planned, 1)

        try board.move(taskID: task.id, to: .processing, at: 0)
        XCTAssertEqual(board.compactSummary.processing, 1)
        XCTAssertEqual(board.compactSummary.progressProcessing, 1)

        try board.remove(taskID: task.id)
        XCTAssertEqual(board.compactSummary, .zero)
    }

    func testSettlementRecreatesDailyTaskAndCarriesOnlyIncompleteOneTimeTasks() throws {
        let oldDay = makeDay()
        let nextDay = BusinessDay(
            featureID: .pusher,
            start: oldDay.end,
            end: oldDay.end.addingTimeInterval(86_400)
        )
        var daily = try PusherTask(title: "Daily", urgency: .planning, status: .done, businessDayID: oldDay.id)
        daily.setRepeatsDaily(true)
        let carried = try PusherTask(title: "Carry", urgency: .progress, status: .processing, businessDayID: oldDay.id)
        let finished = try PusherTask(title: "Finished", urgency: .urgent, status: .done, businessDayID: oldDay.id)
        let board = PusherBoard(businessDay: oldDay, tasks: [daily, carried, finished])

        let settlement = PusherSettlement.settle(
            board,
            into: nextDay,
            carryIncomplete: true,
            atMilliseconds: oldDay.end.millisecondsSince1970
        )

        XCTAssertEqual(settlement.snapshot.doneCount, 2)
        XCTAssertEqual(Set(settlement.nextBoard.allTasks.map(\.title)), Set(["Daily", "Carry"]))
        XCTAssertEqual(settlement.nextBoard.allTasks.first(where: { $0.title == "Daily" })?.status, .planned)
    }

    private func makeDay() -> BusinessDay {
        BusinessDay(
            featureID: FeatureID(rawValue: "pusher"),
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86_400)
        )
    }
}
