import Foundation
import GRDB
import PeekerCore

public final class AppDatabase: @unchecked Sendable {
    public let queue: DatabaseQueue

    public init(path: String) throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        queue = try DatabaseQueue(path: path, configuration: Self.configuration)
        try migrate()
    }

    private init(queue: DatabaseQueue) throws {
        self.queue = queue
        try migrate()
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(queue: DatabaseQueue(configuration: configuration))
    }

    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("Peeker", isDirectory: true)
            .appendingPathComponent("Peeker.sqlite", isDirectory: false)
    }

    public func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "business_days") { table in
                table.column("feature_id", .text).notNull()
                table.column("start_at_ms", .integer).notNull()
                table.column("end_at_ms", .integer).notNull()
                table.primaryKey(["feature_id", "start_at_ms"])
            }

            try db.create(table: "timer_templates") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("target_seconds", .integer).notNull()
                table.column("color_hex", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
            }

            try db.create(table: "timer_day_instances") { table in
                table.column("id", .text).primaryKey()
                table.column("template_id", .text).notNull()
                table.column("feature_id", .text).notNull()
                table.column("day_start_at_ms", .integer).notNull()
                table.column("name", .text).notNull()
                table.column("target_seconds", .integer).notNull()
                table.column("color_hex", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("accumulated_seconds", .integer).notNull().defaults(to: 0)
                table.column("status", .text).notNull()
                table.column("last_action_at_ms", .integer)
                table.column("visible", .boolean).notNull().defaults(to: true)
                table.uniqueKey(["template_id", "feature_id", "day_start_at_ms"])
            }

            try db.create(table: "timer_sessions") { table in
                table.column("id", .text).primaryKey()
                table.column("task_id", .text).notNull()
                table.column("feature_id", .text).notNull()
                table.column("day_start_at_ms", .integer).notNull()
                table.column("started_at_ms", .integer).notNull()
                table.column("ended_at_ms", .integer)
                table.column("credited_seconds", .integer)
                table.column("end_reason", .text)
                table.column("active", .boolean).notNull().defaults(to: true)
            }
            try db.execute(
                sql: "CREATE UNIQUE INDEX timer_one_active_session ON timer_sessions(active) WHERE active = 1"
            )

            try db.create(table: "timer_daily_snapshots") { table in
                table.column("feature_id", .text).notNull()
                table.column("day_start_at_ms", .integer).notNull()
                table.column("completion_ratio", .double)
                table.column("completed_at_ms", .integer).notNull()
                table.primaryKey(["feature_id", "day_start_at_ms"])
            }

            try db.create(table: "pusher_series") { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("urgency", .text).notNull()
                table.column("active", .boolean).notNull().defaults(to: true)
                table.column("updated_at_ms", .integer).notNull()
            }

            try db.create(table: "pusher_tasks") { table in
                table.column("id", .text).primaryKey()
                table.column("series_id", .text)
                table.column("feature_id", .text).notNull()
                table.column("day_start_at_ms", .integer).notNull()
                table.column("title", .text).notNull()
                table.column("urgency", .text).notNull()
                table.column("status", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("created_at_ms", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
                table.column("archived", .boolean).notNull().defaults(to: false)
            }
            try db.create(
                index: "pusher_tasks_day_status_position",
                on: "pusher_tasks",
                columns: ["feature_id", "day_start_at_ms", "status", "position"]
            )

            try db.create(table: "pusher_daily_snapshots") { table in
                table.column("feature_id", .text).notNull()
                table.column("day_start_at_ms", .integer).notNull()
                table.column("done_count", .integer).notNull()
                table.column("total_count", .integer).notNull()
                table.column("completed_at_ms", .integer).notNull()
                table.primaryKey(["feature_id", "day_start_at_ms"])
            }
        }
        migrator.registerMigration("v2-feature-runtime-state") { db in
            try db.create(table: "feature_runtime_state") { table in
                table.column("feature_id", .text).primaryKey()
                table.column("current_day_start_at_ms", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
                table.foreignKey(
                    ["feature_id", "current_day_start_at_ms"],
                    references: "business_days",
                    columns: ["feature_id", "start_at_ms"]
                )
            }
        }
        try migrator.migrate(queue)
    }

    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return configuration
    }
}

public func persistBusinessDay(_ day: BusinessDay, in db: Database) throws {
    try db.execute(
        sql: """
        INSERT INTO business_days (feature_id, start_at_ms, end_at_ms)
        VALUES (?, ?, ?)
        ON CONFLICT(feature_id, start_at_ms) DO UPDATE SET end_at_ms = excluded.end_at_ms
        """,
        arguments: [day.id.featureID.rawValue, day.id.startAtMilliseconds, day.end.millisecondsSince1970]
    )
}
