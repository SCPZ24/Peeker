import Foundation
import GRDB
import XCTest
import PeekerCore
import PersistenceCore
import TimerFeature
@testable import TimerGRDBAdapter

final class TimerTemporaryGRDBTests: XCTestCase {
    func testLegacySessionMigratesAsDaily() async throws {
        let database = try AppDatabase.inMemory(featureMigrations: TimerDatabaseMigrations.all)
        let kind = try await database.queue.write { db -> String? in
            try db.execute(
                sql: """
                INSERT INTO timer_sessions
                    (id, task_id, feature_id, day_start_at_ms, started_at_ms, active)
                VALUES (?, ?, 'timer', 0, 0, 0)
                """,
                arguments: [UUID().uuidString, UUID().uuidString]
            )
            return try String.fetchOne(db, sql: "SELECT task_kind FROM timer_sessions LIMIT 1")
        }
        XCTAssertEqual(kind, "daily")
    }

    func testNonExpiringRunningTaskSplitsAndContinuesAcrossBoundary() async throws {
        let (_, repository) = try makeRepository()
        let day = businessDay(start: 0)
        var state = try await repository.loadOrBootstrapCurrentDay(resolvedToday: day)
        let task = try TimerTemporaryTask(
            name: "Release", targetSeconds: 120, colorHex: "#4F9DFF",
            createdAtMilliseconds: 1_000, updatedAtMilliseconds: 1_000
        )
        try await repository.saveTemporaryTask(task)
        state = try await repository.loadOrBootstrapCurrentDay(resolvedToday: day)
        try state.start(identity: .temporary(taskID: task.id), atMilliseconds: 50_000)
        try await repository.commitTemporaryStart(state: state, task: state.temporaryTasks[0], session: state.activeSession!)
        let completion = try state.pause(atMilliseconds: 60_000, reason: .businessDayBoundary)!
        let snapshot = TimerDailySnapshot(
            businessDayID: day.id, completionRatio: state.completionRatio,
            completedAtMilliseconds: 60_000
        )

        let next = try await repository.advanceDay(TimerDayTransition(
            settledState: state, completion: completion, snapshot: snapshot,
            nextDay: businessDay(start: 60_000), continuingTemplateID: nil,
            continuingTemporaryTaskID: task.id, boundaryMilliseconds: 60_000
        ))

        XCTAssertEqual(next.activeSession?.identity, .temporary(taskID: task.id))
        XCTAssertEqual(next.temporaryTasks.first?.id, task.id)
        XCTAssertEqual(next.temporaryTasks.first?.accumulatedSeconds, 10)
        XCTAssertEqual(next.temporaryTasks.first?.status, .running)
    }

    func testExpireAndCompletedTasksArchiveAfterSnapshotBoundary() async throws {
        for (status, expire, reason) in [
            (TimerTaskStatus.idle, true, TimerTemporaryArchiveReason.expiredAtBoundary),
            (.paused, true, .expiredAtBoundary),
            (.completed, true, .expiredAtBoundary),
            (.completed, false, .completedAtBoundary),
        ] {
            let (database, repository) = try makeRepository()
            let day = businessDay(start: 0)
            var state = try await repository.loadOrBootstrapCurrentDay(resolvedToday: day)
            let task = try TimerTemporaryTask(
                name: "Temp", targetSeconds: 10, colorHex: "#34C759",
                accumulatedSeconds: status == .completed ? 10 : 0,
                status: status, expireOnRefresh: expire,
                createdAtMilliseconds: 1_000, updatedAtMilliseconds: 1_000
            )
            try await repository.saveTemporaryTask(task)
            state = try await repository.loadOrBootstrapCurrentDay(resolvedToday: day)
            let snapshot = TimerDailySnapshot(
                businessDayID: day.id, completionRatio: state.completionRatio,
                completedAtMilliseconds: 60_000
            )
            _ = try await repository.advanceDay(TimerDayTransition(
                settledState: state, completion: nil, snapshot: snapshot,
                nextDay: businessDay(start: 60_000), continuingTemplateID: nil,
                boundaryMilliseconds: 60_000
            ))
            let active = try await repository.loadTemporaryTasks()
            XCTAssertTrue(active.isEmpty)
            let storedReason = try await database.queue.read { db in
                try String.fetchOne(
                    db, sql: "SELECT archive_reason FROM timer_temporary_tasks WHERE id = ?",
                    arguments: [task.id.uuidString]
                )
            }
            XCTAssertEqual(storedReason, reason.rawValue)
        }
    }

    private func makeRepository() throws -> (AppDatabase, TimerGRDBRepository) {
        let database = try AppDatabase.inMemory(featureMigrations: TimerDatabaseMigrations.all)
        return (database, TimerGRDBRepository(database: database))
    }

    private func businessDay(start: Int64) -> BusinessDay {
        BusinessDay(
            featureID: .timer,
            start: Date(millisecondsSince1970: start),
            end: Date(millisecondsSince1970: start + 60_000)
        )
    }
}
