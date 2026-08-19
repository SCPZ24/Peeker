import Foundation
import XCTest
import FeatureRuntimeKit
import MacPlatform
import PeekerCore
@testable import TimerModule

@MainActor
final class TimerModuleTests: XCTestCase {
    func testModuleOwnsTimerIdentityAndSchemaMigration() {
        let module = TimerModule()

        XCTAssertEqual(module.id, FeatureID(rawValue: "timer"))
        XCTAssertEqual(module.databaseMigrations.map(\.id), ["timer-schema-v1"])
    }

    func testPreferencesReadAndWritePublishedLegacyKeys() throws {
        let defaults = makeDefaults()
        defaults.set(6, forKey: "timerRefreshHour")
        defaults.set(45, forKey: "timerRefreshMinute")
        defaults.set("calendar", forKey: "timerStatisticsMode")
        let preferences = TimerModulePreferences(store: FeaturePreferenceStore(defaults: defaults))

        XCTAssertEqual(preferences.refreshTime, try RefreshTime(hour: 6, minute: 45))
        XCTAssertEqual(preferences.statisticsModeRawValue, "calendar")

        preferences.saveRefreshTime(try RefreshTime(hour: 8, minute: 15))
        preferences.statisticsModeRawValue = "progress"
        XCTAssertEqual(defaults.integer(forKey: "timerRefreshHour"), 8)
        XCTAssertEqual(defaults.integer(forKey: "timerRefreshMinute"), 15)
        XCTAssertEqual(defaults.string(forKey: "timerStatisticsMode"), "progress")
    }

    func testUnavailablePersistenceStillProducesTimerRegistration() {
        let registration = TimerModule().makeRegistration(
            context: makeUnavailableContext()
        )

        XCTAssertEqual(registration.id, FeatureID(rawValue: "timer"))
        XCTAssertEqual(registration.name, "Timer")
    }

    private func makeUnavailableContext() -> FunctionCardModuleContext {
        let clock = TimerModuleTestClock()
        return FunctionCardModuleContext(
            persistence: .failure(StartupPersistenceError(message: "Unavailable")),
            clock: clock,
            resolver: BusinessDayResolver(),
            eventHub: TemporalEventHub(clock: clock, scheduler: TimerModuleTestScheduler()),
            preferences: FeaturePreferenceStore(defaults: makeDefaults()),
            hostActions: FunctionCardHostActionsBridge().actions
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "TimerModuleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct TimerModuleTestClock: Clock {
    func now() -> Date { Date(timeIntervalSince1970: 0) }
}

private actor TimerModuleTestScheduler: TemporalScheduling {
    func schedule(at date: Date, action: @escaping @Sendable () -> Void) async {}
    func cancelAll() async {}
}

