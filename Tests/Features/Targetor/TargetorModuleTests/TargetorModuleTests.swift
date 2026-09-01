import XCTest
import TargetorModule

@MainActor
final class TargetorModuleTests: XCTestCase {
    func testModuleCanBeConstructed() {
        _ = TargetorModule()
    }
}
