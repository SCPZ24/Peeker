import Foundation

public enum SchedulerRecurrenceExpander {
    public static func expand(
        snapshot: SchedulerSnapshot,
        from: Date,
        to: Date,
        displayTimeZone: TimeZone = .current,
        calendar baseCalendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [SchedulerOccurrence] {
        guard to > from else { return [] }
        let overrides = Dictionary(grouping: snapshot.overrides, by: \.eventID)
        var output: [SchedulerOccurrence] = []
        for event in snapshot.events {
            let generated = occurrences(
                event: event,
                from: from,
                to: to,
                displayTimeZone: displayTimeZone,
                calendar: baseCalendar
            )
            var generatedKeys = Set<String>()
            for occurrence in generated {
                generatedKeys.insert(occurrence.originalKey)
                if let override = overrides[event.id]?.first(where: { $0.occurrenceKey == occurrence.originalKey }) {
                    if !override.isCancelled, let replacement = override.replacement,
                       intersects(replacement.time, from: from, to: to, displayTimeZone: displayTimeZone) {
                        output.append(replacementWithException(replacement))
                    }
                } else {
                    output.append(occurrence)
                }
            }
            for override in overrides[event.id] ?? [] where !generatedKeys.contains(override.occurrenceKey) {
                if !override.isCancelled, let replacement = override.replacement,
                   intersects(replacement.time, from: from, to: to, displayTimeZone: displayTimeZone) {
                    output.append(replacementWithException(replacement))
                }
            }
        }
        return output.sorted(by: stableOrder)
    }

    private static func occurrences(
        event: SchedulerEvent,
        from: Date,
        to: Date,
        displayTimeZone: TimeZone,
        calendar baseCalendar: Calendar
    ) -> [SchedulerOccurrence] {
        guard let recurrence = event.recurrence else {
            let occurrence = makeOccurrence(event: event, time: event.time, originalKey: originalKey(event.time), exception: false)
            return intersects(event.time, from: from, to: to, displayTimeZone: displayTimeZone) ? [occurrence] : []
        }

        var calendar = baseCalendar
        let timeZone: TimeZone
        let rootDate: Date
        let duration: TimeInterval
        let allDayDuration: Int?
        switch event.time {
        case let .timed(start, end, zoneID):
            timeZone = TimeZone(identifier: zoneID) ?? displayTimeZone
            calendar.timeZone = timeZone
            rootDate = Date(timeIntervalSince1970: Double(start) / 1000)
            duration = Double(end - start) / 1000
            allDayDuration = nil
        case let .allDay(start, end):
            timeZone = displayTimeZone
            calendar.timeZone = timeZone
            guard let date = start.date(in: timeZone),
                  let endDate = end.date(in: timeZone) else { return [] }
            rootDate = date
            duration = endDate.timeIntervalSince(date)
            allDayDuration = calendar.dateComponents([.day], from: date, to: endDate).day
        }

        var dates: [Date] = [rootDate]
        let hardLimit = 1_000_000
        var cursor = rootDate
        var period = 0
        while dates.count < hardLimit {
            period += 1
            guard let candidate = nextCandidate(
                after: cursor,
                root: rootDate,
                period: period,
                recurrence: recurrence,
                calendar: calendar
            ) else { continue }
            cursor = candidate
            if candidate <= rootDate { continue }
            if exceedsEnd(candidate, occurrenceNumber: dates.count + 1, recurrence: recurrence, allDay: allDayDuration != nil, calendar: calendar) { break }
            dates.append(candidate)
            if candidate >= to.addingTimeInterval(max(duration, 86_400)), recurrence.end == .never { break }
        }

        return dates.compactMap { date in
            let occurrenceTime: SchedulerEventTime
            switch event.time {
            case let .timed(_, _, zone):
                let start = Int64((date.timeIntervalSince1970 * 1000).rounded())
                occurrenceTime = .timed(startMilliseconds: start, endMilliseconds: start + Int64(duration * 1000), timeZoneID: zone)
            case .allDay:
                guard let dayCount = allDayDuration,
                      let start = localDate(date, calendar: calendar),
                      let end = start.adding(days: dayCount, in: timeZone) else { return nil }
                occurrenceTime = .allDay(start: start, endExclusive: end)
            }
            guard intersects(occurrenceTime, from: from, to: to, displayTimeZone: displayTimeZone) else { return nil }
            return makeOccurrence(event: event, time: occurrenceTime, originalKey: originalKey(occurrenceTime), exception: false)
        }
    }

    private static func nextCandidate(
        after cursor: Date,
        root: Date,
        period: Int,
        recurrence: SchedulerRecurrence,
        calendar: Calendar
    ) -> Date? {
        switch recurrence.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: recurrence.interval, to: cursor)
        case .monthly:
            let rootComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: root)
            guard let monthBase = calendar.date(byAdding: .month, value: period * recurrence.interval, to: root),
                  var candidate = Optional(calendar.dateComponents([.year, .month], from: monthBase)) else { return nil }
            candidate.day=rootComponents.day; candidate.hour=rootComponents.hour; candidate.minute=rootComponents.minute
            candidate.second=rootComponents.second; candidate.nanosecond=rootComponents.nanosecond
            guard let result = calendar.date(from: candidate), calendar.component(.day, from: result) == rootComponents.day else { return nil }
            return result
        case .yearly:
            let rootComponents = calendar.dateComponents([.month, .day, .hour, .minute, .second, .nanosecond], from: root)
            var candidate = rootComponents
            candidate.year = calendar.component(.year, from: root) + period * recurrence.interval
            guard let result = calendar.date(from: candidate),
                  calendar.component(.month, from: result) == rootComponents.month,
                  calendar.component(.day, from: result) == rootComponents.day else { return nil }
            return result
        case .weekly:
            let weekdays = recurrence.weekdays.isEmpty
                ? [calendar.component(.weekday, from: root)]
                : recurrence.weekdays.map(\.calendarWeekday)
            var day = cursor
            for _ in 0..<8_000 {
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
                day = next
                let dayDistance = calendar.dateComponents([.day], from: calendar.startOfDay(for: root), to: calendar.startOfDay(for: day)).day ?? 0
                let week = dayDistance / 7
                if week % recurrence.interval == 0, weekdays.contains(calendar.component(.weekday, from: day)) { return day }
            }
            return nil
        }
    }

    private static func exceedsEnd(
        _ date: Date,
        occurrenceNumber: Int,
        recurrence: SchedulerRecurrence,
        allDay: Bool,
        calendar: Calendar
    ) -> Bool {
        switch recurrence.end {
        case .never: return false
        case let .count(count): return occurrenceNumber > count
        case let .untilTimed(milliseconds): return date.timeIntervalSince1970 * 1000 > Double(milliseconds)
        case let .untilDate(until):
            guard let candidate = localDate(date, calendar: calendar) else { return true }
            return candidate > until
        }
    }

    public static func originalKey(_ time: SchedulerEventTime) -> String {
        switch time {
        case let .timed(start, _, _): String(start)
        case let .allDay(start, _): start.description
        }
    }

    private static func makeOccurrence(event: SchedulerEvent, time: SchedulerEventTime, originalKey: String, exception: Bool) -> SchedulerOccurrence {
        SchedulerOccurrence(
            eventID: event.id, originalKey: originalKey, title: event.title, notes: event.notes,
            location: event.location, colorHex: event.colorHex, time: time,
            recurring: event.recurrence != nil, isException: exception, sourceID: event.sourceID
        )
    }

    private static func replacementWithException(_ value: SchedulerOccurrence) -> SchedulerOccurrence {
        SchedulerOccurrence(
            eventID: value.eventID, originalKey: value.originalKey, title: value.title, notes: value.notes,
            location: value.location, colorHex: value.colorHex, time: value.time,
            recurring: value.recurring, isException: true, sourceID: value.sourceID
        )
    }

    private static func intersects(_ time: SchedulerEventTime, from: Date, to: Date, displayTimeZone: TimeZone) -> Bool {
        switch time {
        case let .timed(start, end, _):
            return Date(timeIntervalSince1970: Double(end) / 1000) > from && Date(timeIntervalSince1970: Double(start) / 1000) < to
        case let .allDay(start, end):
            guard let startDate = start.date(in: displayTimeZone), let endDate = end.date(in: displayTimeZone) else { return false }
            return endDate > from && startDate < to
        }
    }

    private static func localDate(_ date: Date, calendar: Calendar) -> SchedulerLocalDate? {
        try? SchedulerLocalDate(
            year: calendar.component(.year, from: date),
            month: calendar.component(.month, from: date),
            day: calendar.component(.day, from: date)
        )
    }

    private static func stableOrder(_ lhs: SchedulerOccurrence, _ rhs: SchedulerOccurrence) -> Bool {
        let left = sortDates(lhs.time); let right = sortDates(rhs.time)
        if left.0 != right.0 { return left.0 < right.0 }
        if left.1 != right.1 { return left.1 < right.1 }
        if lhs.eventID != rhs.eventID { return lhs.eventID.uuidString < rhs.eventID.uuidString }
        return lhs.originalKey < rhs.originalKey
    }

    private static func sortDates(_ time: SchedulerEventTime) -> (String, String) {
        switch time {
        case let .timed(start, end, _): return (String(format: "%020lld", start), String(format: "%020lld", end))
        case let .allDay(start, end): return (start.description, end.description)
        }
    }
}
