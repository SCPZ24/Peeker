import CoreGraphics

public enum SettingsWindowGeometry {
    public static func frame(windowSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let desiredOrigin = CGPoint(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.minY + visibleFrame.height * 0.40 - windowSize.height / 2
        )

        return CGRect(
            origin: CGPoint(
                x: clampedOrigin(
                    desiredOrigin.x,
                    extent: windowSize.width,
                    range: visibleFrame.minX...visibleFrame.maxX
                ),
                y: clampedOrigin(
                    desiredOrigin.y,
                    extent: windowSize.height,
                    range: visibleFrame.minY...visibleFrame.maxY
                )
            ),
            size: windowSize
        )
    }

    private static func clampedOrigin(
        _ desired: CGFloat,
        extent: CGFloat,
        range: ClosedRange<CGFloat>
    ) -> CGFloat {
        let maximum = range.upperBound - extent
        guard maximum >= range.lowerBound else { return range.lowerBound }
        return min(max(desired, range.lowerBound), maximum)
    }
}
