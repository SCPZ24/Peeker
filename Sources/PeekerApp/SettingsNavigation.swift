import FunctionCardKit
import PeekerCore

enum SettingsDestination: Hashable {
    case general
    case cards
    case feature(FeatureID)
    case about
}

@MainActor
enum SettingsNavigation {
    static func destinations(
        registrations: [FunctionCardRegistration]
    ) -> [SettingsDestination] {
        [.general, .cards]
            + registrations.map { .feature($0.id) }
            + [.about]
    }

    static func resolve(
        selection: SettingsDestination,
        registrations: [FunctionCardRegistration]
    ) -> SettingsDestination {
        guard case let .feature(id) = selection else { return selection }
        return registrations.contains(where: { $0.id == id }) ? selection : .general
    }
}
