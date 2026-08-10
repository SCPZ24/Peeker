import GRDB
import PersistenceCore

public enum PusherDatabaseMigrations {
    public static let all: [AppDatabaseMigration] = [
        AppDatabaseMigration(id: "pusher-schema-v1") { db in
            try db.create(table: "pusher_series", options: .ifNotExists) { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("urgency", .text).notNull()
                table.column("active", .boolean).notNull().defaults(to: true)
                table.column("updated_at_ms", .integer).notNull()
            }

            try db.create(table: "pusher_tasks", options: .ifNotExists) { table in
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
                columns: ["feature_id", "day_start_at_ms", "status", "position"],
                options: .ifNotExists
            )

            try db.create(table: "pusher_daily_snapshots", options: .ifNotExists) { table in
                table.column("feature_id", .text).notNull()
                table.column("day_start_at_ms", .integer).notNull()
                table.column("done_count", .integer).notNull()
                table.column("total_count", .integer).notNull()
                table.column("completed_at_ms", .integer).notNull()
                table.primaryKey(["feature_id", "day_start_at_ms"])
            }
        },
    ]
}
