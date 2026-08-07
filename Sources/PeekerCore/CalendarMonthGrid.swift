import Foundation

public struct CalendarMonthDay: Identifiable, Equatable, Sendable {
    public let id: Date
    public let date: Date
    public let isInDisplayedMonth: Bool
    public let isCurrentBusinessDay: Bool
    public let isFutureBusinessDay: Bool

    public init(
        date: Date,
        isInDisplayedMonth: Bool,
        isCurrentBusinessDay: Bool,
        isFutureBusinessDay: Bool
    ) {
        self.id = date
        self.date = date
        self.isInDisplayedMonth = isInDisplayedMonth
        self.isCurrentBusinessDay = isCurrentBusinessDay
        self.isFutureBusinessDay = isFutureBusinessDay
    }
}

public struct CalendarMonthGrid: Equatable, Sendable {
    public let monthStart: Date
    public let weeks: [[CalendarMonthDay]]

    public init(
        displaying displayedDate: Date,
        currentBusinessDayStart: Date,
        calendar inputCalendar: Calendar = .autoupdatingCurrent,
        firstWeekday: Int? = nil
    ) {
        var calendar = inputCalendar
        if let firstWeekday { calendar.firstWeekday = firstWeekday }

        let monthInterval = calendar.dateInterval(of: .month, for: displayedDate)!
        let normalizedMonthStart = calendar.startOfDay(for: monthInterval.start)
        let currentDate = calendar.startOfDay(for: currentBusinessDayStart)
        let weekday = calendar.component(.weekday, from: normalizedMonthStart)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: normalizedMonthStart)!
        let daysInMonth = calendar.range(of: .day, in: .month, for: normalizedMonthStart)!.count
        let requiredDays = leadingDays + daysInMonth
        let cellCount = max(35, Int(ceil(Double(requiredDays) / 7.0)) * 7)

        var cells: [CalendarMonthDay] = []
        cells.reserveCapacity(cellCount)
        for offset in 0..<cellCount {
            let date = calendar.date(byAdding: .day, value: offset, to: gridStart)!
            let normalized = calendar.startOfDay(for: date)
            cells.append(
                CalendarMonthDay(
                    date: normalized,
                    isInDisplayedMonth: calendar.isDate(normalized, equalTo: normalizedMonthStart, toGranularity: .month),
                    isCurrentBusinessDay: calendar.isDate(normalized, inSameDayAs: currentDate),
                    isFutureBusinessDay: normalized > currentDate
                )
            )
        }

        monthStart = normalizedMonthStart
        weeks = stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)])
        }
    }

    public func snapshotQueryInterval(calendar: Calendar = .autoupdatingCurrent) -> DateInterval {
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        return DateInterval(
            start: calendar.date(byAdding: .day, value: -1, to: monthStart)!,
            end: calendar.date(byAdding: .day, value: 1, to: nextMonth)!
        )
    }
}
