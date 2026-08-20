import Foundation
import XCTest
@testable import SchedulerFeature

final class SchedulerEventTimeFormModelTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testTimedDraftResolvesValidMonthDayHourAndMinuteFields() throws {
        let draft = SchedulerEventTimeFormDraft(
            allDay: false,
            year: 2026,
            start: .init(month: "08", day: "20", hour: "09", minute: "15"),
            end: .init(month: "08", day: "20", hour: "10", minute: "45")
        )

        let time = try XCTUnwrap(draft.resolvedTime(displayTimeZone: utc))
        guard case let .timed(start, end, zone) = time else {
            return XCTFail("expected timed event")
        }

        XCTAssertEqual(components(start), DateComponents(year: 2026, month: 8, day: 20, hour: 9, minute: 15))
        XCTAssertEqual(components(end), DateComponents(year: 2026, month: 8, day: 20, hour: 10, minute: 45))
        XCTAssertEqual(zone, utc.identifier)
    }

    func testDraftInitializesFieldsFromExistingTimedEvent() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 20,
            hour: 9,
            minute: 5
        )))
        let end = try XCTUnwrap(calendar.date(byAdding: .minute, value: 55, to: start))
        let draft = SchedulerEventTimeFormDraft(
            time: .timed(
                startMilliseconds: Int64(start.timeIntervalSince1970 * 1_000),
                endMilliseconds: Int64(end.timeIntervalSince1970 * 1_000),
                timeZoneID: utc.identifier
            ),
            displayTimeZone: utc
        )

        XCTAssertFalse(draft.allDay)
        XCTAssertEqual(draft.year, 2026)
        XCTAssertEqual(draft.start, .init(month: "08", day: "20", hour: "09", minute: "05"))
        XCTAssertEqual(draft.end, .init(month: "08", day: "20", hour: "10", minute: "00"))
    }

    func testEndMonthDayBeforeStartRollsIntoNextYear() throws {
        let draft = SchedulerEventTimeFormDraft(
            allDay: false,
            year: 2026,
            start: .init(month: "12", day: "31", hour: "23", minute: "30"),
            end: .init(month: "01", day: "01", hour: "00", minute: "15")
        )

        let time = try XCTUnwrap(draft.resolvedTime(displayTimeZone: utc))
        guard case let .timed(_, end, _) = time else {
            return XCTFail("expected timed event")
        }

        XCTAssertEqual(components(end).year, 2027)
    }

    func testRejectsImpossibleDatesAndOutOfRangeClockFields() {
        let invalidFields: [SchedulerTimeInputDraft] = [
            .init(month: "02", day: "29", hour: "09", minute: "00"),
            .init(month: "04", day: "31", hour: "09", minute: "00"),
            .init(month: "13", day: "01", hour: "09", minute: "00"),
            .init(month: "08", day: "20", hour: "24", minute: "00"),
            .init(month: "08", day: "20", hour: "09", minute: "60"),
            .init(month: "08", day: "20", hour: "x", minute: "00"),
        ]

        for start in invalidFields {
            let draft = SchedulerEventTimeFormDraft(
                allDay: false,
                year: 2026,
                start: start,
                end: .init(month: "12", day: "31", hour: "23", minute: "59")
            )
            XCTAssertNil(draft.resolvedTime(displayTimeZone: utc), "unexpectedly accepted \(start)")
        }
    }

    func testAcceptsLeapDayOnlyInALeapYear() {
        let fields = SchedulerTimeInputDraft(month: "02", day: "29", hour: "09", minute: "00")
        let end = SchedulerTimeInputDraft(month: "02", day: "29", hour: "10", minute: "00")

        XCTAssertNotNil(SchedulerEventTimeFormDraft(allDay: false, year: 2028, start: fields, end: end).resolvedTime(displayTimeZone: utc))
        XCTAssertNil(SchedulerEventTimeFormDraft(allDay: false, year: 2027, start: fields, end: end).resolvedTime(displayTimeZone: utc))
    }

    func testRejectsNonexistentDSTWallClockTime() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let draft = SchedulerEventTimeFormDraft(
            allDay: false,
            year: 2026,
            start: .init(month: "03", day: "08", hour: "02", minute: "30"),
            end: .init(month: "03", day: "08", hour: "03", minute: "30")
        )

        XCTAssertNil(draft.resolvedTime(displayTimeZone: zone))
    }

    func testRejectsTimedEndThatDoesNotFollowStartOnSameDay() {
        let start = SchedulerTimeInputDraft(month: "08", day: "20", hour: "10", minute: "00")

        XCTAssertNil(SchedulerEventTimeFormDraft(
            allDay: false,
            year: 2026,
            start: start,
            end: .init(month: "08", day: "20", hour: "10", minute: "00")
        ).resolvedTime(displayTimeZone: utc))
        XCTAssertNil(SchedulerEventTimeFormDraft(
            allDay: false,
            year: 2026,
            start: start,
            end: .init(month: "08", day: "20", hour: "09", minute: "59")
        ).resolvedTime(displayTimeZone: utc))
    }

    func testAllDayDraftUsesOnlyMonthAndDayAndRequiresExclusiveEnd() throws {
        let valid = SchedulerEventTimeFormDraft(
            allDay: true,
            year: 2026,
            start: .init(month: "12", day: "31", hour: "invalid", minute: "invalid"),
            end: .init(month: "01", day: "02", hour: "invalid", minute: "invalid")
        )
        let time = try XCTUnwrap(valid.resolvedTime(displayTimeZone: utc))
        XCTAssertEqual(
            time,
            .allDay(
                start: try SchedulerLocalDate(year: 2026, month: 12, day: 31),
                endExclusive: try SchedulerLocalDate(year: 2027, month: 1, day: 2)
            )
        )

        let invalid = SchedulerEventTimeFormDraft(
            allDay: true,
            year: 2026,
            start: .init(month: "08", day: "20"),
            end: .init(month: "08", day: "20")
        )
        XCTAssertNil(invalid.resolvedTime(displayTimeZone: utc))
    }

    private func components(_ milliseconds: Int64) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        )
    }
}
