import XCTest
import PeekerCore
@testable import MacPlatform

@MainActor
final class LanguagePreferenceTests: XCTestCase {
    func testLanguagePersistsAndInvalidSelectionFallsBackToSystem() throws {
        let name = "Peeker.LanguageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.language, .system)
        preferences.language = .japanese
        XCTAssertEqual(AppPreferences(defaults: defaults).language, .japanese)
        defaults.set("invalid", forKey: "appLanguage")
        XCTAssertEqual(AppPreferences(defaults: defaults).language, .system)
    }
}
