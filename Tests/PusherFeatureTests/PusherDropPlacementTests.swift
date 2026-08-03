import CoreGraphics
import Foundation
import XCTest
import PeekerCore
@testable import PusherFeature

final class PusherDropPlacementTests: XCTestCase {
    func testDragPayloadOnlyResolvesTaskFromItsCurrentBusinessDay() throws {
        let day = BusinessDay(
            featureID: .pusher,
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86_400)
        )
        let task = try PusherTask(title: "Task", urgency: .planning, businessDayID: day.id)
        let board = PusherBoard(businessDay: day, tasks: [task])

        XCTAssertEqual(
            PusherDragPayload(taskID: task.id, businessDayID: day.id).taskID(in: board),
            task.id
        )
        XCTAssertNil(
            PusherDragPayload(
                taskID: task.id,
                businessDayID: BusinessDayID(featureID: .pusher, startAtMilliseconds: 1)
            ).taskID(in: board)
        )
        XCTAssertNil(PusherDragPayload(taskID: UUID(), businessDayID: day.id).taskID(in: board))
    }

    func testEmptyColumnAlwaysUsesFirstInsertionSlot() {
        XCTAssertEqual(
            PusherDropPlacement.insertionIndex(locationY: 200, rows: [], taskCount: 0),
            0
        )
    }

    func testPlacementUsesVariableRowMidpointsAndClampsToVisibleSlots() {
        let rows = [
            PusherDropRow(taskIndex: 0, frame: CGRect(x: 0, y: 20, width: 180, height: 40)),
            PusherDropRow(taskIndex: 1, frame: CGRect(x: 0, y: 70, width: 180, height: 80)),
        ]

        XCTAssertEqual(PusherDropPlacement.insertionIndex(locationY: -50, rows: rows, taskCount: 2), 0)
        XCTAssertEqual(PusherDropPlacement.insertionIndex(locationY: 39, rows: rows, taskCount: 2), 0)
        XCTAssertEqual(PusherDropPlacement.insertionIndex(locationY: 40, rows: rows, taskCount: 2), 1)
        XCTAssertEqual(PusherDropPlacement.insertionIndex(locationY: 109, rows: rows, taskCount: 2), 1)
        XCTAssertEqual(PusherDropPlacement.insertionIndex(locationY: 110, rows: rows, taskCount: 2), 2)
        XCTAssertEqual(PusherDropPlacement.insertionIndex(locationY: 500, rows: rows, taskCount: 2), 2)
    }

    func testPlacementUsesOriginalIndexesForScrolledAndUnsortedRows() {
        let rows = [
            PusherDropRow(taskIndex: 4, frame: CGRect(x: 0, y: 90, width: 180, height: 40)),
            PusherDropRow(taskIndex: 2, frame: CGRect(x: 0, y: 10, width: 180, height: 40)),
            PusherDropRow(taskIndex: 3, frame: CGRect(x: 0, y: 50, width: 180, height: 40)),
        ]

        XCTAssertEqual(PusherDropPlacement.insertionIndex(locationY: 5, rows: rows, taskCount: 7), 2)
        XCTAssertEqual(PusherDropPlacement.insertionIndex(locationY: 69, rows: rows, taskCount: 7), 3)
        XCTAssertEqual(PusherDropPlacement.insertionIndex(locationY: 70, rows: rows, taskCount: 7), 4)
        XCTAssertEqual(PusherDropPlacement.insertionIndex(locationY: 999, rows: rows, taskCount: 7), 5)
    }
}
