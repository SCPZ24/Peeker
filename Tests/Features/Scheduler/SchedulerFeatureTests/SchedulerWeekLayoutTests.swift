import XCTest
@testable import SchedulerFeature

final class SchedulerWeekLayoutTests: XCTestCase {
    func testAllDayOverflowReservesTheSecondRowForAccessToEveryRemainingEvent() {
        XCTAssertEqual([0, 1, 2, 3, 10].map(SchedulerAllDayLayout.visibleCount), [0, 1, 2, 1, 1])
    }

    func testOverlapsUseDistinctColumnsAndTouchingEventsReuseThem() {
        let a = segment(start: 60, duration: 60)
        let b = segment(start: 75, duration: 15)
        let c = segment(start: 80, duration: 80)
        let d = segment(start: 160, duration: 30)
        let result = SchedulerWeekLayout.placements([c, d, b, a])
        XCTAssertEqual(result.prefix(3).map(\.columnCount), [3, 3, 3])
        XCTAssertEqual(Set(result.prefix(3).map(\.column)).count, 3)
        XCTAssertEqual(result.last?.columnCount, 1)
        XCTAssertEqual(result.map(\.id), SchedulerWeekLayout.placements([a, b, c, d]).map(\.id))
    }

    func testMinimumVisibleHeightDoesNotCoverFollowingShortEvent() {
        let result = SchedulerWeekLayout.placements([segment(start: 60, duration: 1), segment(start: 61, duration: 1)], minimumMinutes: 20)
        XCTAssertEqual(result.map(\.columnCount), [2, 2])
        XCTAssertNotEqual(result[0].column, result[1].column)
    }

    func testDSTLayoutUsesWallClockRatherThanElapsedHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 9)))
        let occurrence = SchedulerOccurrence(eventID: UUID(), originalKey: "key", title: "Event", notes: nil, location: nil, colorHex: "#0A84FF", time: .timed(startMilliseconds: Int64(start.timeIntervalSince1970 * 1000), endMilliseconds: Int64(start.addingTimeInterval(3600).timeIntervalSince1970 * 1000), timeZoneID: calendar.timeZone.identifier), recurring: false, isException: false, sourceID: nil)
        let value = try XCTUnwrap(SchedulerWeekLayout.segments(for: occurrence, weekStart: day, calendar: calendar).first)
        XCTAssertEqual(value.startMinute, 540)
        XCTAssertEqual(value.durationMinutes, 60)
        XCTAssertEqual(value.occurrence.originalKey, "key")
    }

    private func segment(start: CGFloat, duration: CGFloat) -> SchedulerTimedSegment {
        SchedulerTimedSegment(occurrence: SchedulerOccurrence(eventID: UUID(), originalKey: "key", title: "Event", notes: nil, location: nil, colorHex: "#0A84FF", time: .timed(startMilliseconds: 1, endMilliseconds: 2, timeZoneID: "UTC"), recurring: false, isException: false, sourceID: nil), day: 0, startMinute: start, durationMinutes: duration)
    }
}
