import CoreGraphics
import Foundation
import XCTest
import PeekerCore
@testable import PusherFeature

final class PusherDropPlacementTests: XCTestCase {
    func testDragEnvelopeRoundTripsAndOnlyResolvesCurrentSessionTask() throws {
        let day = BusinessDay(
            featureID: .pusher,
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86_400)
        )
        let task = try PusherTask(title: "Task", urgency: .planning, businessDayID: day.id)
        let board = PusherBoard(businessDay: day, tasks: [task])
        let nonce = UUID()
        let envelope = PusherDragEnvelope(
            sessionNonce: nonce,
            businessDayStart: day.id.startAtMilliseconds,
            taskID: task.id
        )
        let decoded = try XCTUnwrap(PusherDragEnvelope(rawValue: envelope.rawValue))

        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(decoded.taskID(in: board, sessionNonce: nonce), task.id)
        XCTAssertNil(decoded.taskID(in: board, sessionNonce: UUID()))
        XCTAssertNil(
            PusherDragEnvelope(
                sessionNonce: nonce,
                businessDayStart: 1,
                taskID: task.id
            ).taskID(in: board, sessionNonce: nonce)
        )
        XCTAssertNil(
            PusherDragEnvelope(
                sessionNonce: nonce,
                businessDayStart: day.id.startAtMilliseconds,
                taskID: UUID()
            ).taskID(in: board, sessionNonce: nonce)
        )
    }

    func testDragEnvelopeRejectsMalformedAndUnknownVersions() {
        XCTAssertNil(PusherDragEnvelope(rawValue: ""))
        XCTAssertNil(PusherDragEnvelope(rawValue: "peeker-pusher-drag:v2:a:b:c"))
        XCTAssertNil(PusherDragEnvelope(rawValue: "peeker-pusher-drag:v1:not-a-uuid:0:not-a-uuid"))
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

    func testDropGeometryResolvesColumnSlotAndLandingFrame() throws {
        let columns = [
            PusherDropColumnGeometry(
                status: .planned,
                frame: CGRect(x: 0, y: 0, width: 200, height: 400),
                rows: [
                    PusherDropRow(taskIndex: 0, frame: CGRect(x: 10, y: 50, width: 180, height: 38)),
                    PusherDropRow(taskIndex: 1, frame: CGRect(x: 10, y: 95, width: 180, height: 52)),
                ],
                taskCount: 2
            ),
            PusherDropColumnGeometry(
                status: .processing,
                frame: CGRect(x: 210, y: 0, width: 200, height: 400),
                rows: [],
                taskCount: 0
            ),
        ]

        let planned = try XCTUnwrap(
            PusherDropGeometry.target(
                location: CGPoint(x: 100, y: 120),
                columns: columns,
                draggedCardSize: CGSize(width: 180, height: 38)
            )
        )
        XCTAssertEqual(planned.status, .planned)
        XCTAssertEqual(planned.insertionIndex, 1)
        XCTAssertEqual(planned.landingFrame, CGRect(x: 10, y: 95, width: 180, height: 38))

        let processing = try XCTUnwrap(
            PusherDropGeometry.target(
                location: CGPoint(x: 300, y: 200),
                columns: columns,
                draggedCardSize: CGSize(width: 180, height: 44)
            )
        )
        XCTAssertEqual(processing.status, .processing)
        XCTAssertEqual(processing.insertionIndex, 0)
        XCTAssertEqual(processing.landingFrame, CGRect(x: 220, y: 40, width: 180, height: 44))
        XCTAssertNil(
            PusherDropGeometry.target(
                location: CGPoint(x: 205, y: 100),
                columns: columns,
                draggedCardSize: nil
            )
        )
    }
}
