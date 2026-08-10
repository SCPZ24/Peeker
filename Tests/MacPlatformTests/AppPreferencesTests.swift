import Foundation
import XCTest
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

    private func makeDefaults() -> UserDefaults {
        let suiteName = "AppPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
