import Foundation
import PeekerCore

@MainActor
enum L10n {
    nonisolated static var resourceBundle: Bundle {
        LocalizationResources.bundle(named: "Peeker_FunctionCardKit", fallback: .module)
    }

    nonisolated static func message(_ key: String, _ arguments: String...) -> LocalizedMessage {
        LocalizedMessage(key, bundle: resourceBundle, arguments: arguments.map { .text($0) })
    }

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        AppLanguageContext.shared.text(key, bundle: resourceBundle, arguments: arguments)
    }
}
