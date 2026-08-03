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
