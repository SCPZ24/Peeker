import Foundation
import PeekerCore

@MainActor
enum AppResourceVerification {
    static func run(bundle: Bundle = .main) throws {
        guard let resources = bundle.resourceURL,
              let manifest = try? String(contentsOf: resources.appendingPathComponent("localization-bundles.txt"), encoding: .utf8)
        else { throw VerificationError.invalid("Missing localization bundle manifest") }
        let names = manifest.split(separator: "\n").map(String.init)
        guard !names.isEmpty else { throw VerificationError.invalid("No localization bundles") }
        for name in names {
            let url = resources.appendingPathComponent(name)
            guard let resourceBundle = Bundle(url: url) else { throw VerificationError.invalid("Missing bundle: \(name)") }
            var reference: Set<String>?
            for language in [AppLanguage.english, .japanese, .simplifiedChinese] {
                guard let folder = resourceBundle.localizations.first(where: { $0.caseInsensitiveCompare(language.rawValue) == .orderedSame }),
                      let directory = resourceBundle.url(forResource: folder, withExtension: "lproj") else {
                    throw VerificationError.invalid("Missing \(language.rawValue) in \(name)")
                }
                let data = try Data(contentsOf: directory.appendingPathComponent("Localizable.strings"))
                guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String], !values.isEmpty else {
                    throw VerificationError.invalid("Invalid strings in \(name)")
                }
                let keys = Set(values.keys)
                if let reference, reference != keys { throw VerificationError.invalid("Mismatched keys in \(name)") }
                reference = keys
                let context = AppLanguageContext()
                context.selection = language
                for (key, expected) in values where !expected.contains("%") {
                    guard context.text(key, bundle: resourceBundle) == expected else {
                        throw VerificationError.invalid("Unresolved translation: \(name)/\(folder)/\(key)")
                    }
                }
            }
        }
        guard L10n.resourceBundle.bundleURL.deletingLastPathComponent().standardizedFileURL == resources.standardizedFileURL else {
            throw VerificationError.invalid("App localization resolved outside the app bundle")
        }
    }

    private enum VerificationError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { switch self { case let .invalid(message): message } }
    }
}
