import Foundation
import XCTest
@testable import PeekerCore

final class CalendarMonthGridTests: XCTestCase {
    func testAugust2026ProducesCompleteSixWeekGrid() throws {
        let calendar = try makeCalendar(firstWeekday: 2)
        let displayed = try date(2026, 8, 7, calendar: calendar)
        let current = try date(2026, 8, 7, calendar: calendar)

        let grid = CalendarMonthGrid(
            displaying: displayed,
            currentBusinessDayStart: current,
            calendar: calendar,
            firstWeekday: 2
        )

        XCTAssertEqual(grid.weeks.count, 6)
        XCTAssertTrue(grid.weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(grid.weeks.flatMap { $0 }.filter(\.isInDisplayedMonth).count, 31)
        XCTAssertEqual(grid.weeks.flatMap { $0 }.filter(\.isCurrentBusinessDay).count, 1)
    }

    func testLeapFebruaryAndSundayFirstWeekdayHaveNoDuplicateDates() throws {
        let calendar = try makeCalendar(firstWeekday: 1)
        let displayed = try date(2024, 2, 15, calendar: calendar)
        let current = try date(2024, 2, 20, calendar: calendar)

        let grid = CalendarMonthGrid(
            displaying: displayed,
            currentBusinessDayStart: current,
            calendar: calendar,
            firstWeekday: 1
        )
        let days = grid.weeks.flatMap { $0 }

        XCTAssertEqual(grid.weeks.count, 5)
        XCTAssertEqual(days.filter(\.isInDisplayedMonth).count, 29)
        XCTAssertEqual(Set(days.map(\.id)).count, days.count)
        XCTAssertTrue(days.first(where: { calendar.isDate($0.date, inSameDayAs: try! date(2024, 2, 21, calendar: calendar)) })?.isFutureBusinessDay == true)
    }

    private func makeCalendar(firstWeekday: Int) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }
}
