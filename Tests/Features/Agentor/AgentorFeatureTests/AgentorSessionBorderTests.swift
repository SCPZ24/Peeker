import XCTest
@testable import AgentorFeature

@MainActor
final class AgentorSessionBorderTests: XCTestCase {
    func testSharedPhaseHasOneStablePeriod() {
        XCTAssertEqual(AgentorVisualClock.phase(at: 0.8), 0.25, accuracy: 0.0001)
        XCTAssertEqual(AgentorVisualClock.phase(at: 4), 0.25, accuracy: 0.0001)
    }

    func testClientsShareDriverAndLastDepartureStopsIt() {
        let clock = AgentorVisualClock()
        let a = UUID(), b = UUID()
        clock.setActive(true, client: a)
        let phase = clock.phase
        clock.setActive(true, client: b)
        XCTAssertEqual(clock.phase, phase)
        clock.setActive(false, client: a)
        XCTAssertTrue(clock.isRunning)
        clock.setActive(false, client: b)
        XCTAssertFalse(clock.isRunning)
    }
}
