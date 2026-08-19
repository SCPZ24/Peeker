import GRDB
import XCTest
import PersistenceCore
import SchedulerFeature
@testable import SchedulerGRDBAdapter

final class SchedulerGRDBAdapterTests: XCTestCase {
    func testMigrationAppendsOnlySchedulerTablesAndIsIdempotent() throws {
        let database = try AppDatabase.inMemory(featureMigrations: SchedulerDatabaseMigrations.all)
        try database.migrate()
        let tables = try database.queue.read { db in Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'")) }
        XCTAssertTrue(tables.isSuperset(of: ["business_days", "feature_runtime_state", "scheduler_sources", "scheduler_events", "scheduler_occurrence_overrides"]))
        XCTAssertFalse(tables.contains("timer_templates"))
    }

    func testEventOverrideAndSourceCascadeRoundTrip() async throws {
        let database = try AppDatabase.inMemory(featureMigrations: SchedulerDatabaseMigrations.all)
        let repository = SchedulerGRDBRepository(database: database)
        let source = SchedulerSource(canonicalPath: "/tmp/test.ics", displayName: "test.ics")
        try await repository.saveSource(source)
        let event = try SchedulerEvent(
            sourceID: source.id, sourceUID: "uid", sourceSegmentKey: "root", title: "Imported",
            time: .timed(startMilliseconds: 1000, endMilliseconds: 2000, timeZoneID: "UTC")
        )
        _ = try await repository.save(event)
        let replacement = SchedulerOccurrence(
            eventID: event.id, originalKey: "1000", title: "Changed", notes: nil, location: nil,
            colorHex: "#0A84FF", time: event.time, recurring: false, isException: true, sourceID: source.id
        )
        try await repository.saveOverride(SchedulerOccurrenceOverride(
            eventID: event.id, occurrenceKey: "1000", isCancelled: false, replacement: replacement
        ))
        let beforeRemoval = try await repository.snapshot()
        XCTAssertEqual(beforeRemoval.overrides.count, 1)
        let removed = try await repository.removeSource(id: source.id)
        XCTAssertEqual(removed, 1)
        let afterRemoval = try await repository.snapshot()
        XCTAssertTrue(afterRemoval.events.isEmpty)
    }
}
