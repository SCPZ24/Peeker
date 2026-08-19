import Foundation
import XCTest
@testable import SchedulerFeature

final class SchedulerRecurrenceTests: XCTestCase {
    func testDailyRecurrenceUsesCalendarAcrossDSTAndCountIncludesRoot() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let root = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9)))
        let event = try SchedulerEvent(
            title: "Daily", time: .timed(
                startMilliseconds: ms(root), endMilliseconds: ms(root.addingTimeInterval(1800)), timeZoneID: zone.identifier
            ), recurrence: SchedulerRecurrence(frequency: .daily, end: .count(3))
        )
        let values = SchedulerRecurrenceExpander.expand(
            snapshot: SchedulerSnapshot(events: [event], overrides: []),
            from: root.addingTimeInterval(-1), to: root.addingTimeInterval(4 * 86_400),
            displayTimeZone: zone, calendar: calendar
        )
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values.compactMap { startDate($0.time) }.map { calendar.component(.hour, from: $0) }, [9, 9, 9])
    }

    func testMonthlyMissingDayIsSkippedInsteadOfClamped() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let root = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 10))!
        let event = try SchedulerEvent(
            title: "Month end", time: .timed(startMilliseconds: ms(root), endMilliseconds: ms(root.addingTimeInterval(3600)), timeZoneID: zone.identifier),
            recurrence: SchedulerRecurrence(frequency: .monthly, end: .count(3))
        )
        let values = SchedulerRecurrenceExpander.expand(
            snapshot: SchedulerSnapshot(events: [event], overrides: []),
            from: root.addingTimeInterval(-1), to: calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!,
            displayTimeZone: zone, calendar: calendar
        )
        XCTAssertEqual(values.compactMap { startDate($0.time) }.map { calendar.component(.month, from: $0) }, [1, 3, 5])
    }

    func testCancellationAndMovedOverrideUseOriginalIdentityAndActualWindow() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = try SchedulerEvent(
            title: "Series", time: .timed(startMilliseconds: ms(start), endMilliseconds: ms(start.addingTimeInterval(1800)), timeZoneID: zone.identifier),
            recurrence: SchedulerRecurrence(frequency: .daily, end: .count(2))
        )
        let secondKey = String(ms(start.addingTimeInterval(86_400)))
        let moved = SchedulerOccurrence(
            eventID: event.id, originalKey: secondKey, title: "Moved", notes: nil, location: nil,
            colorHex: "#0A84FF", time: .timed(
                startMilliseconds: ms(start.addingTimeInterval(3 * 86_400)),
                endMilliseconds: ms(start.addingTimeInterval(3 * 86_400 + 1800)), timeZoneID: zone.identifier
            ), recurring: true, isException: true, sourceID: nil
        )
        let override = SchedulerOccurrenceOverride(eventID: event.id, occurrenceKey: secondKey, isCancelled: false, replacement: moved)
        let values = SchedulerRecurrenceExpander.expand(
            snapshot: SchedulerSnapshot(events: [event], overrides: [override]),
            from: start.addingTimeInterval(2.5 * 86_400), to: start.addingTimeInterval(4 * 86_400), displayTimeZone: zone
        )
        XCTAssertEqual(values.map(\.title), ["Moved"])
        XCTAssertEqual(values.first?.originalKey, secondKey)
    }

    private func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }
    private func startDate(_ value: SchedulerEventTime) -> Date? {
        if case let .timed(start, _, _) = value { return Date(timeIntervalSince1970: Double(start) / 1000) }
        return nil
    }
}
