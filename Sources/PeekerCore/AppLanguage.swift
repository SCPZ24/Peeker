import Foundation
import Observation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case simplifiedChinese = "zh-Hans"
    case japanese = "ja"
    case english = "en"

    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        let code = preferredLanguages.first?.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        switch code {
        case "zh": return .simplifiedChinese
        case "ja": return .japanese
        default: return .english
        }
    }

    public var nativeName: String {
        switch self {
        case .system: "Follow System"
        case .simplifiedChinese: "中文（简体）"
        case .japanese: "日本語"
        case .english: "English"
        }
    }
}

@MainActor
@Observable
public final class AppLanguageContext {
    public static let shared = AppLanguageContext()
    public var selection: AppLanguage = .system
    public var systemLanguages: [String] = Locale.preferredLanguages
    public var language: AppLanguage { selection.resolved(preferredLanguages: systemLanguages) }
    public var locale: Locale { Locale(identifier: language.rawValue) }

    public init() {}

    public func text(_ key: String, bundle: Bundle, arguments: [CVarArg] = []) -> String {
        let english = bundle.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        let resourceLanguage = bundle.localizations.first { $0.caseInsensitiveCompare(language.rawValue) == .orderedSame } ?? language.rawValue
        let localized = bundle.path(forResource: resourceLanguage, ofType: "lproj").flatMap(Bundle.init(path:))
        let fallback = english?.localizedString(forKey: key, value: key, table: nil) ?? key
        let format = localized?.localizedString(forKey: key, value: fallback, table: nil) ?? fallback
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: arguments)
    }
}

public struct LocalizedMessage: Equatable, Sendable {
    public enum Argument: Equatable, Sendable {
        case text(String)
        case integer(Int)
        case decimal(Double)
        case time(Date)
        indirect case message(LocalizedMessage)

        @MainActor fileprivate func value(using context: AppLanguageContext) -> CVarArg {
            switch self {
            case let .text(value): value
            case let .integer(value): value
            case let .decimal(value): value
            case let .time(value): value.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: context.locale))
            case let .message(value): value.resolve(using: context)
            }
        }
    }

    public let key: String
    public let bundleURL: URL
    public let arguments: [Argument]

    public init(_ key: String, bundle: Bundle, arguments: [Argument] = []) {
        self.key = key
        bundleURL = bundle.bundleURL
        self.arguments = arguments
    }

    public var diagnosticDescription: String {
        guard !arguments.isEmpty else { return key }
        let values: [CVarArg] = arguments.map {
            switch $0 {
            case let .text(value): return value
            case let .integer(value): return value
            case let .decimal(value): return value
            case let .time(value): return value.formatted(date: .omitted, time: .shortened)
            case let .message(value): return value.diagnosticDescription
            }
        }
        return String(format: key, arguments: values)
    }

    @MainActor
    public func resolve(using context: AppLanguageContext = .shared) -> String {
        context.text(key, bundle: Bundle(url: bundleURL) ?? .main, arguments: arguments.map { $0.value(using: context) })
    }
}

public enum LocalizationResources {
    public static func bundle(named name: String, main: Bundle = .main, fallback: @autoclosure () -> Bundle) -> Bundle {
        if let url = main.resourceURL?.appendingPathComponent(name + ".bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return fallback()
    }
}
