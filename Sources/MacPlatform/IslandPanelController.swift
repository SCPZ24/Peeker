import AppKit
import Observation
import SwiftUI
import FunctionCardKit

@MainActor
public final class IslandPanelController {
    private let panel: PeekerPanel
    private let hostingController: NSHostingController<AnyView>
    private let coordinator: IslandCoordinator
    private let screens: ScreenTopologyService
    private var targetScreenID: String?
    private let didFallbackScreen: (String) -> Void
    nonisolated(unsafe) private var localMonitor: Any?
    nonisolated(unsafe) private var globalMonitor: Any?
    nonisolated(unsafe) private var screenObserver: NSObjectProtocol?

    public init(
        coordinator: IslandCoordinator,
        rootView: AnyView,
        screens: ScreenTopologyService,
        targetScreenID: String?,
        didFallbackScreen: @escaping (String) -> Void
    ) {
        self.coordinator = coordinator
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
                self.coordinator.escape(pointerIsInside: self.panel.frame.contains(NSEvent.mouseLocation))
                return nil
            }
            if event.window !== self.panel, !self.panel.frame.contains(NSEvent.mouseLocation) {
                self.coordinator.escape(pointerIsInside: false)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
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
        let requested = coordinator.isExpanded
            ? CGSize(width: selected.metrics.expandedWidth, height: selected.metrics.expandedHeight)
            : CGSize(width: selected.metrics.compactWidth, height: selected.metrics.compactHeight)

        let requestedScreen = screens.screen(withStableID: targetScreenID)
        let screen = requestedScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        if requestedScreen == nil {
            let fallbackID = ScreenTopologyService.stableID(for: screen)
            targetScreenID = fallbackID
            didFallbackScreen(fallbackID)
        }
        let frame = IslandPanelGeometry.frame(
            requestedSize: requested,
            screenFrame: screen.frame,
            safeTopInset: screen.safeAreaInsets.top,
            margin: 16
        )
        panel.setFrame(frame, display: true, animate: animated)
    }
}

private final class PeekerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
