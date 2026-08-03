import Foundation
import Observation
import PeekerCore

@MainActor
@Observable
public final class IslandCoordinator {
    public var presentation = IslandPresentationState()
    public let registry: CardRegistry
    public private(set) var isPointerInside = false
    @ObservationIgnored private var collapseTask: Task<Void, Never>?

    public init(registry: CardRegistry) {
        self.registry = registry
    }

    deinit {
        collapseTask?.cancel()
    }

    public var isExpanded: Bool {
        if case .compact = presentation.base { return false }
        return true
    }

    public func pointerEntered() {
        isPointerInside = true
        collapseTask?.cancel()
        presentation.pointerEntered(featureID: registry.selectedID)
    }

    public func pointerExited() {
        isPointerInside = false
        scheduleCollapseIfAllowed()
    }

    private func scheduleCollapseIfAllowed() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.presentation.pointerExited()
        }
    }

    public func togglePin() {
        presentation.togglePin()
    }

    public func escape(pointerIsInside: Bool) {
        presentation.escape(pointerIsInside: pointerIsInside)
    }

    public func select(_ id: FeatureID) {
        registry.select(id)
        presentation.select(featureID: id)
    }

    public func setPopoverPresented(_ presented: Bool) {
        presentation.setPopoverPresented(presented)
        if !presented, !isPointerInside { scheduleCollapseIfAllowed() }
    }

    public func setDragging(_ dragging: Bool) {
        presentation.blockers.isDragging = dragging
        if !dragging, !isPointerInside { scheduleCollapseIfAllowed() }
    }

    public func setEditingText(_ editing: Bool) {
        presentation.blockers.isEditingText = editing
        if !editing, !isPointerInside { scheduleCollapseIfAllowed() }
    }
}
