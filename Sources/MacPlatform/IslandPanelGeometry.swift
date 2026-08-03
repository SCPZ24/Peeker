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
    public static func physicalNotchSize(
        screenWidth: CGFloat,
        safeTopInset: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?,
        notchBleed: CGFloat = 4
    ) -> CGSize? {
        guard safeTopInset > 0,
              let auxiliaryTopLeftWidth,
              let auxiliaryTopRightWidth
        else { return nil }
        let width = max(
            0,
            screenWidth
                - max(0, auxiliaryTopLeftWidth)
                - max(0, auxiliaryTopRightWidth)
                + max(0, notchBleed)
        )
        guard width > 0 else { return nil }
        return CGSize(width: ceil(width), height: ceil(safeTopInset))
    }

    public static func frame(
        requestedSize: CGSize,
        screenFrame: CGRect,
        safeTopInset: CGFloat,
        auxiliaryTopLeftWidth: CGFloat?,
        auxiliaryTopRightWidth: CGFloat?,
        horizontalMargin: CGFloat = 16,
        bottomMargin: CGFloat = 16,
        notchBleed: CGFloat = 4
    ) -> CGRect {
        let horizontalMargin = max(0, horizontalMargin)
        let bottomMargin = max(0, bottomMargin)
        let safeTopInset = max(0, safeTopInset)
        let availableWidth = max(1, screenFrame.width - horizontalMargin * 2)
        let availableHeight = max(1, screenFrame.height - bottomMargin)
        let physicalNotchSize = physicalNotchSize(
            screenWidth: screenFrame.width,
            safeTopInset: safeTopInset,
            auxiliaryTopLeftWidth: auxiliaryTopLeftWidth,
            auxiliaryTopRightWidth: auxiliaryTopRightWidth,
            notchBleed: notchBleed
        )
        let size = CGSize(
            width: min(ceil(max(requestedSize.width, physicalNotchSize?.width ?? 0)), availableWidth),
            height: min(ceil(max(requestedSize.height, safeTopInset)), availableHeight)
        )
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
