import XCTest
@testable import MacPlatform

@MainActor
final class SettingsPresentationRouterTests: XCTestCase {
    func testInstalledActionRunsBetweenLifecycleCallbacksForEveryRequest() {
        var events: [String] = []
        let router = SettingsPresentationRouter(
            willOpen: { events.append("willOpen") },
            didOpen: { events.append("didOpen") }
        )
        router.install { events.append("openSettings") }

        router.requestOpen()
        router.requestOpen()

        XCTAssertEqual(
            events,
            [
                "willOpen", "openSettings", "didOpen",
                "willOpen", "openSettings", "didOpen",
            ]
        )
    }

    func testRequestsBeforeInstallationCoalesceAndFlushOnce() {
        var events: [String] = []
        let router = SettingsPresentationRouter(
            willOpen: { events.append("willOpen") },
            didOpen: { events.append("didOpen") }
        )

        router.requestOpen()
        router.requestOpen()
        XCTAssertTrue(events.isEmpty)

        router.install { events.append("openSettings") }

        XCTAssertEqual(events, ["willOpen", "openSettings", "didOpen"])
    }

    func testReplacingActionUsesLatestWithoutReplayingConsumedRequest() {
        var events: [String] = []
        let router = SettingsPresentationRouter()
        router.requestOpen()
        router.install { events.append("first") }

        router.install { events.append("second") }
        XCTAssertEqual(events, ["first"])

        router.requestOpen()
        XCTAssertEqual(events, ["first", "second"])
    }
}
