import Foundation
import PeekerCore

public struct TargetorPeriodResolver: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    public func nextBoundary(
        after date: Date,
        rule: TargetorPeriodRule,
        refreshTime: RefreshTime
    ) -> Date {
        switch rule.frequency {
        case .daily:
            return nextDailyBoundary(after: date, refreshTime: refreshTime)
        case .weekly:
            return nextWeeklyBoundary(after: date, weekday: rule.weekday!, refreshTime: refreshTime)
        case .monthly:
            return nextMonthlyBoundary(after: date, monthDay: rule.monthDay!, refreshTime: refreshTime)
        }
    }

    public func dayInterval(containing date: Date, refreshTime: RefreshTime) -> DateInterval {
        let dayResolver = BusinessDayResolver(calendar: calendar)
        let day = dayResolver.businessDay(
            containing: date, featureID: FeatureID(rawValue: "targetor"), refreshTime: refreshTime
        )
        return DateInterval(start: day.start, end: day.end)
    }

    private func nextDailyBoundary(after date: Date, refreshTime: RefreshTime) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.hour = refreshTime.hour
        components.minute = refreshTime.minute
        components.second = 0
        return calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )!
    }

    private func nextWeeklyBoundary(
        after date: Date,
        weekday: TargetorWeekday,
        refreshTime: RefreshTime
    ) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.weekday = weekday.calendarWeekday
        components.hour = refreshTime.hour
        components.minute = refreshTime.minute
        components.second = 0
        return calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )!
    }

    private func nextMonthlyBoundary(
        after date: Date,
        monthDay: Int,
        refreshTime: RefreshTime
    ) -> Date {
        let dateComponents = calendar.dateComponents([.year, .month], from: date)
        let monthStart = calendar.date(from: DateComponents(
            calendar: calendar, timeZone: calendar.timeZone,
            year: dateComponents.year, month: dateComponents.month, day: 1
        ))!
        for offset in 0...24 {
            let candidateMonth = calendar.date(byAdding: .month, value: offset, to: monthStart)!
            let range = calendar.range(of: .day, in: .month, for: candidateMonth)!
            let day = monthDay == 0 ? range.count : min(monthDay, range.count)
            let components = calendar.dateComponents([.year, .month], from: candidateMonth)
            let localDay = calendar.date(from: DateComponents(
                calendar: calendar, timeZone: calendar.timeZone,
                year: components.year, month: components.month, day: day
            ))!
            let candidate = boundary(onLocalDayStarting: localDay, refreshTime: refreshTime)
            if candidate > date { return candidate }
        }
        preconditionFailure("Unable to resolve a monthly Targetor boundary")
    }

    private func boundary(onLocalDayStarting dayStart: Date, refreshTime: RefreshTime) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: dayStart)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.hour = refreshTime.hour
        components.minute = refreshTime.minute
        components.second = 0
        return calendar.nextDate(
            after: dayStart.addingTimeInterval(-1),
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )!
    }
}

public enum TargetorCompletionLevel: Int, Codable, Equatable, Sendable {
    case empty = 0
    case one = 1
    case two = 2
    case three = 3
    case four = 4

    public init(ratio: Double?) {
        guard let ratio, ratio > 0 else { self = .empty; return }
        if ratio <= 0.25 { self = .one }
        else if ratio <= 0.5 { self = .two }
        else if ratio < 1 { self = .three }
        else { self = .four }
    }
}

public struct TargetorCalendarCell: Equatable, Identifiable, Sendable {
    public let date: Date
    public let ratio: Double?
    public let level: TargetorCompletionLevel
    public let periodSequence: Int?
    public var id: Date { date }
}

public enum TargetorCalendarCalculator {
    public static func period(
        for interval: DateInterval,
        targetID: UUID,
        periods: [TargetorPeriod]
    ) -> TargetorPeriod? {
        periods
            .filter {
                $0.targetID == targetID
                    && Date(millisecondsSince1970: $0.startMilliseconds) < interval.end
                    && Date(millisecondsSince1970: $0.endMilliseconds) > interval.start
            }
            .max { $0.startMilliseconds < $1.startMilliseconds }
    }

    public static func aggregate(
        dates: [Date], now: Date, refreshTime: RefreshTime,
        targets: [TargetorTarget], periods: [TargetorPeriod],
        resolver: TargetorPeriodResolver
    ) -> [TargetorCalendarCell] {
        dates.map { date in
            let interval = resolver.dayInterval(containing: date, refreshTime: refreshTime)
            guard interval.start <= now else {
                return TargetorCalendarCell(date: date, ratio: nil, level: .empty, periodSequence: nil)
            }
            let ratios = targets.compactMap { target -> Double? in
                let created = Date(millisecondsSince1970: target.createdAtMilliseconds)
                let archived = target.archivedAtMilliseconds.map(Date.init(millisecondsSince1970:))
                guard created < interval.end, archived == nil || archived! > interval.start,
                      let period = period(for: interval, targetID: target.id, periods: periods)
                else { return nil }
                return period.ratio
            }
            let ratio = ratios.isEmpty ? nil : ratios.reduce(0, +) / Double(ratios.count)
            return TargetorCalendarCell(
                date: date, ratio: ratio, level: TargetorCompletionLevel(ratio: ratio), periodSequence: nil
            )
        }
    }

    public static func nineWeekDates(
        containing date: Date,
        calendar input: Calendar = .autoupdatingCurrent
    ) -> [Date] {
        var calendar = input
        calendar.firstWeekday = 2
        let today = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: today)
        let offsetFromMonday = (weekday - 2 + 7) % 7
        let currentMonday = calendar.date(byAdding: .day, value: -offsetFromMonday, to: today)!
        let start = calendar.date(byAdding: .day, value: -56, to: currentMonday)!
        return (0..<63).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }
}
