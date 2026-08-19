import XCTest
@testable import PeekerProtocol

final class ProtocolModelsTests: XCTestCase {
    func testEnvelopeRoundTripsArbitraryJSON() throws {
        let envelope = PeekerEnvelope.success(.object([
            "name": .string("Peeker"),
            "running": .bool(true),
            "values": .array([.number(1), .null]),
        ]))
        let data = try JSONEncoder().encode(envelope)
        XCTAssertEqual(try JSONDecoder().decode(PeekerEnvelope.self, from: data), envelope)
    }

    func testErrorCodesMapToStableExitCategories() {
        XCTAssertEqual(PeekerError(code: "invalid_usage", message: "").exitCode, 2)
        XCTAssertEqual(PeekerError(code: "app_not_running", message: "").exitCode, 3)
        XCTAssertEqual(PeekerError(code: "not_found", message: "").exitCode, 4)
        XCTAssertEqual(PeekerError(code: "conflict", message: "").exitCode, 5)
        XCTAssertEqual(PeekerError(code: "internal_error", message: "").exitCode, 6)
        XCTAssertEqual(PeekerError(code: "protocol_mismatch", message: "").exitCode, 7)
    }
}
