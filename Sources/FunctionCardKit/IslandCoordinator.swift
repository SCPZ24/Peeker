import Foundation
import Observation
import PeekerCore

public enum IslandSurfaceDescription: Equatable, Sendable {
    case resting(featureID: FeatureID)
    case compact(featureID: FeatureID)
    case prompt(FunctionCardPrompt)
    case expanded(featureID: FeatureID)
}

@MainActor
@Observable
public final class IslandCoordinator {
    public var presentation = IslandPresentationState()
    public let registry: CardRegistry
    public let promptCenter: PromptCenter
    public private(set) var isPointerInside = false
    public private(set) var hoverExpansionDelaySeconds: Double
    @ObservationIgnored private var pendingExpansionTask: Task<Void, Never>?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?

    public init(
        registry: CardRegistry,
        promptCenter: PromptCenter = PromptCenter(),
        hoverExpansionDelaySeconds: Double = 0
    ) {
        self.registry = registry
        self.promptCenter = promptCenter
        self.hoverExpansionDelaySeconds = Self.normalizedHoverExpansionDelay(hoverExpansionDelaySeconds)
        presentation = IslandPresentationState(base: registry.compactCard == nil ? .resting : .compact)
        promptCenter.setCurrentChangedHandler { [weak self] prompt in
            guard let self, !self.isExpanded else { return }
            self.presentation = IslandPresentationState(base: prompt == nil ? self.resolvedBase : .prompt)
        }
    }

    deinit {
        pendingExpansionTask?.cancel()
        collapseTask?.cancel()
    }

    public var isExpanded: Bool {
        switch presentation.base {
        case .hoverExpanded, .pinnedExpanded: true
        case .resting, .compact, .prompt: false
        }
    }

    public var surfaceDescription: IslandSurfaceDescription {
        switch presentation.base {
        case let .hoverExpanded(featureID), let .pinnedExpanded(featureID):
            return .expanded(featureID: featureID)
        case .resting, .compact, .prompt:
            if let prompt = promptCenter.current { return .prompt(prompt) }
            if let card = registry.compactCard { return .compact(featureID: card.id) }
            return .resting(featureID: registry.selectedID)
        }
    }

    public func pointerEntered() {
        isPointerInside = true
        collapseTask?.cancel()
        pendingExpansionTask?.cancel()

        switch surfaceDescription {
        case .prompt, .expanded:
            expandCurrentSurface()
        case .compact, .resting:
            guard hoverExpansionDelaySeconds > 0 else {
                expandCurrentSurface()
                return
            }
            let delay = hoverExpansionDelaySeconds
            pendingExpansionTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self, self.isPointerInside else { return }
                self.pendingExpansionTask = nil
                self.expandCurrentSurface()
            }
        }
    }

    public func pointerExited() {
        isPointerInside = false
        pendingExpansionTask?.cancel()
        pendingExpansionTask = nil
        scheduleCollapseIfAllowed()
    }

    public func setHoverExpansionDelay(_ seconds: Double) {
        hoverExpansionDelaySeconds = Self.normalizedHoverExpansionDelay(seconds)
        pendingExpansionTask?.cancel()
        pendingExpansionTask = nil
    }

    private func scheduleCollapseIfAllowed() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            let changed = self.mutatePresentation { $0.pointerExited() }
            if changed, !self.isExpanded { self.finishExpansion() }
        }
    }

    public func togglePin() {
        mutatePresentation { $0.togglePin() }
    }

    public func escape(pointerIsInside: Bool) {
        let changed = mutatePresentation { $0.escape(pointerIsInside: pointerIsInside) }
        if changed, !isExpanded { finishExpansion() }
    }

    public func select(_ id: FeatureID) {
        registry.select(id)
        mutatePresentation { $0.select(featureID: id) }
    }

    public func publishPrompt(_ prompt: FunctionCardPrompt) {
        guard registry.enabledIDs.contains(prompt.sourceID) else { return }
        _ = promptCenter.publish(prompt)
    }

    public func revokePrompt(token: String) {
        promptCenter.revoke(token: token)
    }

    public func clearPrompts(sourceID: FeatureID) {
        promptCenter.clear(sourceID: sourceID)
    }

    public func setPopoverPresented(_ presented: Bool) {
        mutatePresentation { $0.setPopoverPresented(presented) }
        if !presented, !isPointerInside { scheduleCollapseIfAllowed() }
    }

    public func setDragging(_ dragging: Bool) {
        mutatePresentation { $0.blockers.isDragging = dragging }
        if !dragging, !isPointerInside { scheduleCollapseIfAllowed() }
    }

    public func setEditingText(_ editing: Bool) {
        mutatePresentation { $0.blockers.isEditingText = editing }
        if !editing, !isPointerInside { scheduleCollapseIfAllowed() }
    }

    private var resolvedBase: IslandBaseState {
        registry.compactCard == nil ? .resting : .compact
    }

    private func expandCurrentSurface() {
        let featureID: FeatureID
        switch surfaceDescription {
        case let .prompt(prompt):
            promptCenter.setPlaybackAllowed(false)
            _ = promptCenter.consumeCurrent()
            featureID = prompt.sourceID
        case let .compact(id), let .resting(id), let .expanded(id):
            featureID = id
        }
        registry.select(featureID)
        promptCenter.setPlaybackAllowed(false)
        mutatePresentation { $0.pointerEntered(featureID: featureID) }
    }

    private static func normalizedHoverExpansionDelay(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (min(2, max(0, value)) * 10).rounded() / 10
    }

    private func finishExpansion() {
        presentation = IslandPresentationState(base: resolvedBase)
        promptCenter.setPlaybackAllowed(true, after: .milliseconds(1_500))
    }

    @discardableResult
    private func mutatePresentation(
        _ mutation: (inout IslandPresentationState) -> Void
    ) -> Bool {
        var next = presentation
        mutation(&next)
        guard next != presentation else { return false }
        presentation = next
        return true
    }
}
