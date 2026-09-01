import Foundation
import GRDB
import PeekerCore
import PersistenceCore
import TargetorFeature

public final class TargetorGRDBRepository: TargetorRepository, @unchecked Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) { self.database = database }

    public func recover(
        now: Date,
        refreshTime: RefreshTime,
        resolver: TargetorPeriodResolver
    ) async throws {
        try await database.queue.write { db in
            let rows = try Row.fetchAll(
                db, sql: "SELECT * FROM targetor_targets WHERE archived_at_ms IS NULL ORDER BY position, id"
            )
            for row in rows {
                let target = try Self.target(row)
                var current = try Self.currentPeriod(targetID: target.id, db: db)
                if current == nil {
                    let start = target.createdAtMilliseconds
                    let end = resolver.nextBoundary(
                        after: Date(millisecondsSince1970: start),
                        rule: target.periodRule,
                        refreshTime: refreshTime
                    ).millisecondsSince1970
                    let period = TargetorPeriod(
                        targetID: target.id, sequence: 0, startMilliseconds: start,
                        endMilliseconds: end, ruleSnapshot: target.periodRule,
                        maxCountSnapshot: target.maxCount, createdAtMilliseconds: start
                    )
                    try Self.insert(period, db: db)
                    current = period
                }
                while let period = current, period.endMilliseconds <= now.millisecondsSince1970 {
                    try db.execute(
                        sql: "UPDATE targetor_periods SET settled_at_ms = ? WHERE id = ? AND settled_at_ms IS NULL",
                        arguments: [period.endMilliseconds, period.id.uuidString]
                    )
                    let nextStart = period.endMilliseconds
                    let nextEnd = resolver.nextBoundary(
                        after: Date(millisecondsSince1970: nextStart),
                        rule: target.periodRule,
                        refreshTime: refreshTime
                    ).millisecondsSince1970
                    let next = TargetorPeriod(
                        targetID: target.id, sequence: period.sequence + 1,
                        startMilliseconds: nextStart, endMilliseconds: nextEnd,
                        ruleSnapshot: target.periodRule, maxCountSnapshot: target.maxCount,
                        createdAtMilliseconds: nextStart
                    )
                    try Self.insert(next, db: db)
                    current = next
                }
            }
        }
    }

    public func snapshot(scope: TargetorArchiveScope) async throws -> TargetorSnapshot {
        try await database.queue.read { db in
            let predicate: String
            switch scope {
            case .active: predicate = "WHERE archived_at_ms IS NULL"
            case .all: predicate = ""
            case .only: predicate = "WHERE archived_at_ms IS NOT NULL"
            }
            let rows = try Row.fetchAll(
                db, sql: "SELECT * FROM targetor_targets \(predicate) ORDER BY archived_at_ms IS NOT NULL, position, created_at_ms, id"
            )
            var values: [TargetorTargetState] = []
            var issues: [String] = []
            for row in rows {
                do {
                    let target = try Self.target(row)
                    values.append(try Self.state(target: target, db: db))
                } catch {
                    let rawID: String = row["id"]
                    issues.append("Target \(rawID) is unavailable: \(error.localizedDescription)")
                }
            }
            return TargetorSnapshot(targets: values, issues: issues)
        }
    }

    public func create(target: TargetorTarget, firstPeriod: TargetorPeriod) async throws {
        try await database.queue.write { db in
            try Self.insert(target, db: db)
            try Self.insert(firstPeriod, db: db)
        }
    }

    public func update(
        target: TargetorTarget,
        replacingCurrentWith period: TargetorPeriod?,
        settleAtMilliseconds: Int64?
    ) async throws {
        try await database.queue.write { db in
            guard try Bool.fetchOne(
                db, sql: "SELECT EXISTS(SELECT 1 FROM targetor_targets WHERE id = ?)",
                arguments: [target.id.uuidString]
            ) == true else { throw TargetorError.targetNotFound }
            guard target.archivedAtMilliseconds == nil else { throw TargetorError.targetArchived }
            try Self.update(target, db: db)
            if let period, let settleAtMilliseconds {
                try db.execute(
                    sql: "UPDATE targetor_periods SET settled_at_ms = ? WHERE target_id = ? AND settled_at_ms IS NULL",
                    arguments: [settleAtMilliseconds, target.id.uuidString]
                )
                try Self.insert(period, db: db)
            } else {
                try db.execute(
                    sql: "UPDATE targetor_periods SET max_count = ? WHERE target_id = ? AND settled_at_ms IS NULL",
                    arguments: [target.maxCount, target.id.uuidString]
                )
            }
        }
    }

    public func archive(targetID: UUID, atMilliseconds: Int64) async throws -> TargetorTargetState {
        try await database.queue.write { db in
            guard var target = try Self.target(id: targetID, db: db) else { throw TargetorError.targetNotFound }
            guard target.archivedAtMilliseconds == nil else { throw TargetorError.targetArchived }
            try db.execute(
                sql: "UPDATE targetor_periods SET settled_at_ms = ? WHERE target_id = ? AND settled_at_ms IS NULL",
                arguments: [atMilliseconds, targetID.uuidString]
            )
            target.archivedAtMilliseconds = atMilliseconds
            target.updatedAtMilliseconds = atMilliseconds
            try Self.update(target, db: db)
            try Self.normalizePositions(db: db, atMilliseconds: atMilliseconds)
            return try Self.state(target: target, db: db)
        }
    }

    public func reorder(activeTargetIDs: [UUID], atMilliseconds: Int64) async throws {
        try await database.queue.write { db in
            let stored = try String.fetchAll(
                db, sql: "SELECT id FROM targetor_targets WHERE archived_at_ms IS NULL ORDER BY position, id"
            )
            guard Set(stored) == Set(activeTargetIDs.map(\.uuidString)), stored.count == activeTargetIDs.count else {
                throw TargetorError.targetNotFound
            }
            for (position, id) in activeTargetIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE targetor_targets SET position = ?, updated_at_ms = ? WHERE id = ? AND archived_at_ms IS NULL",
                    arguments: [position, atMilliseconds, id.uuidString]
                )
            }
        }
    }

    public func checkin(
        targetID: UUID,
        eventID: UUID,
        atMilliseconds: Int64
    ) async throws -> TargetorCheckinResult {
        try await database.queue.write { db in
            guard let target = try Self.target(id: targetID, db: db) else { throw TargetorError.targetNotFound }
            guard target.archivedAtMilliseconds == nil else { throw TargetorError.targetArchived }
            guard let current = try Self.currentPeriod(targetID: targetID, db: db) else {
                throw TargetorError.targetNotFound
            }
            let count = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM targetor_checkins WHERE period_id = ?",
                arguments: [current.id.uuidString]
            ) ?? 0
            guard count < current.maxCountSnapshot else { throw TargetorError.cycleComplete }
            let event = TargetorCheckin(
                id: eventID, targetID: targetID, periodID: current.id,
                occurredAtMilliseconds: atMilliseconds
            )
            try db.execute(
                sql: "INSERT INTO targetor_checkins (id, target_id, period_id, occurred_at_ms) VALUES (?, ?, ?, ?)",
                arguments: [event.id.uuidString, targetID.uuidString, current.id.uuidString, atMilliseconds]
            )
            return TargetorCheckinResult(
                target: try Self.state(target: target, db: db), event: event
            )
        }
    }

    public func uncheck(eventID: UUID) async throws -> TargetorTargetState {
        try await database.queue.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT c.target_id, c.period_id, p.settled_at_ms, t.archived_at_ms
                FROM targetor_checkins c
                JOIN targetor_periods p ON p.id = c.period_id AND p.target_id = c.target_id
                JOIN targetor_targets t ON t.id = c.target_id
                WHERE c.id = ?
                """,
                arguments: [eventID.uuidString]
            ) else { throw TargetorError.eventNotFound }
            let settled: Int64? = row["settled_at_ms"]
            let archived: Int64? = row["archived_at_ms"]
            guard settled == nil, archived == nil else { throw TargetorError.eventNotCurrent }
            let targetRaw: String = row["target_id"]
            guard let targetID = UUID(uuidString: targetRaw), let target = try Self.target(id: targetID, db: db) else {
                throw TargetorError.eventNotFound
            }
            try db.execute(sql: "DELETE FROM targetor_checkins WHERE id = ?", arguments: [eventID.uuidString])
            return try Self.state(target: target, db: db)
        }
    }

    public func history(
        targetID: UUID,
        fromMilliseconds: Int64?,
        toMilliseconds: Int64?
    ) async throws -> TargetorHistory {
        try await database.queue.read { db in
            guard let target = try Self.target(id: targetID, db: db) else { throw TargetorError.targetNotFound }
            let defaultPeriod = try Self.currentPeriod(targetID: targetID, db: db)
                ?? Self.lastPeriod(targetID: targetID, db: db)
            guard let from = fromMilliseconds ?? defaultPeriod?.startMilliseconds,
                  let to = toMilliseconds ?? defaultPeriod?.endMilliseconds,
                  to > from
            else { throw TargetorError.invalidHistoryRange }
            let periods = try Row.fetchAll(
                db,
                sql: """
                SELECT p.*, COUNT(c.id) AS event_count
                FROM targetor_periods p
                LEFT JOIN targetor_checkins c ON c.period_id = p.id
                WHERE p.target_id = ? AND p.start_at_ms < ? AND p.end_at_ms > ?
                GROUP BY p.id ORDER BY p.start_at_ms, p.sequence
                """,
                arguments: [targetID.uuidString, to, from]
            ).map(Self.period)
            let events = try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM targetor_checkins
                WHERE target_id = ? AND occurred_at_ms >= ? AND occurred_at_ms < ?
                ORDER BY occurred_at_ms, id
                """,
                arguments: [targetID.uuidString, from, to]
            ).map(Self.event)
            return TargetorHistory(
                target: target, fromMilliseconds: from, toMilliseconds: to,
                periods: periods, events: events
            )
        }
    }

    private static func state(target: TargetorTarget, db: Database) throws -> TargetorTargetState {
        let current = try currentPeriod(targetID: target.id, db: db)
        return TargetorTargetState(
            target: target,
            currentPeriod: target.archivedAtMilliseconds == nil ? current : nil,
            lastPeriod: try lastPeriod(targetID: target.id, db: db)
        )
    }

    private static func currentPeriod(targetID: UUID, db: Database) throws -> TargetorPeriod? {
        try Row.fetchOne(
            db,
            sql: """
            SELECT p.*, COUNT(c.id) AS event_count
            FROM targetor_periods p LEFT JOIN targetor_checkins c ON c.period_id = p.id
            WHERE p.target_id = ? AND p.settled_at_ms IS NULL
            GROUP BY p.id
            """,
            arguments: [targetID.uuidString]
        ).map(period)
    }

    private static func lastPeriod(targetID: UUID, db: Database) throws -> TargetorPeriod? {
        try Row.fetchOne(
            db,
            sql: """
            SELECT p.*, COUNT(c.id) AS event_count
            FROM targetor_periods p LEFT JOIN targetor_checkins c ON c.period_id = p.id
            WHERE p.target_id = ?
            GROUP BY p.id ORDER BY p.start_at_ms DESC, p.sequence DESC LIMIT 1
            """,
            arguments: [targetID.uuidString]
        ).map(period)
    }

    private static func target(id: UUID, db: Database) throws -> TargetorTarget? {
        try Row.fetchOne(db, sql: "SELECT * FROM targetor_targets WHERE id = ?", arguments: [id.uuidString]).map(target)
    }

    private static func target(_ row: Row) throws -> TargetorTarget {
        let idRaw: String = row["id"]
        guard let id = UUID(uuidString: idRaw),
              let frequency = TargetorFrequency(rawValue: row["frequency"])
        else { throw TargetorPersistenceError.corruptRecord }
        let weekdayRaw: String? = row["weekday"]
        let monthDay: Int? = row["month_day"]
        let rule = try TargetorPeriodRule(
            frequency: frequency,
            weekday: weekdayRaw.flatMap(TargetorWeekday.init(rawValue:)),
            monthDay: monthDay
        )
        return try TargetorTarget(
            id: id, title: row["title"], description: row["description"],
            iconName: row["icon_name"], periodRule: rule, maxCount: row["max_count"],
            position: row["position"], createdAtMilliseconds: row["created_at_ms"],
            updatedAtMilliseconds: row["updated_at_ms"], archivedAtMilliseconds: row["archived_at_ms"]
        )
    }

    private static func period(_ row: Row) throws -> TargetorPeriod {
        let idRaw: String = row["id"], targetRaw: String = row["target_id"]
        guard let id = UUID(uuidString: idRaw), let targetID = UUID(uuidString: targetRaw),
              let frequency = TargetorFrequency(rawValue: row["frequency"])
        else { throw TargetorPersistenceError.corruptRecord }
        let weekdayRaw: String? = row["weekday"]
        let rule = try TargetorPeriodRule(
            frequency: frequency,
            weekday: weekdayRaw.flatMap(TargetorWeekday.init(rawValue:)),
            monthDay: row["month_day"]
        )
        return TargetorPeriod(
            id: id, targetID: targetID, sequence: row["sequence"],
            startMilliseconds: row["start_at_ms"], endMilliseconds: row["end_at_ms"],
            ruleSnapshot: rule, maxCountSnapshot: row["max_count"],
            createdAtMilliseconds: row["created_at_ms"], settledAtMilliseconds: row["settled_at_ms"],
            count: row["event_count"] ?? 0
        )
    }

    private static func event(_ row: Row) throws -> TargetorCheckin {
        let idRaw: String = row["id"], targetRaw: String = row["target_id"], periodRaw: String = row["period_id"]
        guard let id = UUID(uuidString: idRaw), let targetID = UUID(uuidString: targetRaw),
              let periodID = UUID(uuidString: periodRaw) else { throw TargetorPersistenceError.corruptRecord }
        return TargetorCheckin(
            id: id, targetID: targetID, periodID: periodID, occurredAtMilliseconds: row["occurred_at_ms"]
        )
    }

    private static func insert(_ target: TargetorTarget, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO targetor_targets
            (id,title,description,icon_name,frequency,weekday,month_day,max_count,position,created_at_ms,updated_at_ms,archived_at_ms)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            arguments: target.arguments
        )
    }

    private static func update(_ target: TargetorTarget, db: Database) throws {
        try db.execute(
            sql: """
            UPDATE targetor_targets SET title=?,description=?,icon_name=?,frequency=?,weekday=?,month_day=?,max_count=?,position=?,updated_at_ms=?,archived_at_ms=? WHERE id=?
            """,
            arguments: [
                target.title, target.description, target.iconName, target.periodRule.frequency.rawValue,
                target.periodRule.weekday?.rawValue, target.periodRule.monthDay, target.maxCount,
                target.position, target.updatedAtMilliseconds, target.archivedAtMilliseconds, target.id.uuidString,
            ]
        )
    }

    private static func insert(_ period: TargetorPeriod, db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO targetor_periods
            (id,target_id,sequence,start_at_ms,end_at_ms,frequency,weekday,month_day,max_count,created_at_ms,settled_at_ms)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
            """,
            arguments: [
                period.id.uuidString, period.targetID.uuidString, period.sequence,
                period.startMilliseconds, period.endMilliseconds, period.ruleSnapshot.frequency.rawValue,
                period.ruleSnapshot.weekday?.rawValue, period.ruleSnapshot.monthDay,
                period.maxCountSnapshot, period.createdAtMilliseconds, period.settledAtMilliseconds,
            ]
        )
    }

    private static func normalizePositions(db: Database, atMilliseconds: Int64) throws {
        let ids = try String.fetchAll(
            db, sql: "SELECT id FROM targetor_targets WHERE archived_at_ms IS NULL ORDER BY position, created_at_ms, id"
        )
        for (position, id) in ids.enumerated() {
            try db.execute(
                sql: "UPDATE targetor_targets SET position = ?, updated_at_ms = ? WHERE id = ?",
                arguments: [position, atMilliseconds, id]
            )
        }
    }
}

private extension TargetorTarget {
    var arguments: StatementArguments {
        [
            id.uuidString, title, description, iconName, periodRule.frequency.rawValue,
            periodRule.weekday?.rawValue, periodRule.monthDay, maxCount, position,
            createdAtMilliseconds, updatedAtMilliseconds, archivedAtMilliseconds,
        ]
    }
}

private enum TargetorPersistenceError: Error {
    case corruptRecord
}
