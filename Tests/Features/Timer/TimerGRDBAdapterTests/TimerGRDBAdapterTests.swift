import Foundation
import XCTest
import GRDB
import PeekerCore
import PersistenceCore
import TimerFeature
import TimerGRDBAdapter

final class TimerGRDBAdapterTests: XCTestCase {
    func testReleasedV1V2TimerDataMigratesInPlaceAndSurvivesModuleRemoval() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("peeker-timer-legacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("Peeker.sqlite").path
        let templateID = UUID().uuidString
        let taskID = UUID().uuidString
        let sessionID = UUID().uuidString
        let legacy = try DatabaseQueue(path: path)
        try legacy.write { db in
            try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO grdb_migrations VALUES ('v1'), ('v2-feature-runtime-state')")
            try db.execute(sql: """
                CREATE TABLE business_days (
                    feature_id TEXT NOT NULL, start_at_ms INTEGER NOT NULL,
                    end_at_ms INTEGER NOT NULL, PRIMARY KEY (feature_id, start_at_ms)
                );
                CREATE TABLE feature_runtime_state (
                    feature_id TEXT PRIMARY KEY, current_day_start_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL
                );
                CREATE TABLE timer_templates (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL, target_seconds INTEGER NOT NULL,
                    color_hex TEXT NOT NULL, position INTEGER NOT NULL, updated_at_ms INTEGER NOT NULL
                );
                CREATE TABLE timer_day_instances (
                    id TEXT PRIMARY KEY, template_id TEXT NOT NULL, feature_id TEXT NOT NULL,
                    day_start_at_ms INTEGER NOT NULL, name TEXT NOT NULL, target_seconds INTEGER NOT NULL,
                    color_hex TEXT NOT NULL, position INTEGER NOT NULL,
                    accumulated_seconds INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL,
                    last_action_at_ms INTEGER, visible BOOLEAN NOT NULL DEFAULT 1,
                    UNIQUE (template_id, feature_id, day_start_at_ms)
                );
                CREATE TABLE timer_sessions (
                    id TEXT PRIMARY KEY, task_id TEXT NOT NULL, feature_id TEXT NOT NULL,
                    day_start_at_ms INTEGER NOT NULL, started_at_ms INTEGER NOT NULL,
                    ended_at_ms INTEGER, credited_seconds INTEGER, end_reason TEXT,
                    active BOOLEAN NOT NULL DEFAULT 1
                );
                CREATE UNIQUE INDEX timer_one_active_session
                    ON timer_sessions(active) WHERE active = 1;
                CREATE TABLE timer_daily_snapshots (
                    feature_id TEXT NOT NULL, day_start_at_ms INTEGER NOT NULL,
                    completion_ratio DOUBLE, completed_at_ms INTEGER NOT NULL,
                    PRIMARY KEY (feature_id, day_start_at_ms)
                )
                """)
            try db.execute(sql: "INSERT INTO business_days VALUES ('timer', 100, 200)")
            try db.execute(sql: "INSERT INTO feature_runtime_state VALUES ('timer', 100, 150)")
            try db.execute(
                sql: "INSERT INTO timer_templates VALUES (?, 'Legacy Timer', 900, '#123456', 4, 151)",
                arguments: [templateID]
            )
            try db.execute(
                sql: "INSERT INTO timer_day_instances VALUES (?, ?, 'timer', 100, 'Legacy Day', 900, '#654321', 3, 321, 'running', 149, 1)",
                arguments: [taskID, templateID]
            )
            try db.execute(
                sql: "INSERT INTO timer_sessions VALUES (?, ?, 'timer', 100, 120, NULL, NULL, NULL, 1)",
                arguments: [sessionID, taskID]
            )
            try db.execute(sql: "INSERT INTO timer_daily_snapshots VALUES ('timer', 99, 0.75, 100)")
        }

        let migrated = try AppDatabase(path: path, featureMigrations: TimerDatabaseMigrations.all)
        try assertLegacyTimerRows(in: migrated, templateID: templateID, taskID: taskID, sessionID: sessionID)

        let reopenedWithoutTimer = try AppDatabase(path: path)
        try assertLegacyTimerRows(
            in: reopenedWithoutTimer,
            templateID: templateID,
            taskID: taskID,
            sessionID: sessionID
        )
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

    func testTimerRecoveryNeverOverwritesAPreexistingV1Snapshot() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TimerGRDBRepository(database: database)
        let oldDay = makeDay(featureID: .timer)
        let nextDay = makeDay(featureID: .timer, start: 86_400)
        let template = try TimerTemplate(name: "Legacy", targetSeconds: 600, colorHex: "#1685FF", position: 0)
        try await repository.saveTemplate(template)
        let current = try await repository.loadOrBootstrapCurrentDay(resolvedToday: oldDay)
        let frozen = TimerDailySnapshot(
            businessDayID: oldDay.id,
            completionRatio: 0.75,
            completedAtMilliseconds: oldDay.end.millisecondsSince1970
        )
        try await database.queue.write { db in
            try db.execute(
                sql: "INSERT INTO timer_daily_snapshots VALUES (?, ?, ?, ?)",
                arguments: [
                    frozen.businessDayID.featureID.rawValue,
                    frozen.businessDayID.startAtMilliseconds,
                    frozen.completionRatio,
                    frozen.completedAtMilliseconds,
                ]
            )
        }
        let computed = TimerDailySnapshot(
            businessDayID: oldDay.id,
            completionRatio: current.completionRatio,
            completedAtMilliseconds: oldDay.end.millisecondsSince1970
        )

        _ = try await repository.advanceDay(
            TimerDayTransition(
                settledState: current,
                completion: nil,
                snapshot: computed,
                nextDay: nextDay,
                continuingTemplateID: nil,
                boundaryMilliseconds: oldDay.end.millisecondsSince1970
            )
        )

        let snapshots = try await repository.loadSnapshots(from: 0, to: 200_000_000)
        XCTAssertEqual(snapshots, [frozen])
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

    @MainActor
    func testTimerPartialMultiDayRecoveryPublishesLastCommittedPointer() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TimerGRDBRepository(database: database)
        let oldDay = makeDay(featureID: .timer)
        let template = try TimerTemplate(name: "Exercise", targetSeconds: 60, colorHex: "#1685FF", position: 0)
        try await repository.saveTemplate(template)
        _ = try await repository.loadOrBootstrapCurrentDay(resolvedToday: oldDay)
        try await database.queue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_second_timer_recovery
                BEFORE UPDATE ON feature_runtime_state
                WHEN OLD.feature_id = 'timer' AND OLD.current_day_start_at_ms <> 0
                BEGIN
                    SELECT RAISE(ABORT, 'forced second-day failure');
                END
                """)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let clock = FixedTestClock(date: oldDay.end.addingTimeInterval(86_401))
        let store = TimerStore(
            repository: repository,
            clock: clock,
            resolver: BusinessDayResolver(calendar: calendar),
            eventHub: TemporalEventHub(clock: clock, scheduler: PersistenceNoopScheduler()),
            audio: SilentTestAudio()
        )

        await store.load()

        let pointer = try await database.queue.read { db in
            try Int64.fetchOne(
                db,
                sql: "SELECT current_day_start_at_ms FROM feature_runtime_state WHERE feature_id = 'timer'"
            )
        }
        XCTAssertEqual(pointer, oldDay.end.millisecondsSince1970)
        XCTAssertEqual(store.dayState?.businessDay.id.startAtMilliseconds, pointer)
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testTimerRefreshChangeKeepsActiveSessionAndCurrentBusinessDayID() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TimerGRDBRepository(database: database)
        let day = makeDay(featureID: .timer)
        let template = try TimerTemplate(name: "Exercise", targetSeconds: 7_200, colorHex: "#1685FF", position: 0)
        try await repository.saveTemplate(template)
        var running = try await repository.loadOrBootstrapCurrentDay(resolvedToday: day)
        try running.start(taskID: try XCTUnwrap(running.tasks.first?.id), atMilliseconds: 1_000)
        let originalSession = try XCTUnwrap(running.activeSession)
        try await repository.commitStart(state: running, session: originalSession)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let clock = FixedTestClock(date: day.start.addingTimeInterval(3_600))
        let store = TimerStore(
            repository: repository,
            clock: clock,
            resolver: BusinessDayResolver(calendar: calendar),
            eventHub: TemporalEventHub(clock: clock, scheduler: PersistenceNoopScheduler()),
            audio: SilentTestAudio()
        )
        await store.load()

        await store.updateRefreshTime(try RefreshTime(hour: 6, minute: 0))

        let stored = try await database.queue.read { db -> (Int64?, Int64?, Bool?) in
            let pointer = try Int64.fetchOne(
                db,
                sql: "SELECT current_day_start_at_ms FROM feature_runtime_state WHERE feature_id = 'timer'"
            )
            let end = try Int64.fetchOne(
                db,
                sql: "SELECT end_at_ms FROM business_days WHERE feature_id = 'timer' AND start_at_ms = ?",
                arguments: [day.id.startAtMilliseconds]
            )
            let active = try Bool.fetchOne(
                db,
                sql: "SELECT active FROM timer_sessions WHERE id = ?",
                arguments: [originalSession.id.uuidString]
            )
            return (pointer, end, active)
        }
        XCTAssertEqual(store.dayState?.businessDay.id, day.id)
        XCTAssertEqual(store.dayState?.activeSession?.id, originalSession.id)
        XCTAssertEqual(stored.0, day.id.startAtMilliseconds)
        XCTAssertEqual(stored.1, store.dayState?.businessDay.end.millisecondsSince1970)
        XCTAssertGreaterThan(try XCTUnwrap(stored.1), clock.now().millisecondsSince1970)
        XCTAssertEqual(stored.2, true)
    }


    func testTimerMigrationCreatesOnlyTimerSchema() throws {
        let database = try AppDatabase.inMemory(
            featureMigrations: TimerDatabaseMigrations.all
        )
        let tables = try database.queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }

        XCTAssertTrue(tables.contains("timer_templates"))
        XCTAssertTrue(tables.contains("timer_day_instances"))
        XCTAssertTrue(tables.contains("timer_sessions"))
        XCTAssertTrue(tables.contains("timer_daily_snapshots"))
        XCTAssertFalse(tables.contains("pusher_tasks"))
    }

    private func makeDay(featureID: FeatureID, start: TimeInterval = 0) -> BusinessDay {
        BusinessDay(
            featureID: featureID,
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: start + 86_400)
        )
    }

    private func assertLegacyTimerRows(
        in database: AppDatabase,
        templateID: String,
        taskID: String,
        sessionID: String
    ) throws {
        try database.queue.read { db in
            let template = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM timer_templates WHERE id = ?", arguments: [templateID]))
            XCTAssertEqual(template["name"] as String?, "Legacy Timer")
            XCTAssertEqual(template["target_seconds"] as Int?, 900)
            XCTAssertEqual(template["color_hex"] as String?, "#123456")
            XCTAssertEqual(template["position"] as Int?, 4)
            XCTAssertEqual(template["updated_at_ms"] as Int64?, 151)

            let instance = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM timer_day_instances WHERE id = ?", arguments: [taskID]))
            XCTAssertEqual(instance["template_id"] as String?, templateID)
            XCTAssertEqual(instance["name"] as String?, "Legacy Day")
            XCTAssertEqual(instance["accumulated_seconds"] as Int?, 321)
            XCTAssertEqual(instance["status"] as String?, "running")
            XCTAssertEqual(instance["last_action_at_ms"] as Int64?, 149)
            XCTAssertEqual(instance["visible"] as Bool?, true)

            let session = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM timer_sessions WHERE id = ?", arguments: [sessionID]))
            XCTAssertEqual(session["task_id"] as String?, taskID)
            XCTAssertEqual(session["started_at_ms"] as Int64?, 120)
            XCTAssertEqual(session["active"] as Bool?, true)
            XCTAssertNil(session["ended_at_ms"] as Int64?)

            let snapshot = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM timer_daily_snapshots WHERE day_start_at_ms = 99"))
            XCTAssertEqual(snapshot["completion_ratio"] as Double?, 0.75)
            XCTAssertEqual(snapshot["completed_at_ms"] as Int64?, 100)
            XCTAssertEqual(
                try Int64.fetchOne(db, sql: "SELECT current_day_start_at_ms FROM feature_runtime_state WHERE feature_id = 'timer'"),
                100
            )
            XCTAssertEqual(
                try String.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'timer_one_active_session'"),
                "timer_one_active_session"
            )
        }
    }
}

private extension AppDatabase {
    static func inMemory() throws -> AppDatabase {
        try inMemory(featureMigrations: TimerDatabaseMigrations.all)
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
