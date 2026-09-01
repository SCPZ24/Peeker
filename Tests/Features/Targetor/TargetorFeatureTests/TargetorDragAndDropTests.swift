import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import TargetorFeature

@MainActor
final class TargetorDragAndDropTests: XCTestCase {
    private let dropFrame = CGRect(x: 620, y: 0, width: 190, height: 340)

    func testEnvelopeRoundTripsAndRejectsMalformedValues() {
        let envelope = TargetorDragEnvelope(
            expansionNonce: UUID(),
            targetID: UUID(),
            periodID: UUID()
        )

        XCTAssertEqual(TargetorDragEnvelope(rawValue: envelope.rawValue), envelope)
        XCTAssertNil(TargetorDragEnvelope(rawValue: "peeker-targetor-checkin:v1:broken"))
        XCTAssertNil(TargetorDragEnvelope(rawValue: envelope.rawValue.replacingOccurrences(of: ":v1:", with: ":v2:")))
    }

    func testPolicyAcceptsLocalCopyWithoutSwiftUIDragState() throws {
        let fixture = try makeFixture(count: 1, maxCount: 3)

        XCTAssertEqual(
            evaluate(fixture: fixture),
            .accepted(fixture.envelope)
        )
    }

    func testPolicyAcceptsEntireRightColumn() throws {
        let fixture = try makeFixture(count: 1, maxCount: 3)

        for location in [
            CGPoint(x: dropFrame.midX, y: dropFrame.minY + 1),
            CGPoint(x: dropFrame.midX, y: dropFrame.midY),
            CGPoint(x: dropFrame.midX, y: dropFrame.maxY - 1),
        ] {
            XCTAssertEqual(
                evaluate(fixture: fixture, location: location),
                .accepted(fixture.envelope)
            )
        }
    }

    func testPolicyRejectsOutsideRightColumn() throws {
        let fixture = try makeFixture(count: 1, maxCount: 3)

        for location in [
            CGPoint(x: dropFrame.minX - 1, y: dropFrame.midY),
            CGPoint(x: dropFrame.maxX + 1, y: dropFrame.midY),
            CGPoint(x: dropFrame.midX, y: dropFrame.maxY + 1),
        ] {
            XCTAssertEqual(
                evaluate(fixture: fixture, location: location),
                .rejected(.outsideDropArea)
            )
        }
    }

    func testPolicyRejectsInvalidOrStaleSessions() throws {
        let fixture = try makeFixture(count: 1, maxCount: 3)

        XCTAssertEqual(evaluate(fixture: fixture, isLocal: false), .rejected(.externalSource))
        XCTAssertEqual(evaluate(fixture: fixture, itemCount: 2), .rejected(.multipleItems))
        XCTAssertEqual(evaluate(fixture: fixture, operation: .move), .rejected(.copyUnsupported))
        XCTAssertEqual(evaluate(fixture: fixture, rawValue: "broken"), .rejected(.malformedPayload))
        XCTAssertEqual(
            evaluate(fixture: fixture, expansionNonce: UUID()),
            .rejected(.staleExpansion)
        )
        XCTAssertEqual(
            evaluate(fixture: fixture, targets: []),
            .rejected(.missingTarget)
        )

        let stale = TargetorDragEnvelope(
            expansionNonce: fixture.envelope.expansionNonce,
            targetID: fixture.envelope.targetID,
            periodID: UUID()
        )
        XCTAssertEqual(
            evaluate(fixture: fixture, rawValue: stale.rawValue),
            .rejected(.stalePeriod)
        )
    }

    func testPolicyRejectsCompletedTargets() throws {
        let fixture = try makeFixture(count: 2, maxCount: 2)
        XCTAssertEqual(evaluate(fixture: fixture), .rejected(.completedTarget))
    }

    func testDraggingSequenceGateAllowsOneCommitPerSession() {
        var gate = TargetorDraggingSequenceGate()

        XCTAssertTrue(gate.reserve(41))
        XCTAssertFalse(gate.reserve(41))
        XCTAssertTrue(gate.reserve(42))

        gate.release(42)
        XCTAssertTrue(gate.reserve(42))

        gate.reset()
        XCTAssertTrue(gate.reserve(41))
    }

    func testLayoutModelPublishesGeometryAndClearsTarget() throws {
        let fixture = try makeFixture(count: 0, maxCount: 2)
        let model = TargetorDragLayoutModel()

        model.updateDropFrame(dropFrame)
        XCTAssertEqual(model.dropFrame, dropFrame)

        model.setTargetedEnvelope(fixture.envelope)
        XCTAssertEqual(model.targetedEnvelope, fixture.envelope)

        model.clearTargetedEnvelope()
        XCTAssertNil(model.targetedEnvelope)
    }

    func testContainerResetAndExpansionChangeClearTargetedState() throws {
        let fixture = try makeFixture(count: 0, maxCount: 2)
        let model = TargetorDragLayoutModel()
        let container = TargetorDropContainerView(rootView: AnyView(EmptyView()))
        container.layoutModel = model

        model.setTargetedEnvelope(fixture.envelope)
        container.resetTargetedState()
        XCTAssertNil(model.targetedEnvelope)

        model.setTargetedEnvelope(fixture.envelope)
        container.updateExpansionNonce(UUID())
        XCTAssertNil(model.targetedEnvelope)
    }

    func testExpansionHoldSurvivesDragEndUntilFeedbackFinishes() {
        var published: [Bool] = []
        let controller = TargetorExpansionHoldController()
        controller.attach { published.append($0) }

        controller.dragBegan()
        controller.dropAccepted()
        controller.dragEnded()
        XCTAssertTrue(controller.blocksCollapse)
        XCTAssertTrue(controller.isCheckinPending)
        XCTAssertEqual(published, [true])

        controller.checkinCompleted(feedbackVisible: true)
        XCTAssertTrue(controller.blocksCollapse)
        XCTAssertFalse(controller.isCheckinPending)
        XCTAssertEqual(published, [true])

        controller.feedbackChanged(isVisible: false)
        XCTAssertFalse(controller.blocksCollapse)
        XCTAssertEqual(published, [true, false])
    }

    func testExpansionHoldReleasesAfterFailedCheckinOrCancelledDrag() {
        var failedDropValues: [Bool] = []
        let failedDrop = TargetorExpansionHoldController()
        failedDrop.attach { failedDropValues.append($0) }
        failedDrop.dragBegan()
        failedDrop.dropAccepted()
        failedDrop.dragEnded()
        failedDrop.checkinCompleted(feedbackVisible: false)
        XCTAssertEqual(failedDropValues, [true, false])
        XCTAssertFalse(failedDrop.blocksCollapse)

        var cancelledDragValues: [Bool] = []
        let cancelledDrag = TargetorExpansionHoldController()
        cancelledDrag.attach { cancelledDragValues.append($0) }
        cancelledDrag.dragBegan()
        cancelledDrag.dragEnded()
        XCTAssertEqual(cancelledDragValues, [true, false])
        XCTAssertFalse(cancelledDrag.isCheckinPending)
    }

    func testExpansionHoldDetachIgnoresLateCompletionAndDeduplicatesPublishing() {
        var published: [Bool] = []
        let controller = TargetorExpansionHoldController()
        controller.attach { published.append($0) }

        controller.dragBegan()
        controller.dragBegan()
        controller.dropAccepted()
        controller.dragEnded()
        controller.detach()
        controller.checkinCompleted(feedbackVisible: true)
        controller.feedbackChanged(isVisible: true)

        XCTAssertEqual(published, [true, false])
        XCTAssertFalse(controller.blocksCollapse)
        XCTAssertFalse(controller.isCheckinPending)
    }

    func testSidePanelModePriorityAndFallback() throws {
        let fixture = try makeFixture(count: 0, maxCount: 2)
        let hoveredID = UUID()
        let feedback = TargetorFeedback(
            targetID: fixture.envelope.targetID,
            state: .started,
            token: UUID(),
            startedAt: Date()
        )

        XCTAssertEqual(
            TargetorSidePanelMode.resolve(
                feedback: feedback,
                activeEnvelope: fixture.envelope,
                hoveredTargetID: hoveredID
            ),
            .feedback(feedback)
        )
        XCTAssertEqual(
            TargetorSidePanelMode.resolve(
                feedback: nil,
                activeEnvelope: fixture.envelope,
                hoveredTargetID: hoveredID
            ),
            .dragging(fixture.envelope.targetID)
        )
        XCTAssertEqual(
            TargetorSidePanelMode.resolve(
                feedback: nil,
                activeEnvelope: nil,
                hoveredTargetID: hoveredID
            ),
            .target(hoveredID)
        )
        XCTAssertEqual(
            TargetorSidePanelMode.resolve(
                feedback: nil,
                activeEnvelope: nil,
                hoveredTargetID: nil
            ),
            .summary
        )
    }

    private func evaluate(
        fixture: Fixture,
        isLocal: Bool = true,
        itemCount: Int = 1,
        operation: NSDragOperation = .copy,
        rawValue: String? = nil,
        expansionNonce: UUID? = nil,
        targets: [TargetorTargetState]? = nil,
        location: CGPoint? = nil
    ) -> TargetorDropEvaluation {
        TargetorDropSessionPolicy.evaluate(
            TargetorDragSessionSnapshot(
                rawValue: rawValue ?? fixture.envelope.rawValue,
                isLocal: isLocal,
                itemCount: itemCount,
                sourceOperationMask: operation,
                location: location ?? CGPoint(x: dropFrame.midX, y: dropFrame.midY)
            ),
            expansionNonce: expansionNonce ?? fixture.envelope.expansionNonce,
            targets: targets ?? [fixture.target],
            dropFrame: dropFrame
        )
    }

    private func makeFixture(count: Int, maxCount: Int) throws -> Fixture {
        let target = try TargetorTarget(title: "Write", maxCount: maxCount)
        let period = TargetorPeriod(
            targetID: target.id,
            sequence: 0,
            startMilliseconds: 0,
            endMilliseconds: 86_400_000,
            ruleSnapshot: target.periodRule,
            maxCountSnapshot: maxCount,
            createdAtMilliseconds: 0,
            count: count
        )
        let state = TargetorTargetState(target: target, currentPeriod: period, lastPeriod: nil)
        let envelope = TargetorDragEnvelope(
            expansionNonce: UUID(),
            targetID: target.id,
            periodID: period.id
        )
        return Fixture(target: state, envelope: envelope)
    }
}

private struct Fixture {
    let target: TargetorTargetState
    let envelope: TargetorDragEnvelope
}
