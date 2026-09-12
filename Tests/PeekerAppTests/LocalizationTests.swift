import XCTest
import PeekerCore
@testable import PeekerApp

@MainActor
final class LocalizationTests: XCTestCase {
    func testSwitchingLanguageUsesAllThreeNativeResourcesWithoutChangingMessageIdentity() {
        let context = AppLanguageContext()
        let message = LocalizedMessage("发现新版本 %1$@", bundle: L10n.resourceBundle, arguments: [.text("2.1.1")])
        context.selection = .english
        XCTAssertEqual(message.resolve(using: context), "Version 2.1.1 is available")
        context.selection = .japanese
        XCTAssertEqual(message.resolve(using: context), "バージョン 2.1.1 が利用可能です")
        context.selection = .simplifiedChinese
        XCTAssertEqual(message.resolve(using: context), "发现新版本 2.1.1")
        XCTAssertEqual(message.arguments, [.text("2.1.1")])
        XCTAssertEqual(message.diagnosticDescription, "发现新版本 2.1.1")
    }
}
