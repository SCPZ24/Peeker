import Foundation
import XCTest
import SwiftUI
import FunctionCardKit
import PeekerCore
@testable import MacPlatform

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testEmptyDefaultsDoNotAssumeAnyConcreteFeature() {
        let defaults = makeDefaults()
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.enabledCardIDs, [])
        XCTAssertEqual(preferences.cardOrder, [])
        XCTAssertNil(preferences.recentCardID)
    }

    func testHoverExpansionDelayDefaultsToImmediate() {
        let preferences = AppPreferences(defaults: makeDefaults())

        XCTAssertEqual(preferences.hoverExpansionDelaySeconds, 0)
    }

    func testHoverExpansionDelayPersistsAndNormalizesToTenths() {
        let defaults = makeDefaults()
        let preferences = AppPreferences(defaults: defaults)

        preferences.hoverExpansionDelaySeconds = 0.26

        XCTAssertEqual(preferences.hoverExpansionDelaySeconds, 0.3)
        XCTAssertEqual(defaults.double(forKey: "hoverExpansionDelaySeconds"), 0.3)
    }

    func testHoverExpansionDelayClampsBoundsAndRejectsNonFiniteValues() {
        let defaults = makeDefaults()
        let preferences = AppPreferences(defaults: defaults)

        preferences.hoverExpansionDelaySeconds = -0.5
        XCTAssertEqual(preferences.hoverExpansionDelaySeconds, 0)

        preferences.hoverExpansionDelaySeconds = 3
        XCTAssertEqual(preferences.hoverExpansionDelaySeconds, 2)

        defaults.set(Double.infinity, forKey: "hoverExpansionDelaySeconds")
        XCTAssertEqual(preferences.hoverExpansionDelaySeconds, 0)

        defaults.set(Double.nan, forKey: "hoverExpansionDelaySeconds")
        XCTAssertEqual(preferences.hoverExpansionDelaySeconds, 0)
    }

    func testFreshInstallEnablesAllCardsInDefaultOrder() {
        let preferences = AppPreferences(defaults: makeDefaults())
        let snapshot = preferences.upgradedCards(registrations: registrations())

        XCTAssertEqual(snapshot.enabledIDs.map(\.rawValue), ["timer", "pusher", "scheduler"])
        XCTAssertEqual(snapshot.recentID.rawValue, "timer")
    }

    func testV1UpgradePreservesDisabledCardsAndAppendsSchedulerOnce() {
        let defaults = makeDefaults()
        defaults.set(["pusher"], forKey: "enabledCardIDs")
        defaults.set(["pusher"], forKey: "cardOrder")
        defaults.set("timer", forKey: "recentCardID")
        let preferences = AppPreferences(defaults: defaults)

        let first = preferences.upgradedCards(registrations: registrations())
        let second = preferences.upgradedCards(registrations: registrations())

        XCTAssertEqual(first.enabledIDs.map(\.rawValue), ["pusher", "scheduler"])
        XCTAssertEqual(first.recentID.rawValue, "pusher")
        XCTAssertEqual(second.enabledIDs, first.enabledIDs)
    }

    func testGenericFeaturePreferencesPreserveLegacyRawKeys() {
        let defaults = makeDefaults()
        defaults.set(7, forKey: "timerRefreshHour")
        defaults.set("calendar", forKey: "timerStatisticsMode")
        let preferences = FeaturePreferenceStore(defaults: defaults)

        preferences.register(defaults: [
            "timerRefreshHour": 0,
            "timerStatisticsMode": "progress",
            "pusherCarryIncomplete": true,
        ])

        XCTAssertEqual(preferences.integer(forKey: "timerRefreshHour"), 7)
        XCTAssertEqual(preferences.string(forKey: "timerStatisticsMode"), "calendar")
        XCTAssertTrue(preferences.bool(forKey: "pusherCarryIncomplete"))

        preferences.set(12, forKey: "timerRefreshHour")
        XCTAssertEqual(defaults.integer(forKey: "timerRefreshHour"), 12)
    }

    private func registrations() -> [FunctionCardRegistration] {
        [
            registration(id: "timer", order: 0, introduced: 1),
            registration(id: "pusher", order: 1, introduced: 1),
            registration(id: "scheduler", order: 2, introduced: 2),
        ]
    }

    private func registration(id: String, order: Int, introduced: Int) -> FunctionCardRegistration {
        FunctionCardRegistration(
            id: FeatureID(rawValue: id),
            name: id,
            systemImage: "circle",
            defaultOrder: order,
            introducedConfigurationVersion: introduced,
            metrics: FunctionCardMetrics(
                compactWidth: 1,
                compactHeight: 1,
                compactLeadingWidth: 1,
                compactTrailingWidth: 1,
                expandedWidth: 1,
                expandedHeight: 1
            ),
            makeCompactLeadingView: { AnyView(EmptyView()) },
            makeCompactTrailingView: { AnyView(EmptyView()) },
            makeExpandedView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) }
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
