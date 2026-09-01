import Foundation
import XCTest
import PeekerCore
@testable import TargetorFeature

final class TargetorPeriodResolverTests: XCTestCase {
    func testWeeklyRuleUsesRequestedWeekdayAndRefreshTime() throws {
        let resolver = TargetorPeriodResolver(calendar: calendar("UTC"))
        let boundary = resolver.nextBoundary(
            after: date("2026-08-10T10:00:00Z"),
            rule: try TargetorPeriodRule(frequency: .weekly, weekday: .wed),
            refreshTime: try RefreshTime(hour: 4, minute: 30)
        )
        XCTAssertEqual(boundary, date("2026-08-12T04:30:00Z"))
    }

    func testMonthlyDayZeroAndThirtyClampToMonthEnd() throws {
        let resolver = TargetorPeriodResolver(calendar: calendar("UTC"))
        let refresh = try RefreshTime(hour: 3, minute: 0)
        XCTAssertEqual(
            resolver.nextBoundary(
                after: date("2027-02-01T00:00:00Z"),
                rule: try TargetorPeriodRule(frequency: .monthly, monthDay: 0),
                refreshTime: refresh
            ),
            date("2027-02-28T03:00:00Z")
        )
        XCTAssertEqual(
            resolver.nextBoundary(
                after: date("2028-02-01T00:00:00Z"),
                rule: try TargetorPeriodRule(frequency: .monthly, monthDay: 30),
                refreshTime: refresh
            ),
            date("2028-02-29T03:00:00Z")
        )
    }

    func testDailyMissingDSTTimeUsesNextValidLocalTime() throws {
        let resolver = TargetorPeriodResolver(calendar: calendar("America/Los_Angeles"))
        let next = resolver.nextBoundary(
            after: date("2027-03-14T08:00:00Z"),
            rule: .daily,
            refreshTime: try RefreshTime(hour: 2, minute: 30)
        )
        XCTAssertEqual(next, date("2027-03-14T10:00:00Z"))
    }

    func testStateWireValuesAndThresholdsAreStable() {
        XCTAssertEqual(TargetorCheckinState.resolve(count: 0, maxCount: 4).rawValue, "notStarted")
        XCTAssertEqual(TargetorCheckinState.resolve(count: 1, maxCount: 4).rawValue, "started")
        XCTAssertEqual(TargetorCheckinState.resolve(count: 3, maxCount: 4).rawValue, "progressing")
        XCTAssertEqual(TargetorCheckinState.resolve(count: 4, maxCount: 4).rawValue, "completed")
    }

    func testCheckinPreviewUsesTheResultingStateIcon() {
        XCTAssertEqual(
            TargetorInteractionPresentation.checkinPromptIcon(currentCount: 0, maxCount: 4),
            "chevrons-up"
        )
        XCTAssertEqual(
            TargetorInteractionPresentation.checkinPromptIcon(currentCount: 2, maxCount: 4),
            "rocket"
        )
        XCTAssertEqual(
            TargetorInteractionPresentation.checkinPromptIcon(currentCount: 3, maxCount: 4),
            "badge-check"
        )
    }

    @MainActor
    func testExpandedMetricsRemainCompactEnoughForThreeColumnCards() {
        XCTAssertEqual(TargetorFeatureFactory.metrics.expandedWidth, 840)
        XCTAssertEqual(TargetorFeatureFactory.metrics.expandedHeight, 340)
    }

    func testCalendarChoosesLatestOverlappingPeriodForSameDay() throws {
        let targetID = UUID()
        let interval = DateInterval(start: date("2026-08-10T00:00:00Z"), end: date("2026-08-11T00:00:00Z"))
        let old = TargetorPeriod(
            targetID: targetID, sequence: 0,
            startMilliseconds: date("2026-08-09T00:00:00Z").millisecondsSince1970,
            endMilliseconds: date("2026-08-11T00:00:00Z").millisecondsSince1970,
            ruleSnapshot: .daily, maxCountSnapshot: 1,
            createdAtMilliseconds: date("2026-08-09T00:00:00Z").millisecondsSince1970,
            settledAtMilliseconds: date("2026-08-10T12:00:00Z").millisecondsSince1970,
            count: 1
        )
        let new = TargetorPeriod(
            targetID: targetID, sequence: 1,
            startMilliseconds: date("2026-08-10T12:00:00Z").millisecondsSince1970,
            endMilliseconds: date("2026-08-12T00:00:00Z").millisecondsSince1970,
            ruleSnapshot: try TargetorPeriodRule(frequency: .weekly, weekday: .wed),
            maxCountSnapshot: 2,
            createdAtMilliseconds: date("2026-08-10T12:00:00Z").millisecondsSince1970,
            count: 0
        )
        XCTAssertEqual(
            TargetorCalendarCalculator.period(for: interval, targetID: targetID, periods: [old, new])?.id,
            new.id
        )
    }

    func testNineWeekDatesAreOrderedAsWeekColumnsAndWeekdayRows() {
        let calendar = calendar("UTC")
        let dates = TargetorCalendarCalculator.nineWeekDates(
            containing: date("2026-08-19T12:00:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(dates.count, 63)
        let expectedWeekdays = [2, 3, 4, 5, 6, 7, 1]
        for row in 0..<7 {
            for column in 0..<9 {
                let value = dates[(row * 9) + column]
                XCTAssertEqual(calendar.component(.weekday, from: value), expectedWeekdays[row])
                if column > 0 {
                    XCTAssertEqual(
                        calendar.dateComponents(
                            [.day],
                            from: dates[(row * 9) + column - 1],
                            to: value
                        ).day,
                        7
                    )
                }
            }
        }
    }

    func testDailyTargetMonthCalendarLeavesPreCreationAndFutureDatesEmpty() throws {
        let resolver = TargetorPeriodResolver(calendar: calendar("UTC"))
        let now = date("2026-08-15T12:00:00Z")
        let created = date("2026-08-10T12:00:00Z")
        let target = try TargetorTarget(
            title: "Write",
            maxCount: 2,
            createdAtMilliseconds: created.millisecondsSince1970,
            updatedAtMilliseconds: created.millisecondsSince1970
        )
        let period = TargetorPeriod(
            targetID: target.id,
            sequence: 0,
            startMilliseconds: created.millisecondsSince1970,
            endMilliseconds: date("2026-08-11T00:00:00Z").millisecondsSince1970,
            ruleSnapshot: .daily,
            maxCountSnapshot: 2,
            createdAtMilliseconds: created.millisecondsSince1970,
            count: 1
        )
        let window = TargetorCalendarCalculator.targetWindow(
            frequency: .daily,
            containing: now,
            offset: 0,
            refreshTime: .midnight,
            resolver: resolver
        )
        let snapshot = TargetorCalendarCalculator.targetSnapshot(
            target: target,
            periods: [period],
            now: now,
            window: window
        )

        XCTAssertEqual(snapshot.granularity, .month)
        XCTAssertNil(cell(day: 9, in: snapshot, calendar: resolver.calendar).ratio)
        XCTAssertEqual(cell(day: 10, in: snapshot, calendar: resolver.calendar).ratio, 0.5)
        XCTAssertNil(cell(day: 16, in: snapshot, calendar: resolver.calendar).ratio)
    }

    func testWeeklyTargetUsesStableSequenceAcrossMonthCells() throws {
        let resolver = TargetorPeriodResolver(calendar: calendar("UTC"))
        let rule = try TargetorPeriodRule(frequency: .weekly, weekday: .wed)
        let created = date("2026-07-29T00:00:00Z")
        let target = try TargetorTarget(
            title: "Train",
            periodRule: rule,
            maxCount: 2,
            createdAtMilliseconds: created.millisecondsSince1970,
            updatedAtMilliseconds: created.millisecondsSince1970
        )
        let period = TargetorPeriod(
            targetID: target.id,
            sequence: 7,
            startMilliseconds: created.millisecondsSince1970,
            endMilliseconds: date("2026-08-05T00:00:00Z").millisecondsSince1970,
            ruleSnapshot: rule,
            maxCountSnapshot: 2,
            createdAtMilliseconds: created.millisecondsSince1970,
            count: 1
        )
        let window = TargetorCalendarCalculator.targetWindow(
            frequency: .weekly,
            containing: date("2026-08-02T12:00:00Z"),
            offset: 0,
            refreshTime: .midnight,
            resolver: resolver
        )
        let snapshot = TargetorCalendarCalculator.targetSnapshot(
            target: target,
            periods: [period],
            now: date("2026-08-10T12:00:00Z"),
            window: window
        )

        for day in 1...4 {
            let value = cell(day: day, in: snapshot, calendar: resolver.calendar)
            XCTAssertEqual(value.periodSequence, 7)
            XCTAssertEqual(value.periodFrequency, .weekly)
            XCTAssertEqual(value.ratio, 0.5)
        }
        XCTAssertEqual(TargetorCalendarHue.weekly(sequence: 7), .green)
        XCTAssertEqual(TargetorCalendarHue.weekly(sequence: 12), .green)
    }

    func testMonthlyTargetBuildsTwelveMonthYearGridAndLeavesFutureMonthsEmpty() throws {
        let resolver = TargetorPeriodResolver(calendar: calendar("UTC"))
        let rule = try TargetorPeriodRule(frequency: .monthly, monthDay: 20)
        let created = date("2026-07-20T00:00:00Z")
        let target = try TargetorTarget(
            title: "Ship",
            periodRule: rule,
            maxCount: 2,
            createdAtMilliseconds: created.millisecondsSince1970,
            updatedAtMilliseconds: created.millisecondsSince1970
        )
        let period = TargetorPeriod(
            targetID: target.id,
            sequence: 2,
            startMilliseconds: created.millisecondsSince1970,
            endMilliseconds: date("2026-08-20T00:00:00Z").millisecondsSince1970,
            ruleSnapshot: rule,
            maxCountSnapshot: 2,
            createdAtMilliseconds: created.millisecondsSince1970,
            count: 1
        )
        let now = date("2026-08-15T12:00:00Z")
        let window = TargetorCalendarCalculator.targetWindow(
            frequency: .monthly,
            containing: now,
            offset: 0,
            refreshTime: .midnight,
            resolver: resolver
        )
        let snapshot = TargetorCalendarCalculator.targetSnapshot(
            target: target,
            periods: [period],
            now: now,
            window: window
        )

        XCTAssertEqual(snapshot.granularity, .year)
        XCTAssertEqual(snapshot.cells.count, 12)
        XCTAssertEqual(cell(month: 7, in: snapshot, calendar: resolver.calendar).ratio, 0.5)
        XCTAssertEqual(cell(month: 8, in: snapshot, calendar: resolver.calendar).ratio, 0.5)
        XCTAssertNil(cell(month: 9, in: snapshot, calendar: resolver.calendar).ratio)
    }

    func testTargetorDateCellStartsAtRefreshTimeOnItsLocalDate() throws {
        let resolver = TargetorPeriodResolver(calendar: calendar("UTC"))
        let interval = resolver.dayInterval(
            startingOnLocalDate: date("2026-08-11T00:00:00Z"),
            refreshTime: try RefreshTime(hour: 4, minute: 0)
        )
        XCTAssertEqual(interval.start, date("2026-08-11T04:00:00Z"))
        XCTAssertEqual(interval.end, date("2026-08-12T04:00:00Z"))
    }

    private func cell(
        day: Int,
        in snapshot: TargetorTargetCalendarSnapshot,
        calendar: Calendar
    ) -> TargetorCalendarCell {
        snapshot.cells.first { calendar.component(.day, from: $0.date) == day }!
    }

    private func cell(
        month: Int,
        in snapshot: TargetorTargetCalendarSnapshot,
        calendar: Calendar
    ) -> TargetorCalendarCell {
        snapshot.cells.first { calendar.component(.month, from: $0.date) == month }!
    }

    private func calendar(_ identifier: String) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: identifier)!
        return value
    }

    private func date(_ raw: String) -> Date {
        ISO8601DateFormatter().date(from: raw)!
    }
}
