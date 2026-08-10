import GRDB
import PersistenceCore

public enum TimerDatabaseMigrations {
    public static let all: [AppDatabaseMigration] = [
        AppDatabaseMigration(id: "timer-schema-v1") { db in
            try db.create(table: "timer_templates", options: .ifNotExists) { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("target_seconds", .integer).notNull()
                table.column("color_hex", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
            }

            try db.create(table: "timer_day_instances", options: .ifNotExists) { table in
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

            try db.create(table: "timer_sessions", options: .ifNotExists) { table in
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
                sql: "CREATE UNIQUE INDEX IF NOT EXISTS timer_one_active_session ON timer_sessions(active) WHERE active = 1"
            )

            try db.create(table: "timer_daily_snapshots", options: .ifNotExists) { table in
                table.column("feature_id", .text).notNull()
                table.column("day_start_at_ms", .integer).notNull()
                table.column("completion_ratio", .double)
                table.column("completed_at_ms", .integer).notNull()
                table.primaryKey(["feature_id", "day_start_at_ms"])
            }
        },
    ]
}
