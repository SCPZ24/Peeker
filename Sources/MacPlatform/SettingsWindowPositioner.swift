import AppKit

@MainActor
public final class SettingsWindowPositioner: NSObject {
    public typealias VisibleFrameProvider = @MainActor (NSWindow) -> CGRect?

    private weak var window: NSWindow?
    private let visibleFrameProvider: VisibleFrameProvider

    public override init() {
        visibleFrameProvider = Self.defaultVisibleFrame
        super.init()
    }

    public init(visibleFrameProvider: @escaping VisibleFrameProvider) {
        self.visibleFrameProvider = visibleFrameProvider
        super.init()
    }

    public func register(_ window: NSWindow) {
        if let previousWindow = self.window {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didBecomeKeyNotification,
                object: previousWindow
            )
        }
        self.window = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        position(window)
    }

    public func repositionAndBringForward() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        position(window)
    }

    private func position(_ window: NSWindow) {
        guard let visibleFrame = visibleFrameProvider(window) else { return }
        window.setFrame(
            SettingsWindowGeometry.frame(
                windowSize: window.frame.size,
                visibleFrame: visibleFrame
            ),
            display: true
        )
    }

    @objc
    private func windowDidBecomeKey(_ notification: Notification) {
        guard let notifiedWindow = notification.object as? NSWindow,
              notifiedWindow === window else { return }
        DispatchQueue.main.async { [weak self, weak notifiedWindow] in
            guard let self, let notifiedWindow else { return }
            self.position(notifiedWindow)
        }
    }

    private static func defaultVisibleFrame(for window: NSWindow) -> CGRect? {
        window.screen?.visibleFrame
            ?? screenContainingMouse()?.visibleFrame
            ?? NSScreen.main?.visibleFrame
    }

    private static func screenContainingMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(location, screen.frame, false)
        }
    }
}
