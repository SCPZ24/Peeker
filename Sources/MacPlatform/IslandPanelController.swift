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
            _ = coordinator.presentation.base
            _ = coordinator.registry.selectedID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateFrame(animated: true)
                self?.observeLayout()
            }
        }
    }

    private func updateFrame(animated: Bool) {
        guard let selected = coordinator.registry.selectedCard else { return }
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
        let compactFrame = IslandPanelGeometry.frame(
            requestedSize: selected.metrics.compactSize(physicalNotchSize: physicalNotchSize),
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
        let targetExpanded = coordinator.isExpanded
        let targetFrame = targetExpanded ? expandedFrame : compactFrame
        let generation = transitionState.begin(targetExpanded: targetExpanded)
        let duration = IslandPanelAnimation.duration(
            requested: animated,
            isExpanded: targetExpanded,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            panelIsVisible: panel.isVisible
        )
        guard let duration else {
            displayContext.updateLayout(
                physicalNotchSize: physicalNotchSize,
                compactSurfaceSize: compactFrame.size,
                expandedSurfaceSize: expandedFrame.size
            )
            displayContext.setExpansionTarget(targetExpanded ? 1 : 0)
            displayContext.updatePresentationSurfaceSize(targetFrame.size)
            displayContext.setExpandedContentInteractive(targetExpanded)
            panel.setFrame(targetFrame, display: true, animate: false)
            return
        }

        let hostFrame = IslandPanelGeometry.transitionHostFrame(
            compactFrame: compactFrame,
            expandedFrame: expandedFrame,
            minimumHostSize: panel.isVisible ? panel.frame.size : .zero
        )
        panel.setFrame(hostFrame, display: true, animate: false)
        hostingController.view.layoutSubtreeIfNeeded()
        let screenID = ScreenTopologyService.stableID(for: screen)

        Task { @MainActor [weak self] in
            guard let self,
                  self.transitionState.acceptsCompletion(
                      generation: generation,
                      targetExpanded: targetExpanded
                  ), self.targetScreenID == screenID
            else { return }
            withAnimation(
                .easeInOut(duration: duration),
                completionCriteria: .logicallyComplete
            ) {
                self.displayContext.updateLayout(
                    physicalNotchSize: physicalNotchSize,
                    compactSurfaceSize: compactFrame.size,
                    expandedSurfaceSize: expandedFrame.size
                )
                self.displayContext.setExpansionTarget(targetExpanded ? 1 : 0)
            } completion: { [weak self] in
                Task { @MainActor in
                    self?.finishTransition(
                        generation: generation,
                        targetExpanded: targetExpanded,
                        screenID: screenID,
                        targetFrame: targetFrame
                    )
                }
            }
        }
    }

    private func finishTransition(
        generation: UInt64,
        targetExpanded: Bool,
        screenID: String,
        targetFrame: CGRect
    ) {
        guard transitionState.acceptsCompletion(
            generation: generation,
            targetExpanded: targetExpanded
        ), coordinator.isExpanded == targetExpanded,
           targetScreenID == screenID
        else { return }
        displayContext.updatePresentationSurfaceSize(targetFrame.size)
        displayContext.setExpandedContentInteractive(targetExpanded)
        panel.setFrame(targetFrame, display: true, animate: false)
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
