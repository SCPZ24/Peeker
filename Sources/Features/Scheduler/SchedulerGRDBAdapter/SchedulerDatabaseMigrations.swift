import GRDB
import PersistenceCore

public enum SchedulerDatabaseMigrations {
    public static let all = [AppDatabaseMigration(id: "scheduler-schema-v1") { db in
        try db.execute(sql: """
            CREATE TABLE scheduler_sources (
                id TEXT PRIMARY KEY NOT NULL,
                canonical_path TEXT NOT NULL UNIQUE,
                display_name TEXT NOT NULL,
                last_successful_import_at_ms INTEGER,
                last_attempt_at_ms INTEGER,
                last_result TEXT
            );
            CREATE TABLE scheduler_events (
                id TEXT PRIMARY KEY NOT NULL,
                source_id TEXT REFERENCES scheduler_sources(id) ON DELETE CASCADE,
                source_uid TEXT,
                source_segment_key TEXT,
                title TEXT NOT NULL,
                notes TEXT,
                location TEXT,
                color_hex TEXT NOT NULL,
                kind TEXT NOT NULL CHECK(kind IN ('timed','allDay')),
                start_at_ms INTEGER,
                end_at_ms INTEGER,
                normalized_timezone_id TEXT,
                start_date TEXT,
                end_date_exclusive TEXT,
                recurrence_json TEXT,
                created_at_ms INTEGER NOT NULL,
                updated_at_ms INTEGER NOT NULL,
                CHECK (
                    (kind = 'timed' AND start_at_ms IS NOT NULL AND end_at_ms > start_at_ms
                     AND normalized_timezone_id IS NOT NULL AND start_date IS NULL AND end_date_exclusive IS NULL)
                    OR
                    (kind = 'allDay' AND start_at_ms IS NULL AND end_at_ms IS NULL
                     AND normalized_timezone_id IS NULL AND start_date IS NOT NULL
                     AND end_date_exclusive > start_date)
                ),
                CHECK (
                    (source_id IS NULL AND source_uid IS NULL AND source_segment_key IS NULL)
                    OR
                    (source_id IS NOT NULL AND source_uid IS NOT NULL AND source_segment_key IS NOT NULL)
                )
            );
            CREATE UNIQUE INDEX scheduler_events_source_identity
              ON scheduler_events(source_id, source_uid, source_segment_key)
              WHERE source_id IS NOT NULL;
            CREATE INDEX scheduler_events_source_uid ON scheduler_events(source_id, source_uid);
            CREATE INDEX scheduler_events_timed_range ON scheduler_events(start_at_ms, end_at_ms) WHERE kind = 'timed';
            CREATE INDEX scheduler_events_all_day_range ON scheduler_events(start_date, end_date_exclusive) WHERE kind = 'allDay';
            CREATE TABLE scheduler_occurrence_overrides (
                id TEXT PRIMARY KEY NOT NULL,
                event_id TEXT NOT NULL REFERENCES scheduler_events(id) ON DELETE CASCADE,
                occurrence_key TEXT NOT NULL,
                is_cancelled INTEGER NOT NULL CHECK(is_cancelled IN (0,1)),
                replacement_json TEXT,
                updated_at_ms INTEGER NOT NULL,
                CHECK ((is_cancelled = 1 AND replacement_json IS NULL) OR (is_cancelled = 0 AND replacement_json IS NOT NULL)),
                UNIQUE(event_id, occurrence_key)
            );
            CREATE INDEX scheduler_overrides_event ON scheduler_occurrence_overrides(event_id);
            CREATE INDEX scheduler_events_source_fk ON scheduler_events(source_id);
            """)
    }]
}
