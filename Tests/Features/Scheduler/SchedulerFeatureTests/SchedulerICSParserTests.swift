import XCTest
@testable import SchedulerFeature

final class SchedulerICSParserTests: XCTestCase {
    func testParserSupportsFoldedTextOffsetRecurrenceExdateAndRdate() throws {
        let text = """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        BEGIN:VEVENT\r
        UID:series-1\r
        SUMMARY:Weekly \\n review\r
        DTSTART:20260810T090000+0800\r
        DTEND:20260810T093000+0800\r
        RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=3\r
        EXDATE:20260817T090000+0800\r
        RDATE:20260820T090000+0800\r
        END:VEVENT\r
        END:VCALENDAR\r
        """
        let result = try SchedulerICSParser.parse(Data(text.utf8), systemTimeZone: TimeZone(identifier: "Asia/Shanghai")!)
        XCTAssertEqual(result.series.count, 1)
        XCTAssertEqual(result.series[0].event.title, "Weekly \n review")
        XCTAssertEqual(result.series[0].overrides.count, 2)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testInvalidRecognizableUIDIsProtectedWhileOtherUIDImports() throws {
        let text = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:good
        SUMMARY:Good
        DTSTART:20260810T090000Z
        DTEND:20260810T100000Z
        END:VEVENT
        BEGIN:VEVENT
        UID:bad
        SUMMARY:Bad
        DTSTART;TZID=Custom/Unknown:20260810T090000
        DTEND;TZID=Custom/Unknown:20260810T100000
        END:VEVENT
        END:VCALENDAR
        """
        let result = try SchedulerICSParser.parse(Data(text.utf8))
        XCTAssertEqual(result.series.map(\.uid), ["good"])
        XCTAssertEqual(result.protectedUIDs, ["bad"])
        XCTAssertEqual(result.warnings.first?.uid, "bad")
    }

    func testFileWithoutCalendarFailsWithoutPartialResult() {
        XCTAssertThrowsError(try SchedulerICSParser.parse(Data("BEGIN:VEVENT\nEND:VEVENT".utf8)))
    }
}
