import Foundation
import PeekerCore

@MainActor
public final class AppPreferences {
    private enum Key {
        static let targetScreen = "targetScreenID"
        static let enabledCards = "enabledCardIDs"
        static let cardOrder = "cardOrder"
        static let recentCard = "recentCardID"
        static let launchRegistrationAttempted = "launchRegistrationAttempted"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

    public var recentCardID: FeatureID? {
        defaults.string(forKey: Key.recentCard).map(FeatureID.init(rawValue:))
    }

    public func saveCards(enabled: [FeatureID], recent: FeatureID) {
        defaults.set(enabled.map(\.rawValue), forKey: Key.enabledCards)
        defaults.set(enabled.map(\.rawValue), forKey: Key.cardOrder)
        defaults.set(recent.rawValue, forKey: Key.recentCard)
    }

    public var hasAttemptedDefaultLaunchRegistration: Bool {
        get { defaults.bool(forKey: Key.launchRegistrationAttempted) }
        set { defaults.set(newValue, forKey: Key.launchRegistrationAttempted) }
    }
}
