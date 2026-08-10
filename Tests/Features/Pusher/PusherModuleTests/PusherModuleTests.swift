import Foundation
import XCTest
import FeatureRuntimeKit
import MacPlatform
import PeekerCore
@testable import PusherModule

@MainActor
final class PusherModuleTests: XCTestCase {
    func testModuleOwnsPusherIdentityAndSchemaMigration() {
        let module = PusherModule()

        XCTAssertEqual(module.id, FeatureID(rawValue: "pusher"))
        XCTAssertEqual(module.databaseMigrations.map(\.id), ["pusher-schema-v1"])
    }

    func testPreferencesReadAndWritePublishedLegacyKeys() throws {
        let defaults = makeDefaults()
        defaults.set(9, forKey: "pusherRefreshHour")
        defaults.set(30, forKey: "pusherRefreshMinute")
        defaults.set(false, forKey: "pusherCarryIncomplete")
        let preferences = PusherModulePreferences(store: FeaturePreferenceStore(defaults: defaults))

        XCTAssertEqual(preferences.refreshTime, try RefreshTime(hour: 9, minute: 30))
        XCTAssertFalse(preferences.carryIncomplete)

        preferences.saveRefreshTime(try RefreshTime(hour: 11, minute: 5))
        preferences.carryIncomplete = true
        XCTAssertEqual(defaults.integer(forKey: "pusherRefreshHour"), 11)
        XCTAssertEqual(defaults.integer(forKey: "pusherRefreshMinute"), 5)
        XCTAssertTrue(defaults.bool(forKey: "pusherCarryIncomplete"))
    }

    func testUnavailablePersistenceStillProducesPusherRegistration() {
        let registration = PusherModule().makeRegistration(
            context: makeUnavailableContext()
        )

        XCTAssertEqual(registration.id, FeatureID(rawValue: "pusher"))
        XCTAssertEqual(registration.name, "Pusher")
    }

    private func makeUnavailableContext() -> FunctionCardModuleContext {
        let clock = PusherModuleTestClock()
        return FunctionCardModuleContext(
            persistence: .failure(StartupPersistenceError(message: "Unavailable")),
            clock: clock,
            resolver: BusinessDayResolver(),
            eventHub: TemporalEventHub(clock: clock, scheduler: PusherModuleTestScheduler()),
            audio: PusherModuleTestAudio(),
            preferences: FeaturePreferenceStore(defaults: makeDefaults()),
            hostActions: FunctionCardHostActionsBridge().actions
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PusherModuleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct PusherModuleTestClock: Clock {
    func now() -> Date { Date(timeIntervalSince1970: 0) }
}

private actor PusherModuleTestScheduler: TemporalScheduling {
    func schedule(at date: Date, action: @escaping @Sendable () -> Void) async {}
    func cancelAll() async {}
}

private actor PusherModuleTestAudio: AudioNotifying {
    func playCompletionSound() async {}
}
