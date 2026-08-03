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

    private func makeDay(featureID: FeatureID) -> BusinessDay {
        BusinessDay(
            featureID: featureID,
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 86_400)
        )
    }
}
