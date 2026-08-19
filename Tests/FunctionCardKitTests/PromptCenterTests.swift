import XCTest
import SwiftUI
import PeekerCore
@testable import FunctionCardKit

@MainActor
final class PromptCenterTests: XCTestCase {
    private let timer = FeatureID(rawValue: "timer")
    private let pusher = FeatureID(rawValue: "pusher")

    func testQueueIsFIFOAndRejectsThe101stItem() async {
        let center = PromptCenter()
        center.setPlaybackAllowed(false)
        for index in 0..<PromptCenter.capacity {
            XCTAssertTrue(center.publish(prompt(index, source: timer)))
        }
        XCTAssertFalse(center.publish(prompt(100, source: timer)))
        XCTAssertEqual(center.count, 100)

        center.setPlaybackAllowed(true)
        await Task.yield()
        XCTAssertEqual(center.current?.token, "0")
        _ = center.consumeCurrent()
        await Task.yield()
        XCTAssertEqual(center.current?.token, "1")
    }

    func testDuplicateTokenAndDisabledSourceCleanupDoNotDisplaceEarlierItems() async {
        let center = PromptCenter()
        center.setPlaybackAllowed(false)
        XCTAssertTrue(center.publish(prompt(1, source: timer)))
        XCTAssertFalse(center.publish(prompt(1, source: timer)))
        XCTAssertTrue(center.publish(prompt(2, source: pusher)))

        center.clear(sourceID: timer)
        center.setPlaybackAllowed(true)
        await Task.yield()
        XCTAssertEqual(center.current?.sourceID, pusher)
    }

    func testRegistryResolvesOptionalCompactByRecentOpenThenOrder() {
        var timerEligible = true
        let registry = CardRegistry(
            registrations: [
                registration(timer, order: 0, eligible: { timerEligible }),
                registration(pusher, order: 1, eligible: { true }),
            ],
            enabledIDs: [timer, pusher],
            lastOpenedAt: [pusher: Date(timeIntervalSince1970: 10)]
        )
        XCTAssertEqual(registry.compactCard?.id, pusher)
        timerEligible = false
        XCTAssertEqual(registry.compactCard?.id, pusher)
    }

    func testCoordinatorUsesRestingWhenNoCardProvidesCompact() {
        let registry = CardRegistry(registrations: [registrationWithoutCompact(timer)])
        let coordinator = IslandCoordinator(registry: registry)
        XCTAssertEqual(coordinator.surfaceDescription, .resting(featureID: timer))
    }

    private func prompt(_ index: Int, source: FeatureID) -> FunctionCardPrompt {
        FunctionCardPrompt(
            token: String(index),
            sourceID: source,
            systemImage: "circle",
            moduleName: source.rawValue,
            summary: "item \(index)"
        )
    }

    private func registration(
        _ id: FeatureID,
        order: Int,
        eligible: @escaping () -> Bool
    ) -> FunctionCardRegistration {
        FunctionCardRegistration(
            id: id,
            name: id.rawValue,
            systemImage: "circle",
            defaultOrder: order,
            metrics: metrics,
            isCompactEligible: eligible,
            makeCompactLeadingView: { AnyView(EmptyView()) },
            makeCompactTrailingView: { AnyView(EmptyView()) },
            makeExpandedView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) }
        )
    }

    private func registrationWithoutCompact(_ id: FeatureID) -> FunctionCardRegistration {
        FunctionCardRegistration(
            id: id,
            name: id.rawValue,
            systemImage: "circle",
            defaultOrder: 0,
            metrics: metrics,
            makeExpandedView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) }
        )
    }

    private var metrics: FunctionCardMetrics {
        FunctionCardMetrics(
            compactWidth: 100,
            compactHeight: 32,
            compactLeadingWidth: 40,
            compactTrailingWidth: 40,
            expandedWidth: 500,
            expandedHeight: 300
        )
    }
}
