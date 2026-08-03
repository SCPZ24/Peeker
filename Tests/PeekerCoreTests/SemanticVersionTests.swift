import XCTest
@testable import PeekerCore

final class SemanticVersionTests: XCTestCase {
    func testVersionComparisonHandlesPrefixAndMissingPatch() throws {
        let current = try XCTUnwrap(SemanticVersion("v1.2"))
        let newer = try XCTUnwrap(SemanticVersion("1.2.1"))
        XCTAssertLessThan(current, newer)
    }

    func testMalformedVersionIsRejected() {
        XCTAssertNil(SemanticVersion("one.two"))
        XCTAssertNil(SemanticVersion(""))
    }
}
