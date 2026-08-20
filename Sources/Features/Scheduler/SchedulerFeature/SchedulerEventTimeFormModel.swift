import Foundation

struct SchedulerTimeInputDraft: Equatable, Sendable {
    var month: String
    var day: String
    var hour: String
    var minute: String

    init(month: String, day: String, hour: String = "00", minute: String = "00") {
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
    }

    init(date: Date, timeZone: TimeZone) {
        let calendar = Self.calendar(timeZone: timeZone)
        let components = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        month = Self.format(components.month ?? 1)
        day = Self.format(components.day ?? 1)
        hour = Self.format(components.hour ?? 0)
        minute = Self.format(components.minute ?? 0)
    }

    init(localDate: SchedulerLocalDate) {
        month = Self.format(localDate.month)
        day = Self.format(localDate.day)
        hour = "00"
        minute = "00"
    }

    fileprivate var monthDay: (month: Int, day: Int)? {
        guard let month = Self.parse(month, range: 1...12),
              let day = Self.parse(day, range: 1...31) else {
            return nil
        }
        return (month, day)
    }

    fileprivate func localDate(year: Int) -> SchedulerLocalDate? {
        guard let monthDay else { return nil }
        return try? SchedulerLocalDate(year: year, month: monthDay.month, day: monthDay.day)
    }

    fileprivate func date(year: Int, timeZone: TimeZone) -> Date? {
        guard let monthDay,
              let hour = Self.parse(hour, range: 0...23),
              let minute = Self.parse(minute, range: 0...59) else {
            return nil
        }
        let calendar = Self.calendar(timeZone: timeZone)
        let requested = DateComponents(
            timeZone: timeZone,
            year: year,
            month: monthDay.month,
            day: monthDay.day,
            hour: hour,
            minute: minute
        )
        guard let date = calendar.date(from: requested) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard resolved.year == year,
              resolved.month == monthDay.month,
              resolved.day == monthDay.day,
              resolved.hour == hour,
              resolved.minute == minute else {
            return nil
        }
        return date
    }

    private static func parse(_ value: String, range: ClosedRange<Int>) -> Int? {
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
              let parsed = Int(value),
              range.contains(parsed) else {
            return nil
        }
        return parsed
    }

    private static func format(_ value: Int) -> String {
        String(format: "%02d", value)
    }

    private static func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

struct SchedulerEventTimeFormDraft: Equatable, Sendable {
    var allDay: Bool
    let year: Int
    var start: SchedulerTimeInputDraft
    var end: SchedulerTimeInputDraft

    init(time: SchedulerEventTime, displayTimeZone: TimeZone = .current) {
        switch time {
        case let .timed(startMilliseconds, endMilliseconds, _):
            let startDate = Date(timeIntervalSince1970: Double(startMilliseconds) / 1_000)
            let endDate = Date(timeIntervalSince1970: Double(endMilliseconds) / 1_000)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = displayTimeZone
            allDay = false
            year = calendar.component(.year, from: startDate)
            start = SchedulerTimeInputDraft(date: startDate, timeZone: displayTimeZone)
            end = SchedulerTimeInputDraft(date: endDate, timeZone: displayTimeZone)
        case let .allDay(startDate, endDate):
            allDay = true
            year = startDate.year
            start = SchedulerTimeInputDraft(localDate: startDate)
            end = SchedulerTimeInputDraft(localDate: endDate)
        }
    }

    init(
        allDay: Bool,
        year: Int,
        start: SchedulerTimeInputDraft,
        end: SchedulerTimeInputDraft
    ) {
        self.allDay = allDay
        self.year = year
        self.start = start
        self.end = end
    }

    func resolvedTime(displayTimeZone: TimeZone = .current) -> SchedulerEventTime? {
        guard let startMonthDay = start.monthDay,
              let endMonthDay = end.monthDay else {
            return nil
        }
        let endYear = Self.isEarlier(endMonthDay, than: startMonthDay) ? year + 1 : year

        if allDay {
            guard let startDate = start.localDate(year: year),
                  let endDate = end.localDate(year: endYear),
                  endDate > startDate else {
                return nil
            }
            return .allDay(start: startDate, endExclusive: endDate)
        }

        guard let startDate = start.date(year: year, timeZone: displayTimeZone),
              let endDate = end.date(year: endYear, timeZone: displayTimeZone),
              endDate > startDate else {
            return nil
        }
        return .timed(
            startMilliseconds: Self.milliseconds(startDate),
            endMilliseconds: Self.milliseconds(endDate),
            timeZoneID: displayTimeZone.identifier
        )
    }

    private static func isEarlier(
        _ lhs: (month: Int, day: Int),
        than rhs: (month: Int, day: Int)
    ) -> Bool {
        lhs.month < rhs.month || (lhs.month == rhs.month && lhs.day < rhs.day)
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}
