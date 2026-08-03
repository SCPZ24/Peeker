import Foundation
import GRDB
import PeekerCore
import PersistenceCore
import PusherFeature

public final class PusherGRDBRepository: PusherRepository, @unchecked Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func loadOrCreateDay(_ day: BusinessDay) async throws -> PusherBoard {
        try await database.queue.write { db in
            try persistBusinessDay(day, in: db)
            return try Self.fetchBoard(day, db: db)
        }
    }

    public func saveBoard(_ board: PusherBoard) async throws {
        try await database.queue.write { db in
            try persistBusinessDay(board.businessDay, in: db)
            try db.execute(
                sql: "UPDATE pusher_tasks SET archived = 1 WHERE feature_id = ? AND day_start_at_ms = ?",
                arguments: [board.businessDay.id.featureID.rawValue, board.businessDay.id.startAtMilliseconds]
            )
            for task in board.allTasks { try Self.upsert(task, archived: false, db: db) }
        }
    }

    public func insertTask(_ task: PusherTask, at index: Int) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: """
                UPDATE pusher_tasks SET position = position + 1
                WHERE feature_id = ? AND day_start_at_ms = ? AND status = 'planned'
                  AND archived = 0 AND position >= ?
                """,
                arguments: [task.businessDayID.featureID.rawValue, task.businessDayID.startAtMilliseconds, index]
            )
            var inserted = task
            inserted.status = .planned
            inserted.position = index
            try Self.upsert(inserted, archived: false, db: db)
            try Self.upsertSeriesIfNeeded(inserted, db: db)
        }
    }

    public func updateTask(_ task: PusherTask) async throws {
        try await database.queue.write { db in
            try Self.upsert(task, archived: false, db: db)
            try Self.upsertSeriesIfNeeded(task, db: db)
        }
    }

    public func deleteTask(id: UUID) async throws {
        try await database.queue.write { db in
            if let seriesID = try String.fetchOne(
                db,
                sql: "SELECT series_id FROM pusher_tasks WHERE id = ?",
                arguments: [id.uuidString]
            ) {
                try db.execute(
                    sql: "UPDATE pusher_series SET active = 0 WHERE id = ?",
                    arguments: [seriesID]
                )
            }
            try db.execute(
                sql: "UPDATE pusher_tasks SET archived = 1 WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    public func reorderTasks(businessDayID: BusinessDayID, orderedTasks: [PusherTask]) async throws {
        try await database.queue.write { db in
            for status in PusherStatus.allCases {
                for (position, task) in orderedTasks
                    .filter({ $0.status == status })
                    .sorted(by: { $0.position < $1.position })
                    .enumerated() {
                    try db.execute(
                        sql: """
                        UPDATE pusher_tasks SET status = ?, position = ?, updated_at_ms = ?
                        WHERE id = ? AND feature_id = ? AND day_start_at_ms = ? AND archived = 0
                        """,
                        arguments: [
                            status.rawValue, position, task.updatedAtMilliseconds,
                            task.id.uuidString, businessDayID.featureID.rawValue,
                            businessDayID.startAtMilliseconds,
                        ]
                    )
                }
            }
        }
    }

    public func saveSnapshot(_ snapshot: PusherDailySnapshot) async throws {
        try await database.queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO pusher_daily_snapshots
                (feature_id, day_start_at_ms, done_count, total_count, completed_at_ms)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(feature_id, day_start_at_ms) DO NOTHING
                """,
                arguments: [
                    snapshot.businessDayID.featureID.rawValue,
                    snapshot.businessDayID.startAtMilliseconds,
                    snapshot.doneCount, snapshot.totalCount, snapshot.completedAtMilliseconds,
                ]
            )
        }
    }

    public func loadSnapshots(from startMilliseconds: Int64, to endMilliseconds: Int64) async throws -> [PusherDailySnapshot] {
        try await database.queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM pusher_daily_snapshots
                WHERE day_start_at_ms >= ? AND day_start_at_ms < ?
                ORDER BY day_start_at_ms
                """,
                arguments: [startMilliseconds, endMilliseconds]
            ).map { row in
                PusherDailySnapshot(
                    businessDayID: BusinessDayID(
                        featureID: FeatureID(rawValue: row["feature_id"]),
                        startAtMilliseconds: row["day_start_at_ms"]
                    ),
                    doneCount: row["done_count"],
                    totalCount: row["total_count"],
                    completedAtMilliseconds: row["completed_at_ms"]
                )
            }
        }
    }

    private static func fetchBoard(_ day: BusinessDay, db: Database) throws -> PusherBoard {
        let tasks = try Row.fetchAll(
            db,
            sql: """
            SELECT * FROM pusher_tasks
            WHERE feature_id = ? AND day_start_at_ms = ? AND archived = 0
            ORDER BY status, position
            """,
            arguments: [day.id.featureID.rawValue, day.id.startAtMilliseconds]
        ).map { row in
            let seriesRaw: String? = row["series_id"]
            return try PusherTask(
                id: UUID(uuidString: row["id"])!,
                seriesID: seriesRaw.flatMap(UUID.init(uuidString:)),
                title: row["title"],
                urgency: PusherUrgency(rawValue: row["urgency"]) ?? .planning,
                status: PusherStatus(rawValue: row["status"]) ?? .planned,
                position: row["position"],
                businessDayID: day.id,
                createdAtMilliseconds: row["created_at_ms"],
                updatedAtMilliseconds: row["updated_at_ms"]
            )
        }
        return PusherBoard(businessDay: day, tasks: tasks)
    }

    private static func upsert(_ task: PusherTask, archived: Bool, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO pusher_tasks
            (id, series_id, feature_id, day_start_at_ms, title, urgency, status,
             position, created_at_ms, updated_at_ms, archived)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                series_id = excluded.series_id,
                feature_id = excluded.feature_id,
                day_start_at_ms = excluded.day_start_at_ms,
                title = excluded.title,
                urgency = excluded.urgency,
                status = excluded.status,
                position = excluded.position,
                updated_at_ms = excluded.updated_at_ms,
                archived = excluded.archived
            """,
            arguments: [
                task.id.uuidString, task.seriesID?.uuidString,
                task.businessDayID.featureID.rawValue, task.businessDayID.startAtMilliseconds,
                task.title, task.urgency.rawValue, task.status.rawValue, task.position,
                task.createdAtMilliseconds, task.updatedAtMilliseconds, archived,
            ]
        )
        try upsertSeriesIfNeeded(task, db: db)
    }

    private static func upsertSeriesIfNeeded(_ task: PusherTask, db: Database) throws {
        guard let seriesID = task.seriesID else { return }
        try db.execute(
            sql: """
            INSERT INTO pusher_series (id, title, urgency, active, updated_at_ms)
            VALUES (?, ?, ?, 1, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                urgency = excluded.urgency,
                active = 1,
                updated_at_ms = excluded.updated_at_ms
            """,
            arguments: [seriesID.uuidString, task.title, task.urgency.rawValue, task.updatedAtMilliseconds]
        )
    }
}
