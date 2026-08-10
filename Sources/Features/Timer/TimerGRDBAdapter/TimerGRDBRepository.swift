import Foundation
import GRDB
import PeekerCore
import PersistenceCore
import TimerFeature

public final class TimerGRDBRepository: TimerRepository, @unchecked Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func loadOrBootstrapCurrentDay(resolvedToday: BusinessDay) async throws -> TimerDayState {
        try await database.queue.write { db in
            let featureID = FeatureID.timer.rawValue
            let storedStart = try Int64.fetchOne(
                db,
                sql: "SELECT current_day_start_at_ms FROM feature_runtime_state WHERE feature_id = ?",
                arguments: [featureID]
            )
            let day: BusinessDay
            if let storedStart {
                day = try Self.fetchBusinessDay(featureID: .timer, startMilliseconds: storedStart, db: db)
            } else {
                let activeSessionStart = try Int64.fetchOne(
                    db,
                    sql: """
                    SELECT day_start_at_ms FROM timer_sessions
                    WHERE feature_id = ? AND active = 1
                    ORDER BY started_at_ms DESC LIMIT 1
                    """,
                    arguments: [featureID]
                )
                let latestInstanceStart = try Int64.fetchOne(
                    db,
                    sql: "SELECT MAX(day_start_at_ms) FROM timer_day_instances WHERE feature_id = ?",
                    arguments: [featureID]
                )
                let settledEmptyDayStart = try Int64.fetchOne(
                    db,
                    sql: """
                    SELECT MAX(next_day.start_at_ms)
                    FROM business_days AS next_day
                    JOIN timer_daily_snapshots AS snapshot
                      ON snapshot.feature_id = next_day.feature_id
                     AND snapshot.completed_at_ms = next_day.start_at_ms
                    WHERE next_day.feature_id = ?
                    """,
                    arguments: [featureID]
                )
                let candidate = activeSessionStart
                    ?? [latestInstanceStart, settledEmptyDayStart].compactMap({ $0 }).max()
                if let candidate {
                    day = try Self.fetchBusinessDay(featureID: .timer, startMilliseconds: candidate, db: db)
                } else {
                    try persistBusinessDay(resolvedToday, in: db)
                    day = resolvedToday
                }
                try Self.moveRuntimePointer(
                    to: day,
                    updatedAtMilliseconds: Date().millisecondsSince1970,
                    db: db
                )
            }
            try Self.ensureDayInstances(day, db: db)
            return try Self.fetchDay(day, db: db)
        }
    }

    public func advanceDay(_ transition: TimerDayTransition) async throws -> TimerDayState {
        try await database.queue.write { db in
            try Self.requireRuntimePointer(
                featureID: .timer,
                startMilliseconds: transition.settledState.businessDay.id.startAtMilliseconds,
                db: db
            )
            try persistBusinessDay(transition.settledState.businessDay, in: db)
            for task in transition.settledState.tasks { try Self.upsert(task, db: db) }
            if let completion = transition.completion { try Self.finish(completion, db: db) }
            try db.execute(
                sql: """
                INSERT INTO timer_daily_snapshots
                    (feature_id, day_start_at_ms, completion_ratio, completed_at_ms)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(feature_id, day_start_at_ms) DO NOTHING
                """,
                arguments: [
                    transition.snapshot.businessDayID.featureID.rawValue,
                    transition.snapshot.businessDayID.startAtMilliseconds,
                    transition.snapshot.completionRatio,
                    transition.snapshot.completedAtMilliseconds,
                ]
            )
            try persistBusinessDay(transition.nextDay, in: db)
            try Self.ensureDayInstances(transition.nextDay, db: db)
            var nextState = try Self.fetchDay(transition.nextDay, db: db)
            if let templateID = transition.continuingTemplateID,
               let task = nextState.tasks.first(where: { $0.templateID == templateID }) {
                try nextState.start(taskID: task.id, atMilliseconds: transition.boundaryMilliseconds)
                for nextTask in nextState.tasks { try Self.upsert(nextTask, db: db) }
                if let session = nextState.activeSession { try Self.insertSession(session, db: db) }
            }
            try Self.moveRuntimePointer(
                to: transition.nextDay,
                updatedAtMilliseconds: transition.boundaryMilliseconds,
                db: db
            )
            return nextState
        }
    }

    public func updateCurrentBusinessDay(_ day: BusinessDay) async throws {
        try await database.queue.write { db in
            try Self.requireRuntimePointer(
                featureID: .timer,
                startMilliseconds: day.id.startAtMilliseconds,
                db: db
            )
            try persistBusinessDay(day, in: db)
        }
    }

    public func loadTemplates() async throws -> [TimerTemplate] {
        try await database.queue.read { db in try Self.fetchTemplates(db) }
    }

    public func saveTemplate(_ template: TimerTemplate) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO timer_templates (id, name, target_seconds, color_hex, position, updated_at_ms)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    target_seconds = excluded.target_seconds,
                    color_hex = excluded.color_hex,
                    position = excluded.position,
                    updated_at_ms = excluded.updated_at_ms
                """,
                arguments: [
                    template.id.uuidString, template.name, template.targetSeconds,
                    template.colorHex, template.position, template.updatedAtMilliseconds,
                ]
            )
            try db.execute(
                sql: """
                UPDATE timer_day_instances
                SET name = ?, target_seconds = ?, color_hex = ?, position = ?,
                    accumulated_seconds = MIN(accumulated_seconds, ?),
                    status = CASE
                        WHEN MIN(accumulated_seconds, ?) >= ? THEN 'completed'
                        WHEN status = 'completed' THEN 'paused'
                        ELSE status
                    END
                WHERE template_id = ? AND visible = 1
                """,
                arguments: [
                    template.name, template.targetSeconds, template.colorHex, template.position,
                    template.targetSeconds, template.targetSeconds, template.targetSeconds,
                    template.id.uuidString,
                ]
            )
        }
    }

    public func deleteTemplate(id: UUID) async throws {
        try await database.queue.write { db in
            try db.execute(sql: "DELETE FROM timer_templates WHERE id = ?", arguments: [id.uuidString])
            try db.execute(
                sql: "UPDATE timer_day_instances SET visible = 0 WHERE template_id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    public func loadOrCreateDay(_ day: BusinessDay) async throws -> TimerDayState {
        try await database.queue.write { db in
            try persistBusinessDay(day, in: db)
            try Self.ensureDayInstances(day, db: db)
            return try Self.fetchDay(day, db: db)
        }
    }

    public func saveDay(_ state: TimerDayState) async throws {
        try await database.queue.write { db in
            try persistBusinessDay(state.businessDay, in: db)
            for task in state.tasks {
                try Self.upsert(task, db: db)
            }
        }
    }

    public func beginSession(_ session: TimerSession) async throws {
        try await database.queue.write { db in
            try Self.insertSession(session, db: db)
        }
    }

    public func commitStart(state: TimerDayState, session: TimerSession) async throws {
        try await database.queue.write { db in
            try persistBusinessDay(state.businessDay, in: db)
            for task in state.tasks { try Self.upsert(task, db: db) }
            try Self.insertSession(session, db: db)
        }
    }

    public func completeSession(_ completion: TimerSessionCompletion) async throws {
        try await database.queue.write { db in
            try Self.finish(completion, db: db)
        }
    }

    public func interruptSession(_ interruption: TimerSessionInterruption) async throws {
        try await completeSession(interruption)
    }

    public func commitCompletion(state: TimerDayState, completion: TimerSessionCompletion) async throws {
        try await database.queue.write { db in
            for task in state.tasks { try Self.upsert(task, db: db) }
            try Self.finish(completion, db: db)
        }
    }

    public func loadSnapshots(from startMilliseconds: Int64, to endMilliseconds: Int64) async throws -> [TimerDailySnapshot] {
        try await database.queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM timer_daily_snapshots
                WHERE day_start_at_ms >= ? AND day_start_at_ms < ?
                ORDER BY day_start_at_ms
                """,
                arguments: [startMilliseconds, endMilliseconds]
            )
            return rows.map { row in
                TimerDailySnapshot(
                    businessDayID: BusinessDayID(
                        featureID: FeatureID(rawValue: row["feature_id"]),
                        startAtMilliseconds: row["day_start_at_ms"]
                    ),
                    completionRatio: row["completion_ratio"],
                    completedAtMilliseconds: row["completed_at_ms"]
                )
            }
        }
    }

    private static func fetchTemplates(_ db: Database) throws -> [TimerTemplate] {
        try Row.fetchAll(db, sql: "SELECT * FROM timer_templates ORDER BY position, updated_at_ms").map { row in
            try TimerTemplate(
                id: UUID(uuidString: row["id"])!,
                name: row["name"],
                targetSeconds: row["target_seconds"],
                colorHex: row["color_hex"],
                position: row["position"],
                updatedAtMilliseconds: row["updated_at_ms"]
            )
        }
    }

    private static func ensureDayInstances(_ day: BusinessDay, db: Database) throws {
        for template in try fetchTemplates(db) {
            try db.execute(
                sql: """
                INSERT INTO timer_day_instances
                    (id, template_id, feature_id, day_start_at_ms, name, target_seconds,
                     color_hex, position, accumulated_seconds, status, visible)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 'idle', 1)
                ON CONFLICT(template_id, feature_id, day_start_at_ms) DO NOTHING
                """,
                arguments: [
                    UUID().uuidString, template.id.uuidString, day.id.featureID.rawValue,
                    day.id.startAtMilliseconds, template.name, template.targetSeconds,
                    template.colorHex, template.position,
                ]
            )
        }
    }

    private static func fetchBusinessDay(
        featureID: FeatureID,
        startMilliseconds: Int64,
        db: Database
    ) throws -> BusinessDay {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM business_days WHERE feature_id = ? AND start_at_ms = ?",
            arguments: [featureID.rawValue, startMilliseconds]
        ) else { throw TimerPersistenceError.missingBusinessDay }
        return BusinessDay(
            featureID: featureID,
            start: Date(millisecondsSince1970: row["start_at_ms"]),
            end: Date(millisecondsSince1970: row["end_at_ms"])
        )
    }

    private static func moveRuntimePointer(
        to day: BusinessDay,
        updatedAtMilliseconds: Int64,
        db: Database
    ) throws {
        try persistBusinessDay(day, in: db)
        try db.execute(
            sql: """
            INSERT INTO feature_runtime_state (feature_id, current_day_start_at_ms, updated_at_ms)
            VALUES (?, ?, ?)
            ON CONFLICT(feature_id) DO UPDATE SET
                current_day_start_at_ms = excluded.current_day_start_at_ms,
                updated_at_ms = excluded.updated_at_ms
            """,
            arguments: [day.id.featureID.rawValue, day.id.startAtMilliseconds, updatedAtMilliseconds]
        )
    }

    private static func requireRuntimePointer(
        featureID: FeatureID,
        startMilliseconds: Int64,
        db: Database
    ) throws {
        let stored = try Int64.fetchOne(
            db,
            sql: "SELECT current_day_start_at_ms FROM feature_runtime_state WHERE feature_id = ?",
            arguments: [featureID.rawValue]
        )
        guard stored == startMilliseconds else { throw TimerPersistenceError.staleTransition }
    }

    private static func fetchDay(_ day: BusinessDay, db: Database) throws -> TimerDayState {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT * FROM timer_day_instances
            WHERE feature_id = ? AND day_start_at_ms = ?
            ORDER BY position
            """,
            arguments: [day.id.featureID.rawValue, day.id.startAtMilliseconds]
        )
        let tasks = try rows.map { row in
            let lastAction: Int64? = row["last_action_at_ms"]
            return try TimerTaskInstance(
                id: UUID(uuidString: row["id"])!,
                template: TimerTemplate(
                    id: UUID(uuidString: row["template_id"])!,
                    name: row["name"],
                    targetSeconds: row["target_seconds"],
                    colorHex: row["color_hex"],
                    position: row["position"],
                    updatedAtMilliseconds: lastAction ?? 0
                ),
                businessDayID: day.id,
                accumulatedSeconds: row["accumulated_seconds"],
                status: TimerTaskStatus(rawValue: row["status"]) ?? .idle,
                lastActionAtMilliseconds: lastAction,
                isVisible: row["visible"]
            )
        }
        let activeRow = try Row.fetchOne(
            db,
            sql: """
            SELECT * FROM timer_sessions
            WHERE feature_id = ? AND day_start_at_ms = ? AND active = 1
            LIMIT 1
            """,
            arguments: [day.id.featureID.rawValue, day.id.startAtMilliseconds]
        )
        let active = activeRow.map { row in
            TimerSession(
                id: UUID(uuidString: row["id"])!,
                taskID: UUID(uuidString: row["task_id"])!,
                businessDayID: day.id,
                startedAtMilliseconds: row["started_at_ms"]
            )
        }
        return TimerDayState(businessDay: day, tasks: tasks, activeSession: active)
    }

    private static func upsert(_ task: TimerTaskInstance, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO timer_day_instances
            (id, template_id, feature_id, day_start_at_ms, name, target_seconds,
             color_hex, position, accumulated_seconds, status, last_action_at_ms, visible)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                target_seconds = excluded.target_seconds,
                color_hex = excluded.color_hex,
                position = excluded.position,
                accumulated_seconds = excluded.accumulated_seconds,
                status = excluded.status,
                last_action_at_ms = excluded.last_action_at_ms,
                visible = excluded.visible
            """,
            arguments: [
                task.id.uuidString, task.templateID.uuidString,
                task.businessDayID.featureID.rawValue, task.businessDayID.startAtMilliseconds,
                task.name, task.targetSeconds, task.colorHex, task.position,
                task.accumulatedSeconds, task.status.rawValue,
                task.lastActionAtMilliseconds, task.isVisible,
            ]
        )
    }

    private static func finish(_ completion: TimerSessionCompletion, db: Database) throws {
        try db.execute(
            sql: """
            UPDATE timer_sessions
            SET ended_at_ms = ?, credited_seconds = ?, end_reason = ?, active = 0
            WHERE id = ? AND active = 1
            """,
            arguments: [
                completion.endedAtMilliseconds, completion.creditedSeconds,
                completion.endReason.rawValue, completion.session.id.uuidString,
            ]
        )
    }

    private static func insertSession(_ session: TimerSession, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO timer_sessions
                (id, task_id, feature_id, day_start_at_ms, started_at_ms, active)
            VALUES (?, ?, ?, ?, ?, 1)
            """,
            arguments: [
                session.id.uuidString, session.taskID.uuidString,
                session.businessDayID.featureID.rawValue,
                session.businessDayID.startAtMilliseconds,
                session.startedAtMilliseconds,
            ]
        )
    }
}

private enum TimerPersistenceError: Error {
    case missingBusinessDay
    case staleTransition
}
