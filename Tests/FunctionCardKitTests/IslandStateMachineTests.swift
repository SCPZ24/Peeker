import Observation
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

    @MainActor
    func testEscapeOutsideWhileCompactDoesNotPublishPresentationChange() async {
        let coordinator = makeCoordinator()
        let unexpectedChange = expectation(description: "compact escape must not publish")
        unexpectedChange.isInverted = true
        withObservationTracking {
            _ = coordinator.presentation.base
        } onChange: {
            unexpectedChange.fulfill()
        }

        coordinator.escape(pointerIsInside: false)

        await fulfillment(of: [unexpectedChange], timeout: 0.05)
        XCTAssertEqual(coordinator.presentation.base, .compact)
    }

    @MainActor
    func testDelayedPointerExitWhileCompactDoesNotPublishPresentationChange() async {
        let coordinator = makeCoordinator()
        let unexpectedChange = expectation(description: "delayed compact exit must not publish")
        unexpectedChange.isInverted = true
        withObservationTracking {
            _ = coordinator.presentation.base
        } onChange: {
            unexpectedChange.fulfill()
        }

        coordinator.pointerExited()

        await fulfillment(of: [unexpectedChange], timeout: 0.45)
        XCTAssertEqual(coordinator.presentation.base, .compact)
    }

    @MainActor
    func testRealEscapeFromExpandedPublishesCompactTransition() async {
        let coordinator = makeCoordinator()
        coordinator.pointerEntered()
        let changed = expectation(description: "expanded escape publishes compact state")
        withObservationTracking {
            _ = coordinator.presentation.base
        } onChange: {
            changed.fulfill()
        }

        coordinator.escape(pointerIsInside: false)

        await fulfillment(of: [changed], timeout: 0.1)
        XCTAssertEqual(coordinator.presentation.base, .compact)
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
    func testRegistryDefaultsToEveryRegistrationInDefaultOrder() {
        let pusher = FeatureID(rawValue: "pusher")
        let registry = CardRegistry(
            registrations: [makeRegistration(pusher, order: 1), makeRegistration(timer, order: 0)]
        )

        XCTAssertEqual(registry.enabledIDs, [timer, pusher])
        XCTAssertEqual(registry.selectedID, timer)
    }

    @MainActor
    func testRegistryFiltersUnknownStoredIDsAndFallsBackFromUnknownRecentID() {
        let unknown = FeatureID(rawValue: "removed")
        let registry = CardRegistry(
            registrations: [makeRegistration(timer, order: 0)],
            enabledIDs: [unknown, timer],
            recentID: unknown
        )

        XCTAssertEqual(registry.enabledIDs, [timer])
        XCTAssertEqual(registry.selectedID, timer)
    }

    @MainActor
    func testRegistrationCanPreserveASettingsSpecificIcon() {
        let registration = FunctionCardRegistration(
            id: timer,
            name: "Timer",
            systemImage: "timer.circle.fill",
            settingsSystemImage: "timer",
            defaultOrder: 0,
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

        XCTAssertEqual(registration.systemImage, "timer.circle.fill")
        XCTAssertEqual(registration.settingsSystemImage, "timer")
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
    private func makeCoordinator() -> IslandCoordinator {
        IslandCoordinator(registry: CardRegistry(registrations: [makeRegistration(timer, order: 0)]))
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
