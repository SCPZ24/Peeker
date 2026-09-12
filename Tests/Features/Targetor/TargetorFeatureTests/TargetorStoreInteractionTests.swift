import Foundation
import XCTest
import PeekerCore
@testable import TargetorFeature

@MainActor
final class TargetorStoreInteractionTests: XCTestCase {
    func testVisibleUICheckinPublishesOnlyInPlaceFeedbackAfterCommit() async throws {
        let fixture = try makeFixture()
        await fixture.store.load()

        let succeeded = await fixture.store.checkinFromUI(
            targetID: fixture.targetID,
            expectedPeriodID: fixture.periodID
        )

        XCTAssertTrue(succeeded)
        XCTAssertEqual(fixture.store.targets.first?.currentPeriod?.count, 1)
        XCTAssertEqual(fixture.store.feedback?.targetID, fixture.targetID)
        XCTAssertEqual(fixture.store.feedback?.state, .started)
        XCTAssertEqual(fixture.store.feedback?.startedAt, Date(timeIntervalSince1970: 3_600))
        XCTAssertEqual(fixture.prompts.values.count, 0)
        XCTAssertNil(fixture.store.errorMessage)
        let checkinCalls = await fixture.repository.checkinCallCount()
        XCTAssertEqual(checkinCalls, 1)
    }

    func testSuccessiveUICheckinsPublishUniqueFeedbackTokens() async throws {
        let fixture = try makeFixture()
        await fixture.store.load()

        let firstSucceeded = await fixture.store.checkinFromUI(
            targetID: fixture.targetID,
            expectedPeriodID: fixture.periodID
        )
        XCTAssertTrue(firstSucceeded)
        let firstToken = try XCTUnwrap(fixture.store.feedback?.token)

        let secondSucceeded = await fixture.store.checkinFromUI(
            targetID: fixture.targetID,
            expectedPeriodID: fixture.periodID
        )
        XCTAssertTrue(secondSucceeded)
        let secondToken = try XCTUnwrap(fixture.store.feedback?.token)

        XCTAssertNotEqual(firstToken, secondToken)
        XCTAssertEqual(fixture.store.feedback?.state, .completed)
        XCTAssertEqual(fixture.prompts.values.count, 0)
    }

    func testUICheckinFailureKeepsStateAndDoesNotPublishFeedbackOrPrompt() async throws {
        let fixture = try makeFixture(checkinError: StoreTestError.persistenceFailed)
        await fixture.store.load()

        let succeeded = await fixture.store.checkinFromUI(
            targetID: fixture.targetID,
            expectedPeriodID: fixture.periodID
        )

        XCTAssertFalse(succeeded)
        XCTAssertEqual(fixture.store.targets.first?.currentPeriod?.count, 0)
        XCTAssertNil(fixture.store.feedback)
        XCTAssertTrue(fixture.prompts.values.isEmpty)
        XCTAssertNotNil(fixture.store.errorMessage)
        let checkinCalls = await fixture.repository.checkinCallCount()
        XCTAssertEqual(checkinCalls, 1)
    }

    func testUICheckinRejectsStalePeriodBeforeRepositoryWrite() async throws {
        let fixture = try makeFixture()
        await fixture.store.load()

        let succeeded = await fixture.store.checkinFromUI(
            targetID: fixture.targetID,
            expectedPeriodID: UUID()
        )

        XCTAssertFalse(succeeded)
        XCTAssertEqual(fixture.store.targets.first?.currentPeriod?.count, 0)
        XCTAssertNil(fixture.store.feedback)
        XCTAssertTrue(fixture.prompts.values.isEmpty)
        XCTAssertNotNil(fixture.store.errorMessage)
        let checkinCalls = await fixture.repository.checkinCallCount()
        XCTAssertEqual(checkinCalls, 0)
    }

    func testHiddenUICheckinUsesPromptWithoutLocalCelebration() async throws {
        let fixture = try makeFixture()
        await fixture.store.load()
        fixture.store.isPresentationVisible = false
        let succeeded = await fixture.store.checkinFromUI(targetID: fixture.targetID, expectedPeriodID: fixture.periodID)
        XCTAssertTrue(succeeded)
        XCTAssertEqual(fixture.prompts.values.count, 1)
        XCTAssertNil(fixture.store.feedback)
    }

    private func makeFixture(
        checkinError: (any Error & Sendable)? = nil
    ) throws -> (
        store: TargetorStore,
        repository: StoreTestTargetorRepository,
        prompts: PromptRecorder,
        targetID: UUID,
        periodID: UUID
    ) {
        let target = try TargetorTarget(
            title: "Write",
            maxCount: 2,
            createdAtMilliseconds: 0,
            updatedAtMilliseconds: 0
        )
        let period = TargetorPeriod(
            targetID: target.id,
            sequence: 0,
            startMilliseconds: 0,
            endMilliseconds: 86_400_000,
            ruleSnapshot: .daily,
            maxCountSnapshot: 2,
            createdAtMilliseconds: 0
        )
        let repository = StoreTestTargetorRepository(
            state: TargetorTargetState(target: target, currentPeriod: period, lastPeriod: nil),
            checkinError: checkinError
        )
        let clock = StoreTestClock(date: Date(timeIntervalSince1970: 3_600))
        let prompts = PromptRecorder()
        let store = TargetorStore(
            repository: repository,
            clock: clock,
            eventHub: TemporalEventHub(clock: clock, scheduler: StoreNoopScheduler()),
            isValidIcon: { _ in true },
            publishCheckin: { prompts.values.append($0) }
        )
        store.isPresentationVisible = true
        return (store, repository, prompts, target.id, period.id)
    }
}

@MainActor
private final class PromptRecorder {
    var values: [TargetorCheckinResult] = []
}

private enum StoreTestError: Error, Sendable {
    case persistenceFailed
    case unsupported
}

private struct StoreTestClock: Clock {
    let date: Date
    func now() -> Date { date }
}

private actor StoreNoopScheduler: TemporalScheduling {
    func schedule(at date: Date, action: @escaping @Sendable () -> Void) async {}
    func cancelAll() async {}
}

private actor StoreTestTargetorRepository: TargetorRepository {
    private var state: TargetorTargetState
    private let checkinError: (any Error & Sendable)?
    private var checkinCalls = 0
    private var events: [TargetorCheckin] = []

    init(state: TargetorTargetState, checkinError: (any Error & Sendable)?) {
        self.state = state
        self.checkinError = checkinError
    }

    func recover(now: Date, refreshTime: RefreshTime, resolver: TargetorPeriodResolver) async throws {}

    func snapshot(scope: TargetorArchiveScope) async throws -> TargetorSnapshot {
        TargetorSnapshot(targets: [state])
    }

    func create(target: TargetorTarget, firstPeriod: TargetorPeriod) async throws {
        throw StoreTestError.unsupported
    }

    func update(
        target: TargetorTarget,
        replacingCurrentWith period: TargetorPeriod?,
        settleAtMilliseconds: Int64?
    ) async throws {
        throw StoreTestError.unsupported
    }

    func archive(targetID: UUID, atMilliseconds: Int64) async throws -> TargetorTargetState {
        throw StoreTestError.unsupported
    }

    func reorder(activeTargetIDs: [UUID], atMilliseconds: Int64) async throws {
        throw StoreTestError.unsupported
    }

    func checkin(
        targetID: UUID,
        eventID: UUID,
        atMilliseconds: Int64
    ) async throws -> TargetorCheckinResult {
        checkinCalls += 1
        if let checkinError { throw checkinError }
        guard state.id == targetID, let period = state.currentPeriod else {
            throw TargetorError.targetNotFound
        }
        let updatedPeriod = TargetorPeriod(
            id: period.id,
            targetID: period.targetID,
            sequence: period.sequence,
            startMilliseconds: period.startMilliseconds,
            endMilliseconds: period.endMilliseconds,
            ruleSnapshot: period.ruleSnapshot,
            maxCountSnapshot: period.maxCountSnapshot,
            createdAtMilliseconds: period.createdAtMilliseconds,
            settledAtMilliseconds: period.settledAtMilliseconds,
            count: period.count + 1
        )
        state = TargetorTargetState(
            target: state.target,
            currentPeriod: updatedPeriod,
            lastPeriod: state.lastPeriod
        )
        let event = TargetorCheckin(
            id: eventID,
            targetID: targetID,
            periodID: period.id,
            occurredAtMilliseconds: atMilliseconds
        )
        events.append(event)
        return TargetorCheckinResult(target: state, event: event)
    }

    func uncheck(eventID: UUID) async throws -> TargetorTargetState {
        throw StoreTestError.unsupported
    }

    func history(
        targetID: UUID,
        fromMilliseconds: Int64?,
        toMilliseconds: Int64?
    ) async throws -> TargetorHistory {
        guard state.id == targetID, let period = state.currentPeriod else {
            throw TargetorError.targetNotFound
        }
        return TargetorHistory(
            target: state.target,
            fromMilliseconds: fromMilliseconds ?? period.startMilliseconds,
            toMilliseconds: toMilliseconds ?? period.endMilliseconds,
            periods: [period],
            events: events
        )
    }

    func checkinCallCount() -> Int { checkinCalls }
}
