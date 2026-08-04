import AppKit
import Foundation
import XCTest
import PeekerCore
@testable import PusherFeature

@MainActor
final class PusherAppKitDragBridgeTests: XCTestCase {
    func testPolicyAcceptsOneLocalMoveInsideAColumn() throws {
        let fixture = try makeFixture()
        let snapshot = PusherDragSessionSnapshot(
            rawValue: fixture.envelope.rawValue,
            isLocal: true,
            itemCount: 1,
            sourceOperationMask: .move,
            location: CGPoint(x: 100, y: 100),
            draggedCardSize: CGSize(width: 180, height: 38)
        )

        let target = PusherDropSessionPolicy.target(
            for: snapshot,
            sessionNonce: fixture.nonce,
            board: fixture.board,
            columns: fixture.columns
        )

        XCTAssertEqual(target?.taskID, fixture.task.id)
        XCTAssertEqual(target?.status, .planned)
        XCTAssertEqual(target?.insertionIndex, 1)
        XCTAssertEqual(target?.landingFrame, CGRect(x: 10, y: 95, width: 180, height: 38))
    }

    func testPolicyRejectsExternalCopyMultipleMalformedAndOutsideDrops() throws {
        let fixture = try makeFixture()
        let valid = PusherDragSessionSnapshot(
            rawValue: fixture.envelope.rawValue,
            isLocal: true,
            itemCount: 1,
            sourceOperationMask: .move,
            location: CGPoint(x: 100, y: 100),
            draggedCardSize: nil
        )

        XCTAssertNil(target(valid, fixture: fixture, isLocal: false))
        XCTAssertNil(target(valid, fixture: fixture, itemCount: 2))
        XCTAssertNil(target(valid, fixture: fixture, operation: .copy))
        XCTAssertNil(target(valid, fixture: fixture, rawValue: "not-a-peeker-drag"))
        XCTAssertNil(target(valid, fixture: fixture, location: CGPoint(x: 205, y: 100)))
    }

    func testPolicyReportsActionableRejectionReasons() throws {
        let fixture = try makeFixture()
        let snapshot = PusherDragSessionSnapshot(
            rawValue: fixture.envelope.rawValue,
            isLocal: false,
            itemCount: 1,
            sourceOperationMask: .move,
            location: CGPoint(x: 100, y: 100),
            draggedCardSize: nil
        )
        XCTAssertEqual(
            PusherDropSessionPolicy.evaluate(
                snapshot,
                sessionNonce: fixture.nonce,
                board: fixture.board,
                columns: fixture.columns
            ),
            .rejected(.externalSource)
        )
        XCTAssertEqual(
            PusherDropSessionPolicy.evaluate(
                PusherDragSessionSnapshot(
                    rawValue: fixture.envelope.rawValue,
                    isLocal: true,
                    itemCount: 1,
                    sourceOperationMask: .move,
                    location: CGPoint(x: 205, y: 100),
                    draggedCardSize: nil
                ),
                sessionNonce: fixture.nonce,
                board: fixture.board,
                columns: fixture.columns
            ),
            .rejected(.outsideColumn)
        )
    }

    func testLayoutModelPublishesAndClearsActiveTarget() throws {
        let fixture = try makeFixture()
        let model = PusherDragLayoutModel()
        model.updateColumn(fixture.columns[0])
        XCTAssertEqual(model.columns, [fixture.columns[0]])

        let target = PusherResolvedDropTarget(
            taskID: fixture.task.id,
            status: .planned,
            insertionIndex: 1,
            landingFrame: CGRect(x: 10, y: 95, width: 180, height: 38)
        )
        model.setActiveTarget(target)
        XCTAssertEqual(model.activeTarget, target)
        model.clearActiveTarget()
        XCTAssertNil(model.activeTarget)
    }

    private func target(
        _ snapshot: PusherDragSessionSnapshot,
        fixture: Fixture,
        isLocal: Bool? = nil,
        itemCount: Int? = nil,
        operation: NSDragOperation? = nil,
        rawValue: String? = nil,
        location: CGPoint? = nil
    ) -> PusherResolvedDropTarget? {
        PusherDropSessionPolicy.target(
            for: PusherDragSessionSnapshot(
                rawValue: rawValue ?? snapshot.rawValue,
                isLocal: isLocal ?? snapshot.isLocal,
                itemCount: itemCount ?? snapshot.itemCount,
                sourceOperationMask: operation ?? snapshot.sourceOperationMask,
                location: location ?? snapshot.location,
                draggedCardSize: snapshot.draggedCardSize
            ),
            sessionNonce: fixture.nonce,
            board: fixture.board,
            columns: fixture.columns
        )
    }

    private func makeFixture() throws -> Fixture {
        let day = BusinessDay(
            featureID: .pusher,
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86_400)
        )
        let task = try PusherTask(title: "Task", urgency: .urgent, businessDayID: day.id)
        let board = PusherBoard(businessDay: day, tasks: [task])
        let nonce = UUID()
        return Fixture(
            nonce: nonce,
            task: task,
            board: board,
            envelope: PusherDragEnvelope(
                sessionNonce: nonce,
                businessDayStart: day.id.startAtMilliseconds,
                taskID: task.id
            ),
            columns: [
                PusherDropColumnGeometry(
                    status: .planned,
                    frame: CGRect(x: 0, y: 0, width: 200, height: 400),
                    rows: [
                        PusherDropRow(taskIndex: 0, frame: CGRect(x: 10, y: 50, width: 180, height: 38)),
                        PusherDropRow(taskIndex: 1, frame: CGRect(x: 10, y: 95, width: 180, height: 38)),
                    ],
                    taskCount: 2
                ),
            ]
        )
    }
}

private struct Fixture {
    let nonce: UUID
    let task: PusherTask
    let board: PusherBoard
    let envelope: PusherDragEnvelope
    let columns: [PusherDropColumnGeometry]
}
