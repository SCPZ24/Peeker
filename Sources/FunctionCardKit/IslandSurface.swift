import CoreGraphics
import Observation
import SwiftUI

@MainActor
@Observable
public final class IslandDisplayContext {
    public private(set) var physicalNotchSize: CGSize?

    public init(physicalNotchSize: CGSize? = nil) {
        updatePhysicalNotchSize(physicalNotchSize)
    }

    public func updatePhysicalNotchSize(_ size: CGSize?) {
        guard let size, size.width > 0, size.height > 0 else {
            physicalNotchSize = nil
            return
        }
        physicalNotchSize = CGSize(width: ceil(size.width), height: ceil(size.height))
    }
}

enum IslandCompactLayout {
    static func width(
        baseWidth: CGFloat,
        leadingWidth: CGFloat,
        trailingWidth: CGFloat,
        physicalNotchWidth: CGFloat?,
        horizontalPadding: CGFloat
    ) -> CGFloat {
        guard let physicalNotchWidth, physicalNotchWidth > 0 else {
            return max(1, baseWidth)
        }
        return ceil(
            max(
                baseWidth,
                max(0, leadingWidth)
                    + physicalNotchWidth
                    + max(0, trailingWidth)
                    + max(0, horizontalPadding) * 2
            )
        )
    }
}

enum IslandSurfaceMetrics {
    static let compact = (top: CGFloat(6), bottom: CGFloat(14))
    static let expanded = (top: CGFloat(19), bottom: CGFloat(24))
}

struct TopAttachedRoundedRectangle: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(max(0, topCornerRadius), min(rect.width / 2, rect.height))
        let bottom = min(
            max(0, bottomCornerRadius),
            max(0, rect.height - top),
            max(0, (rect.width - top * 2) / 2)
        )
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.minY + top),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.closeSubpath()

        return path
    }
}
