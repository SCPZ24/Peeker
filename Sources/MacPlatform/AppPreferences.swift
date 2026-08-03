import Foundation
import PeekerCore

@MainActor
public final class AppPreferences {
    private enum Key {
        static let targetScreen = "targetScreenID"
        static let enabledCards = "enabledCardIDs"
        static let cardOrder = "cardOrder"
        static let recentCard = "recentCardID"
        static let timerHour = "timerRefreshHour"
        static let timerMinute = "timerRefreshMinute"
        static let timerStatisticsMode = "timerStatisticsMode"
        static let pusherHour = "pusherRefreshHour"
        static let pusherMinute = "pusherRefreshMinute"
        static let carryIncomplete = "pusherCarryIncomplete"
        static let launchRegistrationAttempted = "launchRegistrationAttempted"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabledCards: [FeatureID.timer.rawValue, FeatureID.pusher.rawValue],
            Key.cardOrder: [FeatureID.timer.rawValue, FeatureID.pusher.rawValue],
            Key.recentCard: FeatureID.timer.rawValue,
            Key.timerHour: 0,
            Key.timerMinute: 0,
            Key.timerStatisticsMode: "progress",
            Key.pusherHour: 0,
            Key.pusherMinute: 0,
            Key.carryIncomplete: true,
        ])
    }

    public var targetScreenID: String? {
        get { defaults.string(forKey: Key.targetScreen) }
        set { defaults.set(newValue, forKey: Key.targetScreen) }
    }

    public var enabledCardIDs: [FeatureID] {
        (defaults.stringArray(forKey: Key.enabledCards) ?? []).map(FeatureID.init(rawValue:))
    }

    public var cardOrder: [FeatureID] {
        (defaults.stringArray(forKey: Key.cardOrder) ?? []).map(FeatureID.init(rawValue:))
    }

    public var recentCardID: FeatureID {
        FeatureID(rawValue: defaults.string(forKey: Key.recentCard) ?? FeatureID.timer.rawValue)
    }

    public func saveCards(enabled: [FeatureID], recent: FeatureID) {
        defaults.set(enabled.map(\.rawValue), forKey: Key.enabledCards)
        defaults.set(enabled.map(\.rawValue), forKey: Key.cardOrder)
        defaults.set(recent.rawValue, forKey: Key.recentCard)
    }

    public var timerRefreshTime: RefreshTime {
        (try? RefreshTime(
            hour: defaults.integer(forKey: Key.timerHour),
            minute: defaults.integer(forKey: Key.timerMinute)
        )) ?? .midnight
    }

    public func saveTimerRefreshTime(_ value: RefreshTime) {
        defaults.set(value.hour, forKey: Key.timerHour)
        defaults.set(value.minute, forKey: Key.timerMinute)
    }

    public var timerStatisticsModeRawValue: String {
        get { defaults.string(forKey: Key.timerStatisticsMode) ?? "progress" }
        set { defaults.set(newValue, forKey: Key.timerStatisticsMode) }
    }

    public var pusherRefreshTime: RefreshTime {
        (try? RefreshTime(
            hour: defaults.integer(forKey: Key.pusherHour),
            minute: defaults.integer(forKey: Key.pusherMinute)
        )) ?? .midnight
    }

    public func savePusherRefreshTime(_ value: RefreshTime) {
        defaults.set(value.hour, forKey: Key.pusherHour)
        defaults.set(value.minute, forKey: Key.pusherMinute)
    }

    public var pusherCarryIncomplete: Bool {
        get { defaults.bool(forKey: Key.carryIncomplete) }
        set { defaults.set(newValue, forKey: Key.carryIncomplete) }
    }

    public var hasAttemptedDefaultLaunchRegistration: Bool {
        get { defaults.bool(forKey: Key.launchRegistrationAttempted) }
        set { defaults.set(newValue, forKey: Key.launchRegistrationAttempted) }
    }
}
