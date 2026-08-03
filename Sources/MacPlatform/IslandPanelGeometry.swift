import CoreGraphics
import Foundation

enum IslandPanelAnimation {
    static func duration(
        requested: Bool,
        isExpanded: Bool,
        reduceMotion: Bool,
        panelIsVisible: Bool
    ) -> TimeInterval? {
        guard requested, panelIsVisible, !reduceMotion else { return nil }
        return isExpanded ? 0.22 : 0.18
    }
}

public enum IslandPanelGeometry {
    public static func frame(
        requestedSize: CGSize,
        screenFrame: CGRect,
        safeTopInset: CGFloat,
        margin: CGFloat = 16
    ) -> CGRect {
        let availableWidth = max(1, screenFrame.width - margin * 2)
        let availableHeight = max(1, screenFrame.height - max(0, safeTopInset) - margin * 2)
        let size = CGSize(
            width: min(requestedSize.width, availableWidth),
            height: min(requestedSize.height, availableHeight)
        )
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - margin - size.height,
            width: size.width,
            height: size.height
        )
    }
}
