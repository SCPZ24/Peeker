import Foundation
import XCTest
@testable import PeekerCore

final class BusinessDayResolverTests: XCTestCase {
    func testBusinessDayUsesPreviousRefreshBoundaryBeforeTodaysRefresh() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let resolver = BusinessDayResolver(calendar: calendar)
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 5)))

        let day = resolver.businessDay(
            containing: now,
            featureID: FeatureID(rawValue: "timer"),
            refreshTime: try RefreshTime(hour: 6, minute: 30)
        )

        XCTAssertEqual(calendar.component(.day, from: day.start), 2)
        XCTAssertEqual(calendar.component(.hour, from: day.start), 6)
        XCTAssertEqual(calendar.component(.minute, from: day.start), 30)
        XCTAssertEqual(calendar.component(.day, from: day.end), 3)
    }

    func testNonexistentDSTRefreshMovesToNextValidLocalTime() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let resolver = BusinessDayResolver(calendar: calendar)
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))

        let day = resolver.businessDay(
            containing: noon,
            featureID: FeatureID(rawValue: "timer"),
            refreshTime: try RefreshTime(hour: 2, minute: 30)
        )

        XCTAssertEqual(calendar.component(.hour, from: day.start), 3)
        XCTAssertEqual(calendar.component(.minute, from: day.start), 0)
    }

    func testTargetWinsWhenTargetAndBoundaryAreEqual() {
        XCTAssertEqual(
            TemporalEventOrdering.next(targetAtMilliseconds: 500, boundaryAtMilliseconds: 500),
            .target
        )
    }

    func testRefreshChangeCreatesTransitionDayAtExistingFutureBoundary() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let resolver = BusinessDayResolver(calendar: calendar)
        let oldBoundary = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 0))
        )

        let transition = resolver.businessDay(
            startingAtBoundary: oldBoundary,
            featureID: .timer,
            refreshTime: try RefreshTime(hour: 6, minute: 0)
        )

        XCTAssertEqual(transition.start, oldBoundary)
        XCTAssertEqual(calendar.component(.hour, from: transition.end), 6)
        XCTAssertEqual(calendar.component(.day, from: transition.end), 4)
    }

    func testRepeatedDSTRefreshUsesFirstOccurrence() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let resolver = BusinessDayResolver(calendar: calendar)
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))

        let day = resolver.businessDay(
            containing: noon,
            featureID: .timer,
            refreshTime: try RefreshTime(hour: 1, minute: 30)
        )

        XCTAssertEqual(zone.secondsFromGMT(for: day.start), -4 * 3_600)
    }

    func testRefreshTimeRejectsOutOfRangeValues() {
        XCTAssertThrowsError(try RefreshTime(hour: 24, minute: 0))
        XCTAssertThrowsError(try RefreshTime(hour: 0, minute: 60))
    }
}
