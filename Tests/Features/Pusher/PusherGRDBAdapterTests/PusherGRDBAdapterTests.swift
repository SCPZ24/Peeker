import Foundation
import XCTest
import GRDB
import PeekerCore
import PersistenceCore
import PusherFeature
import PusherGRDBAdapter

final class PusherGRDBAdapterTests: XCTestCase {
    func testReleasedV1V2PusherDataMigratesInPlaceAndSurvivesModuleRemoval() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("peeker-v1-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("Peeker.sqlite").path
        let taskID = UUID().uuidString
        let seriesID = UUID().uuidString
        let legacy = try DatabaseQueue(path: path)
        try legacy.write { db in
            try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO grdb_migrations VALUES ('v1'), ('v2-feature-runtime-state')")
            try db.execute(sql: """
                CREATE TABLE business_days (
                    feature_id TEXT NOT NULL,
                    start_at_ms INTEGER NOT NULL,
                    end_at_ms INTEGER NOT NULL,
                    PRIMARY KEY (feature_id, start_at_ms)
                )
                """)
            try db.execute(sql: """
                CREATE TABLE feature_runtime_state (
                    feature_id TEXT PRIMARY KEY,
                    current_day_start_at_ms INTEGER NOT NULL,
                    updated_at_ms INTEGER NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE pusher_series (
                    id TEXT PRIMARY KEY, title TEXT NOT NULL, urgency TEXT NOT NULL,
                    active BOOLEAN NOT NULL DEFAULT 1, updated_at_ms INTEGER NOT NULL
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
            try db.execute(sql: """
                CREATE INDEX pusher_tasks_day_status_position
                    ON pusher_tasks(feature_id, day_start_at_ms, status, position)
                """)
            try db.execute(sql: """
                CREATE TABLE pusher_daily_snapshots (
                    feature_id TEXT NOT NULL, day_start_at_ms INTEGER NOT NULL,
                    done_count INTEGER NOT NULL, total_count INTEGER NOT NULL,
                    completed_at_ms INTEGER NOT NULL,
                    PRIMARY KEY (feature_id, day_start_at_ms)
                )
                """)
            try db.execute(
                sql: "INSERT INTO business_days VALUES ('pusher', 0, 86400000)"
            )
            try db.execute(sql: "INSERT INTO feature_runtime_state VALUES ('pusher', 0, 44)")
            try db.execute(
                sql: "INSERT INTO pusher_series VALUES (?, 'Legacy Series', 'progress', 1, 43)",
                arguments: [seriesID]
            )
            try db.execute(
                sql: """
                INSERT INTO pusher_tasks
                    (id, feature_id, day_start_at_ms, title, urgency, status,
                     position, created_at_ms, updated_at_ms, archived, series_id)
                VALUES (?, 'pusher', 0, 'Preserved', 'urgent', 'processing', 7, 1, 2, 0, ?)
                """,
                arguments: [taskID, seriesID]
            )
            try db.execute(sql: "INSERT INTO pusher_daily_snapshots VALUES ('pusher', -1, 3, 5, 0)")
        }

        let migrated = try AppDatabase(
            path: path,
            featureMigrations: PusherDatabaseMigrations.all
        )
        try assertLegacyPusherRows(in: migrated, taskID: taskID, seriesID: seriesID)

        let reopenedWithoutPusher = try AppDatabase(path: path)
        try assertLegacyPusherRows(
            in: reopenedWithoutPusher,
            taskID: taskID,
            seriesID: seriesID
        )
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

    func testPusherRecoveryNeverOverwritesAPreexistingV1Snapshot() async throws {
        let database = try AppDatabase.inMemory()
        let repository = PusherGRDBRepository(database: database)
        let oldDay = makeDay(featureID: .pusher)
        let nextDay = makeDay(featureID: .pusher, start: 86_400)
        let task = try PusherTask(title: "Legacy", urgency: .urgent, businessDayID: oldDay.id)
        try await repository.saveBoard(PusherBoard(businessDay: oldDay, tasks: [task]))
        let current = try await repository.loadOrBootstrapCurrentBoard(resolvedToday: nextDay)
        let frozen = PusherDailySnapshot(
            businessDayID: oldDay.id,
            doneCount: 7,
            totalCount: 9,
            completedAtMilliseconds: oldDay.end.millisecondsSince1970
        )
        try await database.queue.write { db in
            try db.execute(
                sql: "INSERT INTO pusher_daily_snapshots VALUES (?, ?, ?, ?, ?)",
                arguments: [
                    frozen.businessDayID.featureID.rawValue,
                    frozen.businessDayID.startAtMilliseconds,
                    frozen.doneCount,
                    frozen.totalCount,
                    frozen.completedAtMilliseconds,
                ]
            )
        }
        let settlement = PusherSettlement.settle(
            current,
            into: nextDay,
            carryIncomplete: true,
            atMilliseconds: oldDay.end.millisecondsSince1970
        )

        _ = try await repository.advanceDay(settlement)

        let snapshots = try await repository.loadSnapshots(from: 0, to: 200_000_000)
        XCTAssertEqual(snapshots, [frozen])
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


    func testPusherMigrationCreatesOnlyPusherSchema() throws {
        let database = try AppDatabase.inMemory(
            featureMigrations: PusherDatabaseMigrations.all
        )
        let tables = try database.queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
        }

        XCTAssertTrue(tables.contains("pusher_series"))
        XCTAssertTrue(tables.contains("pusher_tasks"))
        XCTAssertTrue(tables.contains("pusher_daily_snapshots"))
        XCTAssertFalse(tables.contains("timer_templates"))
    }

    private func makeDay(featureID: FeatureID, start: TimeInterval = 0) -> BusinessDay {
        BusinessDay(
            featureID: featureID,
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: start + 86_400)
        )
    }

    private func assertLegacyPusherRows(
        in database: AppDatabase,
        taskID: String,
        seriesID: String
    ) throws {
        try database.queue.read { db in
            let series = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM pusher_series WHERE id = ?", arguments: [seriesID]))
            XCTAssertEqual(series["title"] as String?, "Legacy Series")
            XCTAssertEqual(series["urgency"] as String?, "progress")
            XCTAssertEqual(series["active"] as Bool?, true)
            XCTAssertEqual(series["updated_at_ms"] as Int64?, 43)

            let task = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM pusher_tasks WHERE id = ?", arguments: [taskID]))
            XCTAssertEqual(task["series_id"] as String?, seriesID)
            XCTAssertEqual(task["title"] as String?, "Preserved")
            XCTAssertEqual(task["urgency"] as String?, "urgent")
            XCTAssertEqual(task["status"] as String?, "processing")
            XCTAssertEqual(task["position"] as Int?, 7)
            XCTAssertEqual(task["created_at_ms"] as Int64?, 1)
            XCTAssertEqual(task["updated_at_ms"] as Int64?, 2)
            XCTAssertEqual(task["archived"] as Bool?, false)

            let snapshot = try XCTUnwrap(Row.fetchOne(db, sql: "SELECT * FROM pusher_daily_snapshots WHERE day_start_at_ms = -1"))
            XCTAssertEqual(snapshot["done_count"] as Int?, 3)
            XCTAssertEqual(snapshot["total_count"] as Int?, 5)
            XCTAssertEqual(snapshot["completed_at_ms"] as Int64?, 0)
            XCTAssertEqual(
                try Int64.fetchOne(db, sql: "SELECT current_day_start_at_ms FROM feature_runtime_state WHERE feature_id = 'pusher'"),
                0
            )
            XCTAssertEqual(
                try String.fetchOne(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'pusher_tasks_day_status_position'"),
                "pusher_tasks_day_status_position"
            )
            XCTAssertEqual(try String.fetchOne(db, sql: "PRAGMA integrity_check"), "ok")
        }
    }
}

private extension AppDatabase {
    static func inMemory() throws -> AppDatabase {
        try inMemory(featureMigrations: PusherDatabaseMigrations.all)
    }
}
