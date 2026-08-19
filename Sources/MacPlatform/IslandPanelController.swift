import AppKit
import Observation
import SwiftUI
import FunctionCardKit

@MainActor
public final class IslandPanelController {
    private let panel: PeekerPanel
    private let hostingController: NSHostingController<AnyView>
    private let coordinator: IslandCoordinator
    private let displayContext: IslandDisplayContext
    private let screens: ScreenTopologyService
    private var targetScreenID: String?
    private let didFallbackScreen: (String) -> Void
    private var transitionState = IslandPanelTransitionState()
    private var transitionTask: Task<Void, Never>?
    nonisolated(unsafe) private var localMonitor: Any?
    nonisolated(unsafe) private var globalMonitor: Any?
    nonisolated(unsafe) private var screenObserver: NSObjectProtocol?

    public init(
        coordinator: IslandCoordinator,
        displayContext: IslandDisplayContext,
        rootView: AnyView,
        screens: ScreenTopologyService,
        targetScreenID: String?,
        didFallbackScreen: @escaping (String) -> Void
    ) {
        self.coordinator = coordinator
        self.displayContext = displayContext
        self.screens = screens
        self.targetScreenID = targetScreenID
        self.didFallbackScreen = didFallbackScreen
        hostingController = NSHostingController(rootView: rootView)
        panel = PeekerPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        installMonitors()
        observeScreenChanges()
        observeLayout()
    }

    deinit {
        transitionTask?.cancel()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    public func show() {
        updateFrame(animated: false)
        panel.orderFrontRegardless()
    }

    public func setTargetScreenID(_ id: String?) {
        targetScreenID = id
        updateFrame(animated: true)
    }

    private func configurePanel() {
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
    }

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                if self.coordinator.presentation.blockers.isPopoverPresented {
                    return event
                }
                self.coordinator.escape(pointerIsInside: self.visibleSurfaceFrame.contains(NSEvent.mouseLocation))
                return nil
            }
            if !self.visibleSurfaceFrame.contains(NSEvent.mouseLocation) {
                self.coordinator.escape(pointerIsInside: false)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.visibleSurfaceFrame.contains(NSEvent.mouseLocation) else { return }
                self.coordinator.escape(pointerIsInside: false)
            }
        }
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateFrame(animated: true) }
        }
    }

    private func observeLayout() {
        withObservationTracking {
            _ = coordinator.surfaceDescription
            _ = coordinator.registry.selectedID
            _ = coordinator.registry.enabledIDs
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateFrame(animated: true)
                self?.observeLayout()
            }
        }
    }

    private func updateFrame(animated: Bool) {
        guard let selected = coordinator.registry.selectedCard else { return }
        let surface = coordinator.surfaceDescription
        let requestedScreen = screens.screen(withStableID: targetScreenID)
        let screen = requestedScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        if requestedScreen == nil {
            let fallbackID = ScreenTopologyService.stableID(for: screen)
            targetScreenID = fallbackID
            didFallbackScreen(fallbackID)
        }
        let auxiliaryTopLeftWidth = screen.auxiliaryTopLeftArea?.width
        let auxiliaryTopRightWidth = screen.auxiliaryTopRightArea?.width
        let physicalNotchSize = IslandPanelGeometry.physicalNotchSize(
            screenWidth: screen.frame.width,
            safeTopInset: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftWidth,
            auxiliaryTopRightWidth: auxiliaryTopRightWidth
        )
        let collapsedSize: CGSize
        switch surface {
        case .resting:
            collapsedSize = IslandPanelGeometry.restingSize(physicalNotchSize: physicalNotchSize)
        case let .compact(featureID):
            collapsedSize = coordinator.registry.registrations.first(where: { $0.id == featureID })?
                .metrics.compactSize(physicalNotchSize: physicalNotchSize)
                ?? IslandPanelGeometry.restingSize(physicalNotchSize: physicalNotchSize)
        case .prompt:
            collapsedSize = CGSize(width: 420, height: 72)
        case .expanded:
            collapsedSize = selected.metrics.compactSize(physicalNotchSize: physicalNotchSize)
        }
        let compactFrame = IslandPanelGeometry.frame(
            requestedSize: collapsedSize,
            screenFrame: screen.frame,
            safeTopInset: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftWidth,
            auxiliaryTopRightWidth: auxiliaryTopRightWidth
        )
        let expandedFrame = IslandPanelGeometry.frame(
            requestedSize: CGSize(
                width: selected.metrics.expandedWidth,
                height: selected.metrics.expandedHeight
            ),
            screenFrame: screen.frame,
            safeTopInset: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: auxiliaryTopLeftWidth,
            auxiliaryTopRightWidth: auxiliaryTopRightWidth
        )
        let transitionEnvironment = makeTransitionEnvironment(
            surface: surface,
            screen: screen
        )
        let targetExpanded = coordinator.isExpanded
        let targetFrame = targetExpanded ? expandedFrame : compactFrame
        let request = IslandPanelTransitionRequest(
            targetExpanded: targetExpanded,
            environment: transitionEnvironment,
            compactFrame: compactFrame,
            expandedFrame: expandedFrame
        )
        guard let generation = transitionState.begin(request: request) else { return }
        let duration = IslandPanelAnimation.duration(
            requested: animated,
            isExpanded: targetExpanded,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            panelIsVisible: panel.isVisible
        )
        guard let duration else {
            transitionTask?.cancel()
            displayContext.updateLayout(
                physicalNotchSize: physicalNotchSize,
                compactSurfaceSize: compactFrame.size,
                expandedSurfaceSize: expandedFrame.size
            )
            displayContext.setExpansionTarget(targetExpanded ? 1 : 0)
            displayContext.updatePresentationSurfaceSize(targetFrame.size)
            _ = transitionState.finish(
                generation: generation,
                targetExpanded: targetExpanded
            )
            panel.setFrame(targetFrame, display: true, animate: false)
            return
        }

        transitionTask?.cancel()
        let hostFrame = IslandPanelGeometry.transitionHostFrame(
            compactFrame: compactFrame,
            expandedFrame: expandedFrame,
            minimumHostSize: panel.isVisible ? panel.frame.size : .zero
        )
        panel.setFrame(hostFrame, display: true, animate: false)
        hostingController.view.layoutSubtreeIfNeeded()

        transitionTask = Task { @MainActor [weak self] in
            guard let self,
                  self.transitionState.acceptsCompletion(
                      generation: generation,
                      targetExpanded: targetExpanded
                  ), self.targetScreenID == transitionEnvironment.screenID
            else { return }
            withAnimation(.easeInOut(duration: duration)) {
                self.displayContext.updateLayout(
                    physicalNotchSize: physicalNotchSize,
                    compactSurfaceSize: compactFrame.size,
                    expandedSurfaceSize: expandedFrame.size
                )
                self.displayContext.setExpansionTarget(targetExpanded ? 1 : 0)
            }
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }
            self.finishTransition(
                generation: generation,
                targetExpanded: targetExpanded,
                environment: transitionEnvironment,
                targetFrame: targetFrame
            )
        }
    }

    private func finishTransition(
        generation: UInt64,
        targetExpanded: Bool,
        environment: IslandPanelTransitionEnvironment,
        targetFrame: CGRect
    ) {
        guard coordinator.registry.selectedCard != nil,
              let screen = screens.screen(withStableID: environment.screenID),
              coordinator.isExpanded == targetExpanded,
              targetScreenID == environment.screenID,
              makeTransitionEnvironment(surface: coordinator.surfaceDescription, screen: screen) == environment,
              transitionState.finish(
                  generation: generation,
                  targetExpanded: targetExpanded
              )
        else { return }
        displayContext.updatePresentationSurfaceSize(targetFrame.size)
        panel.setFrame(targetFrame, display: true, animate: false)
    }

    private func makeTransitionEnvironment(
        surface: IslandSurfaceDescription,
        screen: NSScreen
    ) -> IslandPanelTransitionEnvironment {
        let surfaceID: String
        switch surface {
        case let .resting(id): surfaceID = "resting:\(id.rawValue)"
        case let .compact(id): surfaceID = "compact:\(id.rawValue)"
        case let .prompt(prompt): surfaceID = "prompt:\(prompt.token)"
        case let .expanded(id): surfaceID = "expanded:\(id.rawValue)"
        }
        return IslandPanelTransitionEnvironment(
            selectedCardID: surfaceID,
            screenID: ScreenTopologyService.stableID(for: screen),
            screenFrame: screen.frame,
            safeTopInset: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width
        )
    }

    private var visibleSurfaceFrame: CGRect {
        let size = displayContext.presentationSurfaceSize
        guard size.width > 0, size.height > 0 else { return panel.frame }
        return IslandPanelGeometry.surfaceFrame(size: size, within: panel.frame)
    }
}

private final class PeekerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
