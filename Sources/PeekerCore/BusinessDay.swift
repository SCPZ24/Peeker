import Foundation

public enum RefreshTimeError: Error, Equatable {
    case invalidHour
    case invalidMinute
}

public struct RefreshTime: Codable, Equatable, Hashable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) throws {
        guard (0...23).contains(hour) else { throw RefreshTimeError.invalidHour }
        guard (0...59).contains(minute) else { throw RefreshTimeError.invalidMinute }
        self.hour = hour
        self.minute = minute
    }

    public static let midnight = try! RefreshTime(hour: 0, minute: 0)
}

public struct BusinessDay: Codable, Equatable, Sendable {
    public let id: BusinessDayID
    public let start: Date
    public let end: Date

    public init(featureID: FeatureID, start: Date, end: Date) {
        self.id = BusinessDayID(
            featureID: featureID,
            startAtMilliseconds: start.millisecondsSince1970
        )
        self.start = start
        self.end = end
    }
}

public struct BusinessDayResolver: Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    public func businessDay(
        containing date: Date,
        featureID: FeatureID,
        refreshTime: RefreshTime
    ) -> BusinessDay {
        let localDayStart = calendar.startOfDay(for: date)
        let todayBoundary = boundary(onLocalDayStarting: localDayStart, refreshTime: refreshTime)
        let businessStart: Date

        if todayBoundary <= date {
            businessStart = todayBoundary
        } else {
            let previousDay = calendar.date(byAdding: .day, value: -1, to: localDayStart)!
            businessStart = boundary(onLocalDayStarting: previousDay, refreshTime: refreshTime)
        }

        let nextLocalDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: businessStart)
        )!
        let businessEnd = boundary(onLocalDayStarting: nextLocalDay, refreshTime: refreshTime)
        return BusinessDay(featureID: featureID, start: businessStart, end: businessEnd)
    }

    public func boundaries(
        after start: Date,
        through end: Date,
        featureID: FeatureID,
        refreshTime: RefreshTime
    ) -> [Date] {
        guard start < end else { return [] }
        var result: [Date] = []
        var next = businessDay(
            containing: start,
            featureID: featureID,
            refreshTime: refreshTime
        ).end

        while next <= end {
            result.append(next)
            let following = next.addingTimeInterval(0.001)
            next = businessDay(
                containing: following,
                featureID: featureID,
                refreshTime: refreshTime
            ).end
        }
        return result
    }

    public func businessDay(
        startingAtBoundary boundary: Date,
        featureID: FeatureID,
        refreshTime: RefreshTime
    ) -> BusinessDay {
        let resolved = businessDay(
            containing: boundary.addingTimeInterval(0.001),
            featureID: featureID,
            refreshTime: refreshTime
        )
        return BusinessDay(featureID: featureID, start: boundary, end: resolved.end)
    }

    private func boundary(onLocalDayStarting dayStart: Date, refreshTime: RefreshTime) -> Date {
        let anchor = dayStart.addingTimeInterval(-1)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.hour = refreshTime.hour
        components.minute = refreshTime.minute
        components.second = 0

        return calendar.nextDate(
            after: anchor,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )!
    }
}

public enum TemporalEvent: Equatable, Sendable {
    case target
    case boundary
}

public enum TemporalEventOrdering {
    public static func next(
        targetAtMilliseconds: Int64,
        boundaryAtMilliseconds: Int64
    ) -> TemporalEvent {
        targetAtMilliseconds <= boundaryAtMilliseconds ? .target : .boundary
    }
}
