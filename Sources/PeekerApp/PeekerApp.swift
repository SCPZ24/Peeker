import AppKit
import SwiftUI

@main
struct PeekerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { SettingsRootView(runtime: .shared) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var workspaceObservers: [NSObjectProtocol] = []
    private var systemObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppRuntime.shared.start()
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in Task { @MainActor in AppRuntime.shared.handleSleep() } })
        workspaceObservers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in Task { @MainActor in AppRuntime.shared.handleWake() } })

        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemClockDidChange, Notification.Name.NSSystemTimeZoneDidChange] {
            systemObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in AppRuntime.shared.handleClockOrTimeZoneChange() }
            })
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppRuntime.shared.openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppRuntime.shared.stop()
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspace.removeObserver)
        systemObservers.forEach(NotificationCenter.default.removeObserver)
    }
}
