import XCTest
@testable import PeekerCore

final class AppLanguageTests: XCTestCase {
    func testSystemUsesPrimaryLanguageAndFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["zh-TW", "en"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["ja-JP"]), .japanese)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "ja"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: []), .english)
        XCTAssertEqual(AppLanguage.japanese.resolved(preferredLanguages: ["en-US"]), .japanese)
    }
}
