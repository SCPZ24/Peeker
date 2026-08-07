import XCTest
import GRDB
import PeekerCore
import PersistenceCore
import TimerFeature
import TimerGRDBAdapter
import PusherFeature
import PusherGRDBAdapter

final class AppDatabaseTests: XCTestCase {
    func testMigrationIsIdempotentAndCreatesAllFeatureTables() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()

        let tables = try database.queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }

        XCTAssertTrue(tables.contains("business_days"))
        XCTAssertTrue(tables.contains("timer_templates"))
        XCTAssertTrue(tables.contains("timer_sessions"))
        XCTAssertTrue(tables.contains("pusher_tasks"))
        XCTAssertTrue(tables.contains("pusher_daily_snapshots"))
        XCTAssertTrue(tables.contains("feature_runtime_state"))
    }

    func testRuntimeStateReferencesAnExistingBusinessDay() throws {
        let database = try AppDatabase.inMemory()

        XCTAssertThrowsError(
            try database.queue.write { db in
                try db.execute(sql: "PRAGMA foreign_keys = ON")
                try db.execute(
                    sql: """
                    INSERT INTO feature_runtime_state
                        (feature_id, current_day_start_at_ms, updated_at_ms)
                    VALUES ('pusher', 42, 42)
                    """
                )
            }
        )
    }

    func testDefaultDatabaseURLIsStableAcrossAppBundleReplacement() throws {
        let first = try AppDatabase.defaultURL()
        let second = try AppDatabase.defaultURL()

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.path.hasSuffix("/Library/Application Support/Peeker/Peeker.sqlite"))
        XCTAssertFalse(first.path.contains("/Applications/Peeker.app"))
    }

    func testV1DatabaseMigratesInPlaceWithoutRewritingPusherTasks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("peeker-v1-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("Peeker.sqlite").path
        let taskID = UUID().uuidString
        let legacy = try DatabaseQueue(path: path)
        try legacy.write { db in
            try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v1')")
            try db.execute(sql: """
                CREATE TABLE business_days (
                    feature_id TEXT NOT NULL,
                    start_at_ms INTEGER NOT NULL,
                    end_at_ms INTEGER NOT NULL,
                    PRIMARY KEY (feature_id, start_at_ms)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE pusher_tasks (
                    id TEXT PRIMARY KEY,
                    series_id TEXT,
                    feature_id TEXT NOT NULL,
                    day_start_at_ms INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    urgency TEXT NOT NULL,
                    status TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    created_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL,
                    archived BOOLEAN NOT NULL DEFAULT 0
                )
                """)
            try db.execute(
                sql: "INSERT INTO business_days VALUES ('pusher', 0, 86400000)"
            )
            try db.execute(
                sql: """
                INSERT INTO pusher_tasks
                    (id, feature_id, day_start_at_ms, title, urgency, status,
                     position, created_at_ms, updated_at_ms, archived)
                VALUES (?, 'pusher', 0, 'Preserved', 'urgent', 'planned', 0, 1, 1, 0)
                """,
                arguments: [taskID]
            )
        }

        let migrated = try AppDatabase(path: path)
        let result = try migrated.queue.read { db -> (String?, String?, String?) in
            let title = try String.fetchOne(db, sql: "SELECT title FROM pusher_tasks WHERE id = ?", arguments: [taskID])
            let table = try String.fetchOne(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'feature_runtime_state'"
            )
            let integrity = try String.fetchOne(db, sql: "PRAGMA integrity_check")
            return (title, table, integrity)
        }

        XCTAssertEqual(result.0, "Preserved")
        XCTAssertEqual(result.1, "feature_runtime_state")
        XCTAssertEqual(result.2, "ok")
    }

    func testDatabaseRejectsTwoActiveTimerSessions() async throws {
        let database = try AppDatabase.inMemory()
        let day = makeDay(featureID: .timer)
        let template = try TimerTemplate(name: "Read", targetSeconds: 60, colorHex: "#123456", position: 0)
        let repository = TimerGRDBRepository(database: database)
        try await repository.saveTemplate(template)
        let state = try await repository.loadOrCreateDay(day)
        let task = try XCTUnwrap(state.tasks.first)

        try await repository.beginSession(
            TimerSession(taskID: task.id, businessDayID: day.id, startedAtMilliseconds: 1_000)
        )

        do {
            try await repository.beginSession(
                TimerSession(taskID: task.id, businessDayID: day.id, startedAtMilliseconds: 2_000)
            )
            XCTFail("Expected the one-active-session index to reject a second session")
        } catch {
            // Expected SQLite constraint violation.
        }
    }

    func testTimerCreatesCurrentDayInstancesFromTemplates() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TimerGRDBRepository(database: database)
        let template = try TimerTemplate(name: "Read", targetSeconds: 900, colorHex: "#112233", position: 0)
        try await repository.saveTemplate(template)

        let state = try await repository.loadOrCreateDay(makeDay(featureID: .timer))

        XCTAssertEqual(state.tasks.count, 1)
        XCTAssertEqual(state.tasks[0].templateID, template.id)
        XCTAssertEqual(state.tasks[0].targetSeconds, 900)
    }

    func testPusherReorderPersistsStatusAndContiguousPositions() async throws {
        let database = try AppDatabase.inMemory()
        let repository = PusherGRDBRepository(database: database)
        let day = makeDay(featureID: .pusher)
        var board = PusherBoard(businessDay: day, tasks: [])
        let first = try PusherTask(title: "First", urgency: .planning, businessDayID: day.id)
        let second = try PusherTask(title: "Second", urgency: .urgent, businessDayID: day.id)
        try board.insert(first)
        try board.insert(second)
        try await repository.saveBoard(board)

        try board.move(taskID: first.id, to: .processing, at: 0)
        try await repository.reorderTasks(businessDayID: day.id, orderedTasks: board.allTasks)
        let loaded = try await repository.loadOrCreateDay(day)

        XCTAssertEqual(loaded.tasks(in: .planned).map(\.position), [0])
        XCTAssertEqual(loaded.tasks(in: .processing).map(\.id), [first.id])
    }

    func testPusherReorderPersistsSameColumnMoveToEnd() async throws {
        let database = try AppDatabase.inMemory()
        let repository = PusherGRDBRepository(database: database)
        let day = makeDay(featureID: .pusher)
        let first = try PusherTask(title: "First", urgency: .planning, position: 0, businessDayID: day.id)
        let second = try PusherTask(title: "Second", urgency: .urgent, position: 1, businessDayID: day.id)
        let third = try PusherTask(title: "Third", urgency: .progress, position: 2, businessDayID: day.id)
        var board = PusherBoard(businessDay: day, tasks: [first, second, third])
        try await repository.saveBoard(board)

        try board.move(taskID: first.id, to: .planned, at: 3)
        try await repository.reorderTasks(businessDayID: day.id, orderedTasks: board.allTasks)
        let loaded = try await repository.loadOrCreateDay(day)

        XCTAssertEqual(loaded.tasks(in: .planned).map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(loaded.tasks(in: .planned).map(\.position), [0, 1, 2])
    }

    func testPusherReorderPersistsCrossColumnMiddleInsertion() async throws {
        let database = try AppDatabase.inMemory()
        let repository = PusherGRDBRepository(database: database)
        let day = makeDay(featureID: .pusher)
        let planned = try PusherTask(title: "Planned", urgency: .planning, position: 0, businessDayID: day.id)
        let processingA = try PusherTask(
            title: "Processing A",
            urgency: .urgent,
            status: .processing,
            position: 0,
            businessDayID: day.id
        )
        let processingB = try PusherTask(
            title: "Processing B",
            urgency: .progress,
            status: .processing,
            position: 1,
            businessDayID: day.id
        )
        var board = PusherBoard(businessDay: day, tasks: [planned, processingA, processingB])
        try await repository.saveBoard(board)

        try board.move(taskID: planned.id, to: .processing, at: 1)
        try await repository.reorderTasks(businessDayID: day.id, orderedTasks: board.allTasks)
        let loaded = try await repository.loadOrCreateDay(day)

        XCTAssertEqual(
            loaded.tasks(in: .processing).map(\.id),
            [processingA.id, planned.id, processingB.id]
        )
        XCTAssertEqual(loaded.tasks(in: .processing).map(\.position), [0, 1, 2])
    }

    func testPusherReorderRollsBackEveryUpdateWhenOneTaskFails() async throws {
        let database = try AppDatabase.inMemory()
        let repository = PusherGRDBRepository(database: database)
        let day = makeDay(featureID: .pusher)
        let first = try PusherTask(title: "First", urgency: .planning, position: 0, businessDayID: day.id)
        let second = try PusherTask(title: "Second", urgency: .urgent, position: 1, businessDayID: day.id)
        var board = PusherBoard(businessDay: day, tasks: [first, second])
        try await repository.saveBoard(board)
        try await database.queue.write { db in
            try db.execute(
                sql: "UPDATE pusher_tasks SET position = 9 WHERE id = ?",
                arguments: [first.id.uuidString]
            )
            try db.execute(
                sql: """
                CREATE TRIGGER reject_second_pusher_move
                BEFORE UPDATE OF status, position ON pusher_tasks
                WHEN OLD.id = '\(second.id.uuidString)'
                BEGIN
                    SELECT RAISE(ABORT, 'forced pusher reorder failure');
                END
                """
            )
        }

        try board.move(taskID: second.id, to: .processing, at: 0)
        do {
            try await repository.reorderTasks(businessDayID: day.id, orderedTasks: board.allTasks)
            XCTFail("Expected the trigger to reject the reorder")
        } catch {
            // Expected: the surrounding GRDB write transaction rolls back the first update.
        }

        let storedFirstPosition = try await database.queue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT position FROM pusher_tasks WHERE id = ?",
                arguments: [first.id.uuidString]
            )
        }
        XCTAssertEqual(storedFirstPosition, 9)
    }

    func testPusherBootstrapIgnoresAnOrphanEmptyBusinessDay() async throws {
        let database = try AppDatabase.inMemory()
        let repository = PusherGRDBRepository(database: database)
        let oldDay = makeDay(featureID: .pusher)
        let today = makeDay(featureID: .pusher, start: 86_400)
        let task = try PusherTask(title: "Survives upgrade", urgency: .urgent, businessDayID: oldDay.id)
        try await repository.saveBoard(PusherBoard(businessDay: oldDay, tasks: [task]))
        try await database.queue.write { db in
            try persistBusinessDay(today, in: db)
        }

        let restored = try await repository.loadOrBootstrapCurrentBoard(resolvedToday: today)

        XCTAssertEqual(restored.businessDay.id, oldDay.id)
        XCTAssertEqual(restored.allTasks.map(\.id), [task.id])
    }

    func testPusherAdvanceFreezesSnapshotAndKeepsLegitimateEmptyCurrentBoard() async throws {
        let database = try AppDatabase.inMemory()
        let repository = PusherGRDBRepository(database: database)
        let oldDay = makeDay(featureID: .pusher)
        let nextDay = makeDay(featureID: .pusher, start: 86_400)
        let done = try PusherTask(
            title: "Done",
            urgency: .planning,
            status: .done,
            businessDayID: oldDay.id
        )
        try await repository.saveBoard(PusherBoard(businessDay: oldDay, tasks: [done]))
        let current = try await repository.loadOrBootstrapCurrentBoard(resolvedToday: nextDay)
        let settlement = PusherSettlement.settle(
            current,
            into: nextDay,
            carryIncomplete: false,
            atMilliseconds: oldDay.end.millisecondsSince1970
        )

        let advanced = try await repository.advanceDay(settlement)
        let relaunched = try await repository.loadOrBootstrapCurrentBoard(resolvedToday: nextDay)
        let snapshots = try await repository.loadSnapshots(from: 0, to: 200_000_000)

        XCTAssertTrue(advanced.allTasks.isEmpty)
        XCTAssertEqual(relaunched.businessDay.id, nextDay.id)
        XCTAssertTrue(relaunched.allTasks.isEmpty)
        XCTAssertEqual(snapshots, [settlement.snapshot])
    }

    func testPusherAdvanceRollsBackSnapshotNextBoardAndRuntimePointer() async throws {
        let database = try AppDatabase.inMemory()
        let repository = PusherGRDBRepository(database: database)
        let oldDay = makeDay(featureID: .pusher)
        let nextDay = makeDay(featureID: .pusher, start: 86_400)
        let task = try PusherTask(title: "Carry me", urgency: .progress, businessDayID: oldDay.id)
        try await repository.saveBoard(PusherBoard(businessDay: oldDay, tasks: [task]))
        let current = try await repository.loadOrBootstrapCurrentBoard(resolvedToday: nextDay)
        let settlement = PusherSettlement.settle(
            current,
            into: nextDay,
            carryIncomplete: true,
            atMilliseconds: oldDay.end.millisecondsSince1970
        )
        try await database.queue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_pusher_pointer_move
                BEFORE UPDATE ON feature_runtime_state
                WHEN OLD.feature_id = 'pusher'
                BEGIN
                    SELECT RAISE(ABORT, 'forced pointer failure');
                END
                """)
        }

        do {
            _ = try await repository.advanceDay(settlement)
            XCTFail("Expected the trigger to reject the atomic transition")
        } catch {}

        let pointer = try await database.queue.read { db in
            try Int64.fetchOne(
                db,
                sql: "SELECT current_day_start_at_ms FROM feature_runtime_state WHERE feature_id = 'pusher'"
            )
        }
        let snapshots = try await repository.loadSnapshots(from: 0, to: 200_000_000)
        let oldBoard = try await repository.loadOrCreateDay(oldDay)
        XCTAssertEqual(pointer, oldDay.id.startAtMilliseconds)
        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertEqual(oldBoard.allTasks.map(\.id), [task.id])
    }

    func testTimerBootstrapPrefersActiveSessionOverNewerOrphanInstances() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TimerGRDBRepository(database: database)
        let oldDay = makeDay(featureID: .timer)
        let today = makeDay(featureID: .timer, start: 86_400)
        let template = try TimerTemplate(name: "Exercise", targetSeconds: 600, colorHex: "#1685FF", position: 0)
        try await repository.saveTemplate(template)
        var oldState = try await repository.loadOrCreateDay(oldDay)
        try oldState.start(taskID: try XCTUnwrap(oldState.tasks.first?.id), atMilliseconds: 1_000)
        try await repository.commitStart(state: oldState, session: try XCTUnwrap(oldState.activeSession))
        _ = try await repository.loadOrCreateDay(today)

        let restored = try await repository.loadOrBootstrapCurrentDay(resolvedToday: today)

        XCTAssertEqual(restored.businessDay.id, oldDay.id)
        XCTAssertNotNil(restored.activeSession)
    }

    func testTimerAdvanceAtomicallySplitsRunningSessionAndMovesPointer() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TimerGRDBRepository(database: database)
        let oldDay = makeDay(featureID: .timer)
        let nextDay = makeDay(featureID: .timer, start: 86_400)
        let template = try TimerTemplate(name: "Exercise", targetSeconds: 600, colorHex: "#1685FF", position: 0)
        try await repository.saveTemplate(template)
        var running = try await repository.loadOrBootstrapCurrentDay(resolvedToday: oldDay)
        try running.start(
            taskID: try XCTUnwrap(running.tasks.first?.id),
            atMilliseconds: oldDay.end.millisecondsSince1970 - 30_000
        )
        try await repository.commitStart(state: running, session: try XCTUnwrap(running.activeSession))
        var settled = running
        let completion = try XCTUnwrap(
            try settled.pause(atMilliseconds: oldDay.end.millisecondsSince1970, reason: .businessDayBoundary)
        )
        let snapshot = TimerDailySnapshot(
            businessDayID: oldDay.id,
            completionRatio: settled.completionRatio,
            completedAtMilliseconds: oldDay.end.millisecondsSince1970
        )

        let advanced = try await repository.advanceDay(
            TimerDayTransition(
                settledState: settled,
                completion: completion,
                snapshot: snapshot,
                nextDay: nextDay,
                continuingTemplateID: template.id,
                boundaryMilliseconds: oldDay.end.millisecondsSince1970
            )
        )
        let relaunched = try await repository.loadOrBootstrapCurrentDay(resolvedToday: nextDay)
        let snapshots = try await repository.loadSnapshots(from: 0, to: 200_000_000)

        XCTAssertEqual(advanced.businessDay.id, nextDay.id)
        XCTAssertNotNil(advanced.activeSession)
        XCTAssertEqual(relaunched.activeSession, advanced.activeSession)
        XCTAssertEqual(snapshots, [snapshot])
        let oldSessionActive = try await database.queue.read { db in
            try Bool.fetchOne(db, sql: "SELECT active FROM timer_sessions WHERE id = ?", arguments: [completion.session.id.uuidString])
        }
        XCTAssertEqual(oldSessionActive, false)
    }

    func testTimerAdvanceRollsBackEverySettlementWrite() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TimerGRDBRepository(database: database)
        let oldDay = makeDay(featureID: .timer)
        let nextDay = makeDay(featureID: .timer, start: 86_400)
        let template = try TimerTemplate(name: "Exercise", targetSeconds: 600, colorHex: "#1685FF", position: 0)
        try await repository.saveTemplate(template)
        var running = try await repository.loadOrBootstrapCurrentDay(resolvedToday: oldDay)
        try running.start(
            taskID: try XCTUnwrap(running.tasks.first?.id),
            atMilliseconds: oldDay.end.millisecondsSince1970 - 30_000
        )
        try await repository.commitStart(state: running, session: try XCTUnwrap(running.activeSession))
        var settled = running
        let completion = try XCTUnwrap(
            try settled.pause(atMilliseconds: oldDay.end.millisecondsSince1970, reason: .businessDayBoundary)
        )
        let snapshot = TimerDailySnapshot(
            businessDayID: oldDay.id,
            completionRatio: settled.completionRatio,
            completedAtMilliseconds: oldDay.end.millisecondsSince1970
        )
        try await database.queue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_timer_pointer_move
                BEFORE UPDATE ON feature_runtime_state
                WHEN OLD.feature_id = 'timer'
                BEGIN
                    SELECT RAISE(ABORT, 'forced pointer failure');
                END
                """)
        }

        do {
            _ = try await repository.advanceDay(
                TimerDayTransition(
                    settledState: settled,
                    completion: completion,
                    snapshot: snapshot,
                    nextDay: nextDay,
                    continuingTemplateID: template.id,
                    boundaryMilliseconds: oldDay.end.millisecondsSince1970
                )
            )
            XCTFail("Expected the trigger to reject the atomic transition")
        } catch {}

        let pointer = try await database.queue.read { db in
            try Int64.fetchOne(db, sql: "SELECT current_day_start_at_ms FROM feature_runtime_state WHERE feature_id = 'timer'")
        }
        let oldSessionActive = try await database.queue.read { db in
            try Bool.fetchOne(db, sql: "SELECT active FROM timer_sessions WHERE id = ?", arguments: [completion.session.id.uuidString])
        }
        let nextInstanceCount = try await database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM timer_day_instances WHERE day_start_at_ms = ?", arguments: [nextDay.id.startAtMilliseconds])
        }
        XCTAssertEqual(pointer, oldDay.id.startAtMilliseconds)
        XCTAssertEqual(oldSessionActive, true)
        XCTAssertEqual(nextInstanceCount, 0)
        let snapshots = try await repository.loadSnapshots(from: 0, to: 200_000_000)
        XCTAssertTrue(snapshots.isEmpty)
    }

    @MainActor
    func testTimerStoreRecoversEveryMissedDayBeforePublishingMonthSnapshotsInEitherMode() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TimerGRDBRepository(database: database)
        let oldDay = makeDay(featureID: .timer)
        let template = try TimerTemplate(name: "Exercise", targetSeconds: 600, colorHex: "#1685FF", position: 0)
        try await repository.saveTemplate(template)
        _ = try await repository.loadOrBootstrapCurrentDay(resolvedToday: oldDay)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let clock = FixedTestClock(date: oldDay.end.addingTimeInterval(86_401))
        let store = TimerStore(
            repository: repository,
            clock: clock,
            resolver: BusinessDayResolver(calendar: calendar),
            eventHub: TemporalEventHub(clock: clock, scheduler: PersistenceNoopScheduler()),
            audio: SilentTestAudio(),
            statisticsMode: .heatmap
        )

        await store.load()

        XCTAssertEqual(store.snapshots.count, 2)
        XCTAssertEqual(store.dayState?.businessDay.start.millisecondsSince1970, store.snapshots.last?.completedAtMilliseconds)
        store.updateStatisticsMode(.progress)

        let relaunched = TimerStore(
            repository: repository,
            clock: clock,
            resolver: BusinessDayResolver(calendar: calendar),
            eventHub: TemporalEventHub(clock: clock, scheduler: PersistenceNoopScheduler()),
            audio: SilentTestAudio(),
            statisticsMode: .progress
        )
        await relaunched.load()
        XCTAssertEqual(relaunched.snapshots.count, 2)
        let persistedCount = try await database.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM timer_daily_snapshots")
        }
        XCTAssertEqual(persistedCount, 2)
    }

    @MainActor
    func testTimerWakeDoesNotReplayCompletionSoundForAStaleOfflineTarget() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TimerGRDBRepository(database: database)
        let oldDay = makeDay(featureID: .timer)
        let template = try TimerTemplate(name: "Exercise", targetSeconds: 60, colorHex: "#1685FF", position: 0)
        try await repository.saveTemplate(template)
        var running = try await repository.loadOrBootstrapCurrentDay(resolvedToday: oldDay)
        try running.start(taskID: try XCTUnwrap(running.tasks.first?.id), atMilliseconds: 1_000)
        try await repository.commitStart(state: running, session: try XCTUnwrap(running.activeSession))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let clock = FixedTestClock(date: Date(millisecondsSince1970: 30_000))
        let audio = RecordingTestAudio()
        let store = TimerStore(
            repository: repository,
            clock: clock,
            resolver: BusinessDayResolver(calendar: calendar),
            eventHub: TemporalEventHub(clock: clock, scheduler: PersistenceNoopScheduler()),
            audio: audio
        )
        await store.load()
        clock.set(oldDay.end.addingTimeInterval(86_401))

        await store.handleWake()

        let playCount = await audio.playCount()
        XCTAssertEqual(playCount, 0)
        XCTAssertNil(store.dayState?.activeSession)
    }

    private func makeDay(featureID: FeatureID, start: TimeInterval = 0) -> BusinessDay {
        BusinessDay(
            featureID: featureID,
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: start + 86_400)
        )
    }
}

private final class FixedTestClock: Clock, @unchecked Sendable {
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

private actor PersistenceNoopScheduler: TemporalScheduling {
    func schedule(at date: Date, action: @escaping @Sendable () -> Void) async {}
    func cancelAll() async {}
}

private actor SilentTestAudio: AudioNotifying {
    func playCompletionSound() async {}
}

private actor RecordingTestAudio: AudioNotifying {
    private var count = 0
    func playCompletionSound() async { count += 1 }
    func playCount() -> Int { count }
}
