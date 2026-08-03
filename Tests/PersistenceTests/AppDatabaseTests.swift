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

    private func makeDay(featureID: FeatureID) -> BusinessDay {
        BusinessDay(
            featureID: featureID,
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86_400)
        )
    }
}
