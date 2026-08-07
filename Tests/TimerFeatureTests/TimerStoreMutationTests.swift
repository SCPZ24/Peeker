import Foundation
import XCTest
import PeekerCore
@testable import TimerFeature

@MainActor
final class TimerStoreMutationTests: XCTestCase {
    func testBoundaryWaitsForSuspendedStartAndAdvancesThePublishedSession() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = BusinessDay(
            featureID: .timer,
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86_400)
        )
        let template = try TimerTemplate(
            name: "Exercise",
            targetSeconds: 600,
            colorHex: "#1685FF",
            position: 0
        )
        let task = try TimerTaskInstance(template: template, businessDayID: day.id)
        let repository = SuspendedStartTimerRepository(
            template: template,
            state: TimerDayState(businessDay: day, tasks: [task])
        )
        let clock = TimerMutableClock(date: day.end.addingTimeInterval(-30))
        let store = TimerStore(
            repository: repository,
            clock: clock,
            resolver: BusinessDayResolver(calendar: calendar),
            eventHub: TemporalEventHub(clock: clock, scheduler: TimerNoopScheduler()),
            audio: TimerSilentAudio()
        )
        await store.load()

        let startTask = Task { await store.start(taskID: task.id) }
        await repository.waitForCommitStart()
        clock.set(day.end.addingTimeInterval(1))
        let wakeTask = Task { await store.handleWake() }
        await Task.yield()
        let countWhileStartIsSuspended = await repository.advanceCount()
        XCTAssertEqual(countWhileStartIsSuspended, 0)

        await repository.releaseCommitStart()
        await startTask.value
        await wakeTask.value

        let finalAdvanceCount = await repository.advanceCount()
        XCTAssertEqual(finalAdvanceCount, 1)
        XCTAssertEqual(store.dayState?.businessDay.start, day.end)
        XCTAssertNotNil(store.dayState?.activeSession)
    }

    func testPauseAfterBoundaryRecoversBeforeClosingTheCurrentSession() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = BusinessDay(
            featureID: .timer,
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86_400)
        )
        let template = try TimerTemplate(
            name: "Exercise",
            targetSeconds: 600,
            colorHex: "#1685FF",
            position: 0
        )
        let task = try TimerTaskInstance(template: template, businessDayID: day.id)
        let repository = SuspendedStartTimerRepository(
            template: template,
            state: TimerDayState(businessDay: day, tasks: [task])
        )
        let clock = TimerMutableClock(date: day.end.addingTimeInterval(-30))
        let store = TimerStore(
            repository: repository,
            clock: clock,
            resolver: BusinessDayResolver(calendar: calendar),
            eventHub: TemporalEventHub(clock: clock, scheduler: TimerNoopScheduler()),
            audio: TimerSilentAudio()
        )
        await store.load()

        let startTask = Task { await store.start(taskID: task.id) }
        await repository.waitForCommitStart()
        await repository.releaseCommitStart()
        await startTask.value

        let pauseDate = day.end.addingTimeInterval(5)
        clock.set(pauseDate)
        try await store.pause()

        let completions = await repository.recordedCompletions()
        XCTAssertEqual(store.dayState?.businessDay.start, day.end)
        XCTAssertNil(store.dayState?.activeSession)
        XCTAssertEqual(completions.map(\.endReason), [.businessDayBoundary, .paused])
        XCTAssertEqual(completions.map(\.endedAtMilliseconds), [
            day.end.millisecondsSince1970,
            pauseDate.millisecondsSince1970,
        ])
        XCTAssertEqual(try XCTUnwrap(completions.first).session.businessDayID, day.id)
        XCTAssertEqual(try XCTUnwrap(completions.last).session.businessDayID, store.dayState?.businessDay.id)
    }
}

private actor SuspendedStartTimerRepository: TimerRepository {
    private let template: TimerTemplate
    private var state: TimerDayState
    private var snapshots: [TimerDailySnapshot] = []
    private var completions: [TimerSessionCompletion] = []
    private var advanceCalls = 0
    private var commitStartBegan = false
    private var commitStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var commitStartRelease: CheckedContinuation<Void, Never>?

    init(template: TimerTemplate, state: TimerDayState) {
        self.template = template
        self.state = state
    }

    func loadOrBootstrapCurrentDay(resolvedToday: BusinessDay) async throws -> TimerDayState { state }

    func advanceDay(_ transition: TimerDayTransition) async throws -> TimerDayState {
        advanceCalls += 1
        snapshots.append(transition.snapshot)
        if let completion = transition.completion { completions.append(completion) }
        let nextTask = try TimerTaskInstance(template: template, businessDayID: transition.nextDay.id)
        var next = TimerDayState(businessDay: transition.nextDay, tasks: [nextTask])
        if transition.continuingTemplateID == template.id {
            try next.start(taskID: nextTask.id, atMilliseconds: transition.boundaryMilliseconds)
        }
        state = next
        return next
    }

    func updateCurrentBusinessDay(_ day: BusinessDay) async throws {
        state = TimerDayState(businessDay: day, tasks: state.tasks, activeSession: state.activeSession)
    }

    func loadTemplates() async throws -> [TimerTemplate] { [template] }
    func saveTemplate(_ template: TimerTemplate) async throws {}
    func deleteTemplate(id: UUID) async throws {}
    func loadOrCreateDay(_ day: BusinessDay) async throws -> TimerDayState { state }
    func saveDay(_ state: TimerDayState) async throws { self.state = state }
    func beginSession(_ session: TimerSession) async throws {}

    func commitStart(state: TimerDayState, session: TimerSession) async throws {
        commitStartBegan = true
        let waiters = commitStartWaiters
        commitStartWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            commitStartRelease = continuation
        }
        self.state = state
    }

    func completeSession(_ completion: TimerSessionCompletion) async throws {}
    func interruptSession(_ interruption: TimerSessionInterruption) async throws {}
    func commitCompletion(state: TimerDayState, completion: TimerSessionCompletion) async throws {
        completions.append(completion)
        self.state = state
    }

    func loadSnapshots(
        from startMilliseconds: Int64,
        to endMilliseconds: Int64
    ) async throws -> [TimerDailySnapshot] {
        snapshots
    }

    func waitForCommitStart() async {
        guard !commitStartBegan else { return }
        await withCheckedContinuation { continuation in
            commitStartWaiters.append(continuation)
        }
    }

    func releaseCommitStart() {
        commitStartRelease?.resume()
        commitStartRelease = nil
    }

    func advanceCount() -> Int { advanceCalls }
    func recordedCompletions() -> [TimerSessionCompletion] { completions }
}

private final class TimerMutableClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(date: Date) { self.date = date }
    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }
    func set(_ date: Date) {
        lock.lock()
        self.date = date
        lock.unlock()
    }
}

private actor TimerNoopScheduler: TemporalScheduling {
    func schedule(at date: Date, action: @escaping @Sendable () -> Void) async {}
    func cancelAll() async {}
}

private actor TimerSilentAudio: AudioNotifying {
    func playCompletionSound() async {}
}
