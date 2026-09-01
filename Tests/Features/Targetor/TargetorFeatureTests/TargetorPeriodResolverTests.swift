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

    private func calendar(_ identifier: String) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: identifier)!
        return value
    }

    private func date(_ raw: String) -> Date {
        ISO8601DateFormatter().date(from: raw)!
    }
}
