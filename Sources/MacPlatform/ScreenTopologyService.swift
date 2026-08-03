import AppKit
import CoreGraphics
import PeekerCore

@MainActor
public final class ScreenTopologyService: ScreenTopologyProviding {
    public init() {}

    public func availableScreens() async -> [ScreenDescriptor] {
        NSScreen.screens.map { screen in
            let displayID = Self.displayID(for: screen)
            return ScreenDescriptor(
                id: Self.stableID(for: displayID),
                name: screen.localizedName,
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0
            )
        }
    }

    public func currentMainScreenID() async -> String? {
        NSScreen.main.map { Self.stableID(for: Self.displayID(for: $0)) }
    }

    public func screen(withStableID stableID: String?) -> NSScreen? {
        guard let stableID else { return nil }
        return NSScreen.screens.first {
            Self.stableID(for: Self.displayID(for: $0)) == stableID
        }
    }

    public func preferredScreen(savedID: String?) -> NSScreen? {
        if let saved = screen(withStableID: savedID) { return saved }
        return NSScreen.screens.first {
            CGDisplayIsBuiltin(Self.displayID(for: $0)) != 0
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    public static func stableID(for screen: NSScreen) -> String {
        stableID(for: displayID(for: screen))
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private static func stableID(for displayID: CGDirectDisplayID) -> String {
        guard let unmanaged = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return "display-\(displayID)"
        }
        let uuid = unmanaged.takeRetainedValue()
        return (CFUUIDCreateString(nil, uuid) as String?) ?? "display-\(displayID)"
    }
}
