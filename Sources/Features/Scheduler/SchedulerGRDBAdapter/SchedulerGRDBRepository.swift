import Foundation
import GRDB
import PersistenceCore
import SchedulerFeature

public final class SchedulerGRDBRepository: SchedulerRepository, @unchecked Sendable {
    private let database: AppDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: AppDatabase) { self.database = database }

    public func snapshot() async throws -> SchedulerSnapshot {
        try await database.queue.read { db in
            let eventRows = try Row.fetchAll(db, sql: "SELECT * FROM scheduler_events ORDER BY start_at_ms, start_date, id")
            let overrideRows = try Row.fetchAll(db, sql: "SELECT * FROM scheduler_occurrence_overrides ORDER BY event_id, occurrence_key")
            return try SchedulerSnapshot(
                events: eventRows.map(self.decodeEvent),
                overrides: overrideRows.map(self.decodeOverride)
            )
        }
    }

    public func event(id: UUID) async throws -> SchedulerEvent? {
        try await database.queue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM scheduler_events WHERE id = ?", arguments: [id.uuidString]).map(self.decodeEvent)
        }
    }

    public func save(_ event: SchedulerEvent) async throws -> SchedulerEvent {
        try await database.queue.write { db in
            let values = try self.eventArguments(event)
            try db.execute(sql: """
                INSERT INTO scheduler_events (
                    id, source_id, source_uid, source_segment_key, title, notes, location, color_hex,
                    kind, start_at_ms, end_at_ms, normalized_timezone_id, start_date, end_date_exclusive,
                    recurrence_json, created_at_ms, updated_at_ms
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET
                    source_id=excluded.source_id, source_uid=excluded.source_uid,
                    source_segment_key=excluded.source_segment_key, title=excluded.title, notes=excluded.notes,
                    location=excluded.location, color_hex=excluded.color_hex, kind=excluded.kind,
                    start_at_ms=excluded.start_at_ms, end_at_ms=excluded.end_at_ms,
                    normalized_timezone_id=excluded.normalized_timezone_id, start_date=excluded.start_date,
                    end_date_exclusive=excluded.end_date_exclusive, recurrence_json=excluded.recurrence_json,
                    updated_at_ms=excluded.updated_at_ms
                """, arguments: StatementArguments(values))
            return event
        }
    }

    public func deleteEvent(id: UUID) async throws -> Bool {
        try await database.queue.write { db in
            try db.execute(sql: "DELETE FROM scheduler_events WHERE id = ?", arguments: [id.uuidString])
            return db.changesCount > 0
        }
    }

    public func saveOverride(_ override: SchedulerOccurrenceOverride) async throws {
        try await database.queue.write { db in
            let replacement = try override.replacement.map { String(data: try self.encoder.encode($0), encoding: .utf8)! }
            try db.execute(sql: """
                INSERT INTO scheduler_occurrence_overrides
                    (id,event_id,occurrence_key,is_cancelled,replacement_json,updated_at_ms)
                VALUES (?,?,?,?,?,?)
                ON CONFLICT(event_id,occurrence_key) DO UPDATE SET
                    id=excluded.id,is_cancelled=excluded.is_cancelled,
                    replacement_json=excluded.replacement_json,updated_at_ms=excluded.updated_at_ms
                """, arguments: [override.id.uuidString, override.eventID.uuidString, override.occurrenceKey,
                                   override.isCancelled, replacement, override.updatedAtMilliseconds])
        }
    }

    public func deleteOverrides(eventID: UUID, fromKey: String?) async throws -> Int {
        try await database.queue.write { db in
            if let fromKey {
                try db.execute(sql: "DELETE FROM scheduler_occurrence_overrides WHERE event_id = ? AND occurrence_key >= ?", arguments: [eventID.uuidString, fromKey])
            } else {
                try db.execute(sql: "DELETE FROM scheduler_occurrence_overrides WHERE event_id = ?", arguments: [eventID.uuidString])
            }
            return db.changesCount
        }
    }

    public func sources() async throws -> [SchedulerSource] {
        try await database.queue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM scheduler_sources ORDER BY display_name, id").map(self.decodeSource)
        }
    }

    public func source(id: UUID) async throws -> SchedulerSource? {
        try await database.queue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM scheduler_sources WHERE id = ?", arguments: [id.uuidString]).map(self.decodeSource)
        }
    }

    public func saveSource(_ source: SchedulerSource) async throws {
        try await database.queue.write { db in
            try db.execute(sql: """
                INSERT INTO scheduler_sources (id,canonical_path,display_name,last_successful_import_at_ms,last_attempt_at_ms,last_result)
                VALUES (?,?,?,?,?,?)
                ON CONFLICT(id) DO UPDATE SET canonical_path=excluded.canonical_path,
                    display_name=excluded.display_name,last_successful_import_at_ms=excluded.last_successful_import_at_ms,
                    last_attempt_at_ms=excluded.last_attempt_at_ms,last_result=excluded.last_result
                """, arguments: [source.id.uuidString, source.canonicalPath, source.displayName,
                                   source.lastSuccessfulImportAtMilliseconds, source.lastAttemptAtMilliseconds, source.lastResult])
        }
    }

    public func removeSource(id: UUID) async throws -> Int {
        try await database.queue.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scheduler_events WHERE source_id = ?", arguments: [id.uuidString]) ?? 0
            try db.execute(sql: "DELETE FROM scheduler_sources WHERE id = ?", arguments: [id.uuidString])
            return count
        }
    }

    public func replaceSource(
        _ source: SchedulerSource,
        series: [SchedulerImportedSeries],
        protectedUIDs: Set<String>
    ) async throws -> SchedulerImportCommit {
        try await database.queue.write { db in
            try self.upsertSource(source, in: db)
            let oldRows = try Row.fetchAll(db, sql: "SELECT id, source_uid FROM scheduler_events WHERE source_id = ? AND source_segment_key = 'root'", arguments: [source.id.uuidString])
            let oldByUID = Dictionary(uniqueKeysWithValues: oldRows.compactMap { row -> (String, UUID)? in
                let uid: String = row["source_uid"]; guard let id = UUID(uuidString: row["id"]) else { return nil }; return (uid, id)
            })
            let incoming = Set(series.map(\.uid))
            var created = 0; var updated = 0; var deleted = 0
            for uid in oldByUID.keys where !incoming.contains(uid) && !protectedUIDs.contains(uid) {
                try db.execute(sql: "DELETE FROM scheduler_events WHERE source_id = ? AND source_uid = ?", arguments: [source.id.uuidString, uid])
                deleted += db.changesCount
            }
            for imported in series {
                let stableID = oldByUID[imported.uid] ?? imported.event.id
                if oldByUID[imported.uid] == nil { created += 1 } else { updated += 1 }
                try db.execute(sql: "DELETE FROM scheduler_events WHERE source_id = ? AND source_uid = ?", arguments: [source.id.uuidString, imported.uid])
                var event = imported.event
                event.id = stableID; event.sourceID = source.id; event.sourceUID = imported.uid; event.sourceSegmentKey = "root"
                try self.insertEvent(event, in: db)
                for item in imported.overrides {
                    let replacement = item.replacement.map { value in
                        SchedulerOccurrence(
                            eventID: stableID, originalKey: value.originalKey, title: value.title, notes: value.notes,
                            location: value.location, colorHex: value.colorHex, time: value.time,
                            recurring: value.recurring, isException: true, sourceID: source.id
                        )
                    }
                    let adjusted = SchedulerOccurrenceOverride(
                        id: item.id, eventID: stableID, occurrenceKey: item.occurrenceKey,
                        isCancelled: item.isCancelled, replacement: replacement,
                        updatedAtMilliseconds: item.updatedAtMilliseconds
                    )
                    let encoded = try adjusted.replacement.map { String(data: try self.encoder.encode($0), encoding: .utf8)! }
                    try db.execute(sql: "INSERT INTO scheduler_occurrence_overrides (id,event_id,occurrence_key,is_cancelled,replacement_json,updated_at_ms) VALUES (?,?,?,?,?,?)",
                                   arguments: [adjusted.id.uuidString, stableID.uuidString, adjusted.occurrenceKey, adjusted.isCancelled, encoded, adjusted.updatedAtMilliseconds])
                }
            }
            return SchedulerImportCommit(source: source, created: created, updated: updated, deleted: deleted, skipped: protectedUIDs.count)
        }
    }

    private func upsertSource(_ source: SchedulerSource, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO scheduler_sources (id,canonical_path,display_name,last_successful_import_at_ms,last_attempt_at_ms,last_result)
            VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET canonical_path=excluded.canonical_path,
            display_name=excluded.display_name,last_successful_import_at_ms=excluded.last_successful_import_at_ms,
            last_attempt_at_ms=excluded.last_attempt_at_ms,last_result=excluded.last_result
            """, arguments: [source.id.uuidString, source.canonicalPath, source.displayName,
                               source.lastSuccessfulImportAtMilliseconds, source.lastAttemptAtMilliseconds, source.lastResult])
    }

    private func insertEvent(_ event: SchedulerEvent, in db: Database) throws {
        try db.execute(sql: """
            INSERT INTO scheduler_events (
                id, source_id, source_uid, source_segment_key, title, notes, location, color_hex,
                kind, start_at_ms, end_at_ms, normalized_timezone_id, start_date, end_date_exclusive,
                recurrence_json, created_at_ms, updated_at_ms
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, arguments: StatementArguments(try eventArguments(event)))
    }

    private func eventArguments(_ event: SchedulerEvent) throws -> [DatabaseValueConvertible?] {
        let recurrence = try event.recurrence.map { String(data: try encoder.encode($0), encoding: .utf8)! }
        var kind: String; var start: Int64?; var end: Int64?; var zone: String?; var startDate: String?; var endDate: String?
        switch event.time {
        case let .timed(value, endValue, zoneValue):
            kind="timed"; start=value; end=endValue; zone=zoneValue; startDate=nil; endDate=nil
        case let .allDay(value, endValue):
            kind="allDay"; start=nil; end=nil; zone=nil; startDate=value.description; endDate=endValue.description
        }
        return [event.id.uuidString, event.sourceID?.uuidString, event.sourceUID, event.sourceSegmentKey,
                event.title, event.notes, event.location, event.colorHex, kind, start, end, zone, startDate, endDate,
                recurrence, event.createdAtMilliseconds, event.updatedAtMilliseconds]
    }

    private func decodeEvent(_ row: Row) throws -> SchedulerEvent {
        let time: SchedulerEventTime
        let kind: String = row["kind"]
        if kind == "timed" {
            time = .timed(startMilliseconds: row["start_at_ms"], endMilliseconds: row["end_at_ms"], timeZoneID: row["normalized_timezone_id"])
        } else {
            guard let start = SchedulerLocalDate(row["start_date"]), let end = SchedulerLocalDate(row["end_date_exclusive"]) else { throw SchedulerError.invalidTimeRange }
            time = .allDay(start: start, endExclusive: end)
        }
        let recurrenceString: String? = row["recurrence_json"]
        let recurrence = try recurrenceString.map { try decoder.decode(SchedulerRecurrence.self, from: Data($0.utf8)) }
        return try SchedulerEvent(
            id: UUID(uuidString: row["id"])!, sourceID: (row["source_id"] as String?).flatMap(UUID.init(uuidString:)),
            sourceUID: row["source_uid"], sourceSegmentKey: row["source_segment_key"], title: row["title"],
            notes: row["notes"], location: row["location"], colorHex: row["color_hex"], time: time,
            recurrence: recurrence, createdAtMilliseconds: row["created_at_ms"], updatedAtMilliseconds: row["updated_at_ms"]
        )
    }

    private func decodeOverride(_ row: Row) throws -> SchedulerOccurrenceOverride {
        let replacementString: String? = row["replacement_json"]
        let replacement = try replacementString.map { try decoder.decode(SchedulerOccurrence.self, from: Data($0.utf8)) }
        return SchedulerOccurrenceOverride(
            id: UUID(uuidString: row["id"])!, eventID: UUID(uuidString: row["event_id"])!,
            occurrenceKey: row["occurrence_key"], isCancelled: row["is_cancelled"], replacement: replacement,
            updatedAtMilliseconds: row["updated_at_ms"]
        )
    }

    private func decodeSource(_ row: Row) -> SchedulerSource {
        SchedulerSource(
            id: UUID(uuidString: row["id"])!, canonicalPath: row["canonical_path"], displayName: row["display_name"],
            lastSuccessfulImportAtMilliseconds: row["last_successful_import_at_ms"],
            lastAttemptAtMilliseconds: row["last_attempt_at_ms"], lastResult: row["last_result"]
        )
    }
}
