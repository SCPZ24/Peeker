import Foundation
import XCTest
import PeekerCore
import PersistenceCore
import TargetorFeature
@testable import TargetorGRDBAdapter

final class TargetorGRDBRepositoryTests: XCTestCase {
    func testMigrationCreatesCurrentPeriodUniquenessAndCompositeCheckinForeignKey() async throws {
        let database = try AppDatabase.inMemory(featureMigrations: TargetorDatabaseMigrations.all)
        let indexes = try await database.queue.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'targetor_%'")
        }
        XCTAssertTrue(indexes.contains("targetor_periods_one_current"))
        XCTAssertTrue(indexes.contains("targetor_checkins_period_time"))
    }

    func testRecoveryFillsZeroEventPeriodsIdempotently() async throws {
        let repository = try makeRepository()
        let target = try makeTarget(created: date("2026-08-10T10:00:00Z"), max: 2)
        let first = makePeriod(target: target, start: date("2026-08-10T10:00:00Z"), end: date("2026-08-11T00:00:00Z"))
        try await repository.create(target: target, firstPeriod: first)
        let resolver = TargetorPeriodResolver(calendar: calendar())

        try await repository.recover(now: date("2026-08-13T12:00:00Z"), refreshTime: .midnight, resolver: resolver)
        let firstHistory = try await repository.history(
            targetID: target.id,
            fromMilliseconds: date("2026-08-10T00:00:00Z").millisecondsSince1970,
            toMilliseconds: date("2026-08-14T00:00:00Z").millisecondsSince1970
        )
        try await repository.recover(now: date("2026-08-13T12:00:00Z"), refreshTime: .midnight, resolver: resolver)
        let secondHistory = try await repository.history(
            targetID: target.id,
            fromMilliseconds: date("2026-08-10T00:00:00Z").millisecondsSince1970,
            toMilliseconds: date("2026-08-14T00:00:00Z").millisecondsSince1970
        )

        XCTAssertEqual(firstHistory.periods.count, 4)
        XCTAssertEqual(firstHistory.periods.map(\.count), [0, 0, 0, 0])
        XCTAssertEqual(secondHistory.periods.map(\.id), firstHistory.periods.map(\.id))
    }

    func testConcurrentCheckinsCannotExceedMax() async throws {
        let repository = try makeRepository()
        let target = try makeTarget(created: date("2026-08-10T10:00:00Z"), max: 1)
        try await repository.create(
            target: target,
            firstPeriod: makePeriod(target: target, start: date("2026-08-10T10:00:00Z"), end: date("2026-08-11T00:00:00Z"))
        )

        let targetID = target.id
        let firstMilliseconds = date("2026-08-10T11:00:00Z").millisecondsSince1970
        let secondMilliseconds = date("2026-08-10T11:00:01Z").millisecondsSince1970
        let first = Task { try await repository.checkin(
            targetID: targetID, eventID: UUID(), atMilliseconds: firstMilliseconds
        ) }
        let second = Task { try await repository.checkin(
            targetID: targetID, eventID: UUID(), atMilliseconds: secondMilliseconds
        ) }
        var successCount = 0
        var errors: [TargetorError] = []
        for task in [first, second] {
            do { _ = try await task.value; successCount += 1 }
            catch let error as TargetorError { errors.append(error) }
        }

        XCTAssertEqual(successCount, 1)
        XCTAssertEqual(errors, [.cycleComplete])
    }

    func testUncheckOnlyDeletesCurrentEventAndArchivePreservesHistory() async throws {
        let repository = try makeRepository()
        let target = try makeTarget(created: date("2026-08-10T10:00:00Z"), max: 2)
        try await repository.create(
            target: target,
            firstPeriod: makePeriod(target: target, start: date("2026-08-10T10:00:00Z"), end: date("2026-08-11T00:00:00Z"))
        )
        let result = try await repository.checkin(
            targetID: target.id, eventID: UUID(), atMilliseconds: date("2026-08-10T11:00:00Z").millisecondsSince1970
        )
        let afterUncheck = try await repository.uncheck(eventID: result.event.id)
        XCTAssertEqual(afterUncheck.currentPeriod?.count, 0)

        _ = try await repository.checkin(
            targetID: target.id, eventID: UUID(), atMilliseconds: date("2026-08-10T12:00:00Z").millisecondsSince1970
        )
        _ = try await repository.archive(targetID: target.id, atMilliseconds: date("2026-08-10T13:00:00Z").millisecondsSince1970)
        let history = try await repository.history(targetID: target.id, fromMilliseconds: nil, toMilliseconds: nil)
        XCTAssertEqual(history.events.count, 1)
        let active = try await repository.snapshot(scope: .active)
        let archived = try await repository.snapshot(scope: .only)
        XCTAssertEqual(active.targets.count, 0)
        XCTAssertEqual(archived.targets.count, 1)
    }

    private func makeRepository() throws -> TargetorGRDBRepository {
        TargetorGRDBRepository(database: try AppDatabase.inMemory(featureMigrations: TargetorDatabaseMigrations.all))
    }

    private func makeTarget(created: Date, max: Int) throws -> TargetorTarget {
        try TargetorTarget(
            title: "Write", maxCount: max,
            createdAtMilliseconds: created.millisecondsSince1970,
            updatedAtMilliseconds: created.millisecondsSince1970
        )
    }

    private func makePeriod(target: TargetorTarget, start: Date, end: Date) -> TargetorPeriod {
        TargetorPeriod(
            targetID: target.id, sequence: 0,
            startMilliseconds: start.millisecondsSince1970,
            endMilliseconds: end.millisecondsSince1970,
            ruleSnapshot: target.periodRule, maxCountSnapshot: target.maxCount,
            createdAtMilliseconds: start.millisecondsSince1970
        )
    }

    private func calendar() -> Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value
    }
    private func date(_ raw: String) -> Date { ISO8601DateFormatter().date(from: raw)! }
}
