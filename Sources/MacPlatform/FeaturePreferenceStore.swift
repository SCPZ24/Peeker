import Foundation

@MainActor
public final class FeaturePreferenceStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func register(defaults values: [String: Any]) {
        defaults.register(defaults: values)
    }

    public func integer(forKey key: String) -> Int {
        defaults.integer(forKey: key)
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func bool(forKey key: String) -> Bool {
        defaults.bool(forKey: key)
    }

    public func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}
