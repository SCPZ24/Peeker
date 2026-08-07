import Foundation
import XCTest
import PeekerCore
@testable import PusherFeature

@MainActor
final class PusherStoreMoveTests: XCTestCase {
    func testBeginMoveUpdatesBoardBeforePersistenceAndPersistsAfterBoard() async throws {
        let fixture = try makeFixture()
        await fixture.store.load()

        let transaction = try startedTransaction(
            fixture.store.beginMove(taskID: fixture.first.id, to: .processing, insertionIndex: 0)
        )

        XCTAssertEqual(fixture.store.board?.tasks(in: .processing).map(\.id), [fixture.first.id])
        XCTAssertTrue(fixture.store.isMovePending)
        let countBeforePersistence = await fixture.repository.reorderCount()
        XCTAssertEqual(countBeforePersistence, 0)

        await fixture.store.persistMove(transaction)

        XCTAssertFalse(fixture.store.isMovePending)
        let countAfterPersistence = await fixture.repository.reorderCount()
        let persistedBoard = await fixture.repository.lastReorderedBoard()
        XCTAssertEqual(countAfterPersistence, 1)
        XCTAssertEqual(persistedBoard?.tasks(in: .processing).map(\.id), [fixture.first.id])
    }

    func testPersistenceFailureRestoresExactBoardAndCompactSummary() async throws {
        let fixture = try makeFixture(reorderError: TestMoveError.persistenceFailed)
        await fixture.store.load()
        let original = try XCTUnwrap(fixture.store.board)
        let originalSummary = original.compactSummary
        let transaction = try startedTransaction(
            fixture.store.beginMove(taskID: fixture.first.id, to: .processing, insertionIndex: 0)
        )

        await fixture.store.persistMove(transaction)

        XCTAssertEqual(fixture.store.board, original)
        XCTAssertEqual(fixture.store.board?.compactSummary, originalSummary)
        XCTAssertFalse(fixture.store.isMovePending)
        XCTAssertTrue(fixture.store.errorMessage?.contains("无法移动任务，已恢复原位置") == true)
    }

    func testCreateIsRejectedWhileFailingMoveIsPending() async throws {
        let fixture = try makeFixture(reorderError: TestMoveError.persistenceFailed)
        await fixture.store.load()
        let original = try XCTUnwrap(fixture.store.board)
        let transaction = try startedTransaction(
            fixture.store.beginMove(taskID: fixture.first.id, to: .processing, insertionIndex: 0)
        )

        let created = await fixture.store.create(title: "Racing task", urgency: .urgent, repeatsDaily: false)
        XCTAssertFalse(created)
        XCTAssertEqual(fixture.store.board?.allTasks.count, original.allTasks.count)

        await fixture.store.persistMove(transaction)
        XCTAssertEqual(fixture.store.board, original)
    }

    func testBoundaryRecoveryWaitsForFailingMoveThenAdvancesFromRestoredBoard() async throws {
        let fixture = try makeFixture(reorderError: TestMoveError.persistenceFailed)
        await fixture.store.load()
        let originalDay = try XCTUnwrap(fixture.store.board?.businessDay)
        let transaction = try startedTransaction(
            fixture.store.beginMove(taskID: fixture.first.id, to: .processing, insertionIndex: 0)
        )
        fixture.clock.set(originalDay.end.addingTimeInterval(1))

        await fixture.store.handleWake()
        XCTAssertEqual(fixture.store.board?.businessDay, originalDay)

        await fixture.store.persistMove(transaction)
        XCTAssertEqual(fixture.store.board?.businessDay.start, originalDay.end)
        XCTAssertEqual(fixture.store.snapshots.count, 1)
        XCTAssertFalse(fixture.store.isMovePending)
    }

    func testInitialLoadRecoversBeforeReadingMonthSnapshots() async throws {
        let fixture = try makeFixture()
        let originalDay = await fixture.repository.currentBoard().businessDay
        fixture.clock.set(originalDay.end.addingTimeInterval(86_401))

        await fixture.store.load()

        XCTAssertEqual(fixture.store.snapshots.count, 2)
        XCTAssertEqual(
            fixture.store.board?.businessDay.start.millisecondsSince1970,
            fixture.store.snapshots.last?.completedAtMilliseconds
        )
    }

    func testMoveRemainsLockedWhileDeferredRecoveryIsSuspended() async throws {
        let fixture = try makeFixture(suspendSnapshotSave: true)
        await fixture.store.load()
        let originalDay = try XCTUnwrap(fixture.store.board?.businessDay)
        let transaction = try startedTransaction(
            fixture.store.beginMove(taskID: fixture.first.id, to: .processing, insertionIndex: 0)
        )
        fixture.clock.set(originalDay.end.addingTimeInterval(1))
        await fixture.store.handleWake()

        let persistence = Task { await fixture.store.persistMove(transaction) }
        await fixture.repository.waitForSnapshotSaveToStart()

        XCTAssertTrue(fixture.store.isMovePending)
        guard case .rejected = fixture.store.beginMove(
            taskID: fixture.second.id,
            to: .done,
            insertionIndex: 0
        ) else { return XCTFail("pending move should be rejected") }

        await fixture.repository.releaseSnapshotSave()
        let persistenceSucceeded = await persistence.value
        XCTAssertTrue(persistenceSucceeded)
        XCTAssertFalse(fixture.store.isMovePending)
        XCTAssertEqual(fixture.store.board?.businessDay.start, originalDay.end)
    }

    func testPendingMoveRejectsAnotherMove() async throws {
        let fixture = try makeFixture()
        await fixture.store.load()
        let original = try XCTUnwrap(fixture.store.board)
        let transaction = try startedTransaction(
            fixture.store.beginMove(taskID: fixture.first.id, to: .processing, insertionIndex: 0)
        )

        guard case .rejected = fixture.store.beginMove(
            taskID: fixture.second.id,
            to: .done,
            insertionIndex: 0
        ) else { return XCTFail("pending move should be rejected") }
        XCTAssertEqual(fixture.store.board?.tasks(in: .processing).map(\.id), [fixture.first.id])

        await fixture.store.persistMove(PusherMoveTransaction(before: original, after: original))
        XCTAssertTrue(fixture.store.isMovePending)
        XCTAssertEqual(fixture.store.board?.tasks(in: .processing).map(\.id), [fixture.first.id])

        await fixture.store.persistMove(transaction)
        let reorderCount = await fixture.repository.reorderCount()
        XCTAssertEqual(reorderCount, 1)
    }

    func testNoOpMoveDoesNotCreateTransactionOrWriteRepository() async throws {
        let fixture = try makeFixture(includeProcessingTask: true)
        await fixture.store.load()

        let preparation = fixture.store.beginMove(
            taskID: fixture.first.id,
            to: .planned,
            insertionIndex: 1
        )

        guard case .unchanged = preparation else { return XCTFail("same slot should be unchanged") }
        XCTAssertFalse(fixture.store.isMovePending)
        let reorderCount = await fixture.repository.reorderCount()
        XCTAssertEqual(reorderCount, 0)
    }

    func testInvalidMoveIsRejectedWithoutChangingBoard() async throws {
        let fixture = try makeFixture()
        await fixture.store.load()
        let original = fixture.store.board

        guard case .rejected = fixture.store.beginMove(
            taskID: UUID(),
            to: .done,
            insertionIndex: 0
        ) else { return XCTFail("unknown task should be rejected") }

        XCTAssertEqual(fixture.store.board, original)
        XCTAssertFalse(fixture.store.isMovePending)
    }

    private func startedTransaction(
        _ preparation: PusherMovePreparation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> PusherMoveTransaction {
        guard case let .started(transaction) = preparation else {
            XCTFail("expected started move", file: file, line: line)
            throw TestMoveError.persistenceFailed
        }
        return transaction
    }

    private func makeFixture(
        reorderError: (any Error & Sendable)? = nil,
        includeProcessingTask: Bool = false,
        suspendSnapshotSave: Bool = false
    ) throws -> (
        store: PusherStore,
        repository: TestPusherRepository,
        clock: MutableTestClock,
        first: PusherTask,
        second: PusherTask
    ) {
        let day = BusinessDay(
            featureID: .pusher,
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86_400)
        )
        let first = try PusherTask(
            title: "First",
            urgency: .urgent,
            position: 0,
            businessDayID: day.id
        )
        let second = try PusherTask(
            title: "Second",
            urgency: .progress,
            position: 1,
            businessDayID: day.id
        )
        var tasks = [first, second]
        if includeProcessingTask {
            tasks.append(
                try PusherTask(
                    title: "Already processing",
                    urgency: .planning,
                    status: .processing,
                    businessDayID: day.id
                )
            )
        }
        let repository = TestPusherRepository(
            board: PusherBoard(businessDay: day, tasks: tasks),
            reorderError: reorderError,
            suspendSnapshotSave: suspendSnapshotSave
        )
        let clock = MutableTestClock(date: day.start.addingTimeInterval(60))
        let eventHub = TemporalEventHub(clock: clock, scheduler: NoopTestScheduler())
        let store = PusherStore(
            repository: repository,
            clock: clock,
            resolver: BusinessDayResolver(calendar: Calendar(identifier: .gregorian)),
            eventHub: eventHub
        )
        return (store, repository, clock, first, second)
    }
}

private enum TestMoveError: Error, Sendable {
    case persistenceFailed
}

private final class MutableTestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(date: Date) {
        self.date = date
    }

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

private actor NoopTestScheduler: TemporalScheduling {
    func schedule(at date: Date, action: @escaping @Sendable () -> Void) async {}
    func cancelAll() async {}
}

private actor TestPusherRepository: PusherRepository {
    private var board: PusherBoard
    private let reorderError: (any Error & Sendable)?
    private let suspendSnapshotSave: Bool
    private var reorderedBoards: [PusherBoard] = []
    private var snapshots: [PusherDailySnapshot] = []
    private var snapshotSaveStarted = false
    private var snapshotStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var snapshotRelease: CheckedContinuation<Void, Never>?

    init(
        board: PusherBoard,
        reorderError: (any Error & Sendable)?,
        suspendSnapshotSave: Bool
    ) {
        self.board = board
        self.reorderError = reorderError
        self.suspendSnapshotSave = suspendSnapshotSave
    }

    func loadOrBootstrapCurrentBoard(resolvedToday: BusinessDay) async throws -> PusherBoard { board }

    func advanceDay(_ settlement: PusherSettlement) async throws -> PusherBoard {
        snapshotSaveStarted = true
        let waiters = snapshotStartWaiters
        snapshotStartWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        if suspendSnapshotSave {
            await withCheckedContinuation { continuation in
                snapshotRelease = continuation
            }
        }
        snapshots.removeAll { $0.businessDayID == settlement.snapshot.businessDayID }
        snapshots.append(settlement.snapshot)
        board = settlement.nextBoard
        return board
    }

    func loadOrCreateDay(_ day: BusinessDay) async throws -> PusherBoard { board }
    func updateCurrentBusinessDay(_ day: BusinessDay) async throws {
        board = PusherBoard(businessDay: day, tasks: board.allTasks)
    }
    func saveBoard(_ board: PusherBoard) async throws { self.board = board }
    func insertTask(_ task: PusherTask, at index: Int) async throws {}
    func updateTask(_ task: PusherTask) async throws {}
    func deleteTask(id: UUID) async throws {}

    func reorderTasks(businessDayID: BusinessDayID, orderedTasks: [PusherTask]) async throws {
        if let reorderError { throw reorderError }
        let reordered = PusherBoard(businessDay: board.businessDay, tasks: orderedTasks)
        reorderedBoards.append(reordered)
        board = reordered
    }

    func loadSnapshots(
        from startMilliseconds: Int64,
        to endMilliseconds: Int64
    ) async throws -> [PusherDailySnapshot] {
        snapshots.filter {
            $0.businessDayID.startAtMilliseconds >= startMilliseconds
                && $0.businessDayID.startAtMilliseconds < endMilliseconds
        }
    }

    func reorderCount() -> Int { reorderedBoards.count }
    func lastReorderedBoard() -> PusherBoard? { reorderedBoards.last }
    func currentBoard() -> PusherBoard { board }

    func waitForSnapshotSaveToStart() async {
        guard !snapshotSaveStarted else { return }
        await withCheckedContinuation { continuation in
            snapshotStartWaiters.append(continuation)
        }
    }

    func releaseSnapshotSave() {
        snapshotRelease?.resume()
        snapshotRelease = nil
    }
}
