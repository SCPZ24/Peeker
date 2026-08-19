import Foundation

public enum SchedulerError: Error, Equatable, Sendable {
    case invalidTitle
    case invalidTimeRange
    case invalidRecurrence
    case eventNotFound
    case occurrenceNotFound
    case scopeRequired
    case scopeNotAllowed
    case sourceNotFound
    case sourceUnreadable
    case sourcePathConflict
    case icsParseFailed(String)
}

public struct SchedulerLocalDate: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { throw SchedulerError.invalidTimeRange }
        self.year = year; self.month = month; self.day = day
    }

    public init?(_ value: String) {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = try? SchedulerLocalDate(year: parts[0], month: parts[1], day: parts[2]) else { return nil }
        self = date
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.description < rhs.description }

    public func date(in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public func adding(days: Int, in timeZone: TimeZone) -> SchedulerLocalDate? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard let date = date(in: timeZone), let next = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return try? SchedulerLocalDate(
            year: calendar.component(.year, from: next),
            month: calendar.component(.month, from: next),
            day: calendar.component(.day, from: next)
        )
    }
}

public enum SchedulerFrequency: String, Codable, CaseIterable, Sendable { case daily, weekly, monthly, yearly }
public enum SchedulerWeekday: String, Codable, CaseIterable, Sendable {
    case mon, tue, wed, thu, fri, sat, sun
    public var calendarWeekday: Int { [2, 3, 4, 5, 6, 7, 1][Self.allCases.firstIndex(of: self)!] }
}
public enum SchedulerRecurrenceEnd: Codable, Equatable, Sendable {
    case never
    case untilTimed(Int64)
    case untilDate(SchedulerLocalDate)
    case count(Int)
}

public struct SchedulerRecurrence: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var frequency: SchedulerFrequency
    public var interval: Int
    public var weekdays: [SchedulerWeekday]
    public var end: SchedulerRecurrenceEnd

    public init(
        frequency: SchedulerFrequency,
        interval: Int = 1,
        weekdays: [SchedulerWeekday] = [],
        end: SchedulerRecurrenceEnd = .never
    ) throws {
        guard interval > 0,
              frequency == .weekly || weekdays.isEmpty,
              ({ if case let .count(value) = end { return value > 0 }; return true })()
        else { throw SchedulerError.invalidRecurrence }
        schemaVersion = 1
        self.frequency = frequency
        self.interval = interval
        self.weekdays = Array(Set(weekdays)).sorted {
            SchedulerWeekday.allCases.firstIndex(of: $0)! < SchedulerWeekday.allCases.firstIndex(of: $1)!
        }
        self.end = end
    }
}

public enum SchedulerEventTime: Codable, Equatable, Sendable {
    case timed(startMilliseconds: Int64, endMilliseconds: Int64, timeZoneID: String)
    case allDay(start: SchedulerLocalDate, endExclusive: SchedulerLocalDate)
}

public struct SchedulerEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sourceID: UUID?
    public var sourceUID: String?
    public var sourceSegmentKey: String?
    public var title: String
    public var notes: String?
    public var location: String?
    public var colorHex: String
    public var time: SchedulerEventTime
    public var recurrence: SchedulerRecurrence?
    public var createdAtMilliseconds: Int64
    public var updatedAtMilliseconds: Int64

    public init(
        id: UUID = UUID(), sourceID: UUID? = nil, sourceUID: String? = nil, sourceSegmentKey: String? = nil,
        title: String, notes: String? = nil, location: String? = nil, colorHex: String = "#0A84FF",
        time: SchedulerEventTime, recurrence: SchedulerRecurrence? = nil,
        createdAtMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAtMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw SchedulerError.invalidTitle }
        guard colorHex.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else {
            throw SchedulerError.invalidTimeRange
        }
        switch time {
        case let .timed(start, end, zone): guard end > start, TimeZone(identifier: zone) != nil else { throw SchedulerError.invalidTimeRange }
        case let .allDay(start, end): guard end > start else { throw SchedulerError.invalidTimeRange }
        }
        self.id=id; self.sourceID=sourceID; self.sourceUID=sourceUID; self.sourceSegmentKey=sourceSegmentKey
        self.title=title; self.notes=notes; self.location=location; self.colorHex=colorHex.uppercased()
        self.time=time; self.recurrence=recurrence; self.createdAtMilliseconds=createdAtMilliseconds; self.updatedAtMilliseconds=updatedAtMilliseconds
    }
}

public struct SchedulerOccurrence: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(eventID.uuidString):\(originalKey)" }
    public let eventID: UUID
    public let originalKey: String
    public let title: String
    public let notes: String?
    public let location: String?
    public let colorHex: String
    public let time: SchedulerEventTime
    public let recurring: Bool
    public let isException: Bool
    public let sourceID: UUID?

    public init(
        eventID: UUID, originalKey: String, title: String, notes: String?, location: String?,
        colorHex: String, time: SchedulerEventTime, recurring: Bool, isException: Bool, sourceID: UUID?
    ) {
        self.eventID=eventID; self.originalKey=originalKey; self.title=title; self.notes=notes
        self.location=location; self.colorHex=colorHex; self.time=time; self.recurring=recurring
        self.isException=isException; self.sourceID=sourceID
    }
}

public struct SchedulerOccurrenceOverride: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let eventID: UUID
    public let occurrenceKey: String
    public let isCancelled: Bool
    public let replacement: SchedulerOccurrence?
    public let updatedAtMilliseconds: Int64

    public init(id: UUID = UUID(), eventID: UUID, occurrenceKey: String, isCancelled: Bool, replacement: SchedulerOccurrence?, updatedAtMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.id=id; self.eventID=eventID; self.occurrenceKey=occurrenceKey; self.isCancelled=isCancelled; self.replacement=replacement; self.updatedAtMilliseconds=updatedAtMilliseconds
    }
}

public enum SchedulerMutationScope: String, Codable, Sendable { case this, future, all }

public struct SchedulerSource: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var canonicalPath: String
    public var displayName: String
    public var lastSuccessfulImportAtMilliseconds: Int64?
    public var lastAttemptAtMilliseconds: Int64?
    public var lastResult: String?

    public init(
        id: UUID = UUID(), canonicalPath: String, displayName: String,
        lastSuccessfulImportAtMilliseconds: Int64? = nil,
        lastAttemptAtMilliseconds: Int64? = nil, lastResult: String? = nil
    ) {
        self.id=id; self.canonicalPath=canonicalPath; self.displayName=displayName
        self.lastSuccessfulImportAtMilliseconds=lastSuccessfulImportAtMilliseconds
        self.lastAttemptAtMilliseconds=lastAttemptAtMilliseconds; self.lastResult=lastResult
    }
}
