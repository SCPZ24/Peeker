import XCTest
import SwiftUI
import PeekerCore
@testable import FunctionCardKit

final class IslandStateMachineTests: XCTestCase {
    private let timer = FeatureID(rawValue: "timer")

    func testHoverPinAndEscapeTransitions() {
        var state = IslandPresentationState()
        state.pointerEntered(featureID: timer)
        XCTAssertEqual(state.base, .hoverExpanded(featureID: timer))

        state.togglePin()
        XCTAssertEqual(state.base, .pinnedExpanded(featureID: timer))

        state.escape(pointerIsInside: false)
        XCTAssertEqual(state.base, .compact)
    }

    func testBlockersPreventAutomaticCollapse() {
        var state = IslandPresentationState()
        state.pointerEntered(featureID: timer)
        state.blockers.isDragging = true
        state.pointerExited()

        XCTAssertFalse(state.canAutomaticallyCollapse)
        XCTAssertEqual(state.base, .hoverExpanded(featureID: timer))
    }

    func testClosingPopoverRestoresPinnedState() {
        var state = IslandPresentationState()
        state.pointerEntered(featureID: timer)
        state.togglePin()
        state.setPopoverPresented(true)
        state.setPopoverPresented(false)

        XCTAssertEqual(state.base, .pinnedExpanded(featureID: timer))
    }

    @MainActor
    func testRegistryPreventsDisablingLastCardAndFallsBackFromDisabledSelection() throws {
        let pusher = FeatureID(rawValue: "pusher")
        let registrations = [makeRegistration(timer, order: 0), makeRegistration(pusher, order: 1)]
        let registry = CardRegistry(
            registrations: registrations,
            enabledIDs: [timer, pusher],
            recentID: pusher
        )

        try registry.setEnabled(pusher, enabled: false)
        XCTAssertEqual(registry.selectedID, timer)
        XCTAssertThrowsError(try registry.setEnabled(timer, enabled: false))
    }

    @MainActor
    func testClearingPopoverOutsideIslandSchedulesCollapse() async {
        let registry = CardRegistry(registrations: [makeRegistration(timer, order: 0)])
        let coordinator = IslandCoordinator(registry: registry)
        coordinator.pointerEntered()
        coordinator.setPopoverPresented(true)
        coordinator.pointerExited()
        coordinator.setPopoverPresented(false)

        try? await Task.sleep(for: .milliseconds(400))

        XCTAssertEqual(coordinator.presentation.base, .compact)
    }

    @MainActor
    private func makeRegistration(_ id: FeatureID, order: Int) -> FunctionCardRegistration {
        FunctionCardRegistration(
            id: id,
            name: id.rawValue,
            systemImage: "square",
            defaultOrder: order,
            metrics: FunctionCardMetrics(
                compactWidth: 140,
                compactHeight: 38,
                compactLeadingWidth: 50,
                compactTrailingWidth: 50,
                expandedWidth: 600,
                expandedHeight: 400
            ),
            makeCompactLeadingView: { AnyView(EmptyView()) },
            makeCompactTrailingView: { AnyView(EmptyView()) },
            makeExpandedView: { AnyView(EmptyView()) },
            makeSettingsView: { AnyView(EmptyView()) }
        )
    }
}
