import Foundation

public struct SchedulerTimedSegment: Identifiable, Equatable {
    public let occurrence: SchedulerOccurrence
    public let day: Int
    public let startMinute: CGFloat
    public let durationMinutes: CGFloat
    public var id: String { "\(occurrence.id):\(day)" }
}

public struct SchedulerEventPlacement: Identifiable, Equatable {
    public let segment: SchedulerTimedSegment
    public let column: Int
    public let columnCount: Int
    public var id: String { segment.id }
}

public enum SchedulerWeekLayout {
    public static func segments(for occurrence: SchedulerOccurrence, weekStart: Date, calendar: Calendar) -> [SchedulerTimedSegment] {
        guard case let .timed(startMS, endMS, _) = occurrence.time else { return [] }
        let start = Date(timeIntervalSince1970: Double(startMS) / 1000)
        let end = Date(timeIntervalSince1970: Double(endMS) / 1000)
        return (0..<7).compactMap { day in
            let dayStart = calendar.date(byAdding: .day, value: day, to: weekStart)!
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let first = max(start, dayStart), last = min(end, dayEnd)
            guard last > first else { return nil }
            let from = minute(first, calendar: calendar)
            let to = last == dayEnd ? 1440 : minute(last, calendar: calendar)
            return SchedulerTimedSegment(occurrence: occurrence, day: day, startMinute: from, durationMinutes: max(1, to - from))
        }
    }

    public static func placements(_ segments: [SchedulerTimedSegment], minimumMinutes: CGFloat = 0) -> [SchedulerEventPlacement] {
        var output: [SchedulerEventPlacement] = []
        for day in 0..<7 {
            let sorted = segments.filter { $0.day == day }.sorted {
                if $0.startMinute != $1.startMinute { return $0.startMinute < $1.startMinute }
                if $0.durationMinutes != $1.durationMinutes { return $0.durationMinutes > $1.durationMinutes }
                return $0.id < $1.id
            }
            var group: [(SchedulerTimedSegment, Int)] = []
            var ends: [CGFloat] = []
            func flush() {
                output += group.map { SchedulerEventPlacement(segment: $0.0, column: $0.1, columnCount: ends.count) }
                group.removeAll(keepingCapacity: true)
                ends.removeAll(keepingCapacity: true)
            }
            for segment in sorted {
                if let last = ends.max(), segment.startMinute >= last { flush() }
                let column = ends.firstIndex(where: { $0 <= segment.startMinute }) ?? ends.count
                let end = segment.startMinute + max(minimumMinutes, segment.durationMinutes)
                if column == ends.count { ends.append(end) } else { ends[column] = end }
                group.append((segment, column))
            }
            flush()
        }
        return output
    }

    private static func minute(_ date: Date, calendar: Calendar) -> CGFloat {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0)) + CGFloat(components.second ?? 0) / 60
    }
}

enum SchedulerAllDayLayout {
    static func visibleCount(_ total: Int) -> Int { total > 2 ? 1 : max(0, total) }
}
