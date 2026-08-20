import Foundation
import FunctionCardKit
import PeekerCore

public struct CardPreferenceSnapshot: Equatable, Sendable {
    public let configurationVersion: Int
    public let enabledIDs: [FeatureID]
    public let recentID: FeatureID
    public let knownIDs: [FeatureID]
    public let lastOpenedAt: [FeatureID: Date]

    public init(
        configurationVersion: Int,
        enabledIDs: [FeatureID],
        recentID: FeatureID,
        knownIDs: [FeatureID],
        lastOpenedAt: [FeatureID: Date]
    ) {
        self.configurationVersion = configurationVersion
        self.enabledIDs = enabledIDs
        self.recentID = recentID
        self.knownIDs = knownIDs
        self.lastOpenedAt = lastOpenedAt
    }
}

@MainActor
public final class AppPreferences {
    private enum Key {
        static let targetScreen = "targetScreenID"
        static let enabledCards = "enabledCardIDs"
        static let cardOrder = "cardOrder"
        static let recentCard = "recentCardID"
        static let launchRegistrationAttempted = "launchRegistrationAttempted"
        static let cardConfigurationVersion = "cardConfigurationVersion"
        static let knownCardIDs = "knownCardIDs"
        static let lastOpenedCardDates = "lastOpenedCardDates"
        static let hoverExpansionDelaySeconds = "hoverExpansionDelaySeconds"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var targetScreenID: String? {
        get { defaults.string(forKey: Key.targetScreen) }
        set { defaults.set(newValue, forKey: Key.targetScreen) }
    }

    public var hoverExpansionDelaySeconds: Double {
        get { Self.normalizedHoverExpansionDelay(defaults.double(forKey: Key.hoverExpansionDelaySeconds)) }
        set { defaults.set(Self.normalizedHoverExpansionDelay(newValue), forKey: Key.hoverExpansionDelaySeconds) }
    }

    public static func normalizedHoverExpansionDelay(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (min(2, max(0, value)) * 10).rounded() / 10
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

    public func upgradedCards(
        registrations: [FunctionCardRegistration],
        targetVersion: Int = 2
    ) -> CardPreferenceSnapshot {
        let sorted = registrations.sorted { $0.defaultOrder < $1.defaultOrder }
        let allIDs = sorted.map(\.id)
        let allIDSet = Set(allIDs)
        let hasStoredV1Preferences = defaults.object(forKey: Key.enabledCards) != nil
            || defaults.object(forKey: Key.cardOrder) != nil
            || defaults.object(forKey: Key.recentCard) != nil
        let storedVersion = defaults.object(forKey: Key.cardConfigurationVersion) == nil
            ? (hasStoredV1Preferences ? 1 : 0)
            : defaults.integer(forKey: Key.cardConfigurationVersion)

        var enabled: [FeatureID]
        if storedVersion == 0 {
            enabled = sorted.filter(\.defaultEnabled).map(\.id)
        } else {
            let storedEnabled = enabledCardIDs.filter(allIDSet.contains)
            let enabledSet = Set(storedEnabled)
            let storedOrder = cardOrder.filter(allIDSet.contains)
            enabled = storedOrder.filter(enabledSet.contains)
            enabled.append(contentsOf: storedEnabled.filter { !enabled.contains($0) })
            for registration in sorted where registration.defaultEnabled
                && registration.introducedConfigurationVersion > storedVersion
                && registration.introducedConfigurationVersion <= targetVersion
                && !enabled.contains(registration.id) {
                enabled.append(registration.id)
            }
        }
        if enabled.isEmpty, let fallback = sorted.first(where: \.defaultEnabled)?.id ?? allIDs.first {
            enabled = [fallback]
        }
        precondition(!enabled.isEmpty, "At least one function card must be registered")
        let recent = recentCardID.flatMap { enabled.contains($0) ? $0 : nil } ?? enabled[0]
        let snapshot = CardPreferenceSnapshot(
            configurationVersion: targetVersion,
            enabledIDs: enabled,
            recentID: recent,
            knownIDs: allIDs,
            lastOpenedAt: lastOpenedCardDates.filter { allIDSet.contains($0.key) }
        )
        persist(snapshot)
        return snapshot
    }

    public func saveCards(enabled: [FeatureID], recent: FeatureID) {
        defaults.set(enabled.map(\.rawValue), forKey: Key.enabledCards)
        defaults.set(enabled.map(\.rawValue), forKey: Key.cardOrder)
        defaults.set(recent.rawValue, forKey: Key.recentCard)
    }

    public func markCardOpened(_ id: FeatureID, at date: Date = Date()) {
        var values = defaults.dictionary(forKey: Key.lastOpenedCardDates) as? [String: Double] ?? [:]
        values[id.rawValue] = date.timeIntervalSince1970
        defaults.set(values, forKey: Key.lastOpenedCardDates)
    }

    public var lastOpenedCardDates: [FeatureID: Date] {
        let values = defaults.dictionary(forKey: Key.lastOpenedCardDates) as? [String: Double] ?? [:]
        return Dictionary(uniqueKeysWithValues: values.map {
            (FeatureID(rawValue: $0.key), Date(timeIntervalSince1970: $0.value))
        })
    }

    private func persist(_ snapshot: CardPreferenceSnapshot) {
        saveCards(enabled: snapshot.enabledIDs, recent: snapshot.recentID)
        defaults.set(snapshot.configurationVersion, forKey: Key.cardConfigurationVersion)
        defaults.set(snapshot.knownIDs.map(\.rawValue), forKey: Key.knownCardIDs)
        defaults.set(
            Dictionary(uniqueKeysWithValues: snapshot.lastOpenedAt.map {
                ($0.key.rawValue, $0.value.timeIntervalSince1970)
            }),
            forKey: Key.lastOpenedCardDates
        )
    }

    public var hasAttemptedDefaultLaunchRegistration: Bool {
        get { defaults.bool(forKey: Key.launchRegistrationAttempted) }
        set { defaults.set(newValue, forKey: Key.launchRegistrationAttempted) }
    }
}
