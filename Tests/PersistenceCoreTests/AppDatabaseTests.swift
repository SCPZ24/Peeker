import XCTest
import GRDB
import PeekerCore
import PersistenceCore

final class AppDatabaseTests: XCTestCase {
    func testMigrationIsIdempotentAndCreatesOnlySharedTablesWithoutFeatures() throws {
        let database = try AppDatabase.inMemory()
        try database.migrate()

        let tables = try tableNames(in: database)

        XCTAssertTrue(tables.contains("business_days"))
        XCTAssertTrue(tables.contains("feature_runtime_state"))
        XCTAssertFalse(tables.contains("timer_templates"))
        XCTAssertFalse(tables.contains("pusher_tasks"))
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

}

final class AppDatabaseMigrationCompositionTests: XCTestCase {
    func testInMemoryDatabaseComposesOnlyProvidedFeatureMigrations() throws {
        let first = AppDatabaseMigration(id: "first-schema-v1") { db in
            try db.create(table: "first_items") { table in
                table.column("id", .text).primaryKey()
            }
        }
        let second = AppDatabaseMigration(id: "second-schema-v1") { db in
            try db.create(table: "second_items") { table in
                table.column("id", .text).primaryKey()
            }
        }

        let database = try AppDatabase.inMemory(featureMigrations: [first, second])
        let tables = try tableNames(in: database)

        XCTAssertTrue(tables.contains("business_days"))
        XCTAssertTrue(tables.contains("feature_runtime_state"))
        XCTAssertTrue(tables.contains("first_items"))
        XCTAssertTrue(tables.contains("second_items"))
        XCTAssertFalse(tables.contains("timer_templates"))
        XCTAssertFalse(tables.contains("pusher_tasks"))
    }

    func testDuplicateFeatureMigrationIdentifiersAreRejectedBeforeMigrationRuns() throws {
        let first = AppDatabaseMigration(id: "duplicate-v1") { db in
            try db.create(table: "first_table") { _ in }
        }
        let second = AppDatabaseMigration(id: "duplicate-v1") { db in
            try db.create(table: "second_table") { _ in }
        }

        XCTAssertThrowsError(
            try AppDatabase.inMemory(featureMigrations: [first, second])
        ) { error in
            XCTAssertEqual(
                error as? AppDatabaseMigrationError,
                .duplicateIdentifier("duplicate-v1")
            )
        }
    }

    func testDuplicateFeatureMigrationIdentifiersAreRejectedBeforeOpeningAFileDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("peeker-duplicate-migration-\(UUID().uuidString)")
        let path = directory.appendingPathComponent("Peeker.sqlite").path
        defer { try? FileManager.default.removeItem(at: directory) }
        let duplicate = [
            AppDatabaseMigration(id: "duplicate-v1") { _ in },
            AppDatabaseMigration(id: "duplicate-v1") { _ in },
        ]

        XCTAssertThrowsError(
            try AppDatabase(path: path, featureMigrations: duplicate)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testFeatureMigrationCannotReuseASharedMigrationIdentifier() {
        XCTAssertThrowsError(
            try AppDatabase.inMemory(
                featureMigrations: [AppDatabaseMigration(id: "v1") { _ in }]
            )
        ) { error in
            XCTAssertEqual(
                error as? AppDatabaseMigrationError,
                .duplicateIdentifier("v1")
            )
        }
    }
}

private func tableNames(in database: AppDatabase) throws -> [String] {
    try database.queue.read { db in
        try String.fetchAll(
            db,
            sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
        )
    }
}
