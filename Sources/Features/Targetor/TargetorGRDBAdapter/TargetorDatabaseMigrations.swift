import GRDB
import PersistenceCore

public enum TargetorDatabaseMigrations {
    public static let all: [AppDatabaseMigration] = [
        AppDatabaseMigration(id: "targetor-schema-v1") { db in
            try db.create(table: "targetor_targets", options: .ifNotExists) { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("description", .text)
                table.column("icon_name", .text).notNull()
                table.column("frequency", .text).notNull()
                table.column("weekday", .text)
                table.column("month_day", .integer)
                table.column("max_count", .integer).notNull()
                table.column("position", .integer).notNull()
                table.column("created_at_ms", .integer).notNull()
                table.column("updated_at_ms", .integer).notNull()
                table.column("archived_at_ms", .integer)
            }
            try db.create(
                index: "targetor_targets_active_position",
                on: "targetor_targets", columns: ["archived_at_ms", "position"], options: .ifNotExists
            )

            try db.create(table: "targetor_periods", options: .ifNotExists) { table in
                table.column("id", .text).primaryKey()
                table.column("target_id", .text).notNull().references("targetor_targets", onDelete: .restrict)
                table.column("sequence", .integer).notNull()
                table.column("start_at_ms", .integer).notNull()
                table.column("end_at_ms", .integer).notNull()
                table.column("frequency", .text).notNull()
                table.column("weekday", .text)
                table.column("month_day", .integer)
                table.column("max_count", .integer).notNull()
                table.column("created_at_ms", .integer).notNull()
                table.column("settled_at_ms", .integer)
                table.uniqueKey(["target_id", "start_at_ms"])
                table.uniqueKey(["target_id", "sequence"])
                table.uniqueKey(["id", "target_id"])
            }
            try db.create(
                index: "targetor_periods_target_interval",
                on: "targetor_periods", columns: ["target_id", "start_at_ms", "end_at_ms"], options: .ifNotExists
            )
            try db.execute(sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS targetor_periods_one_current
                ON targetor_periods(target_id) WHERE settled_at_ms IS NULL
                """)

            try db.create(table: "targetor_checkins", options: .ifNotExists) { table in
                table.column("id", .text).primaryKey()
                table.column("target_id", .text).notNull()
                table.column("period_id", .text).notNull()
                table.column("occurred_at_ms", .integer).notNull()
                table.foreignKey(
                    ["period_id", "target_id"],
                    references: "targetor_periods", columns: ["id", "target_id"], onDelete: .restrict
                )
            }
            try db.create(
                index: "targetor_checkins_period_time",
                on: "targetor_checkins", columns: ["period_id", "occurred_at_ms"], options: .ifNotExists
            )
        },
    ]
}
