import CoreGraphics
import Observation
import SwiftUI

@MainActor
@Observable
public final class IslandDisplayContext {
    public private(set) var physicalNotchSize: CGSize?
    public private(set) var compactSurfaceSize: CGSize
    public private(set) var expandedSurfaceSize: CGSize
    public private(set) var expansionTarget: CGFloat
    public private(set) var presentationSurfaceSize: CGSize
    public private(set) var isExpandedContentInteractive: Bool

    public init(
        physicalNotchSize: CGSize? = nil,
        compactSurfaceSize: CGSize = .zero,
        expandedSurfaceSize: CGSize = .zero,
        expansionTarget: CGFloat = 0,
        presentationSurfaceSize: CGSize = .zero,
        isExpandedContentInteractive: Bool = false
    ) {
        self.compactSurfaceSize = Self.normalizedSize(compactSurfaceSize)
        self.expandedSurfaceSize = Self.normalizedSize(expandedSurfaceSize)
        self.expansionTarget = expansionTarget < 0.5 ? 0 : 1
        self.presentationSurfaceSize = Self.normalizedSize(presentationSurfaceSize)
        self.isExpandedContentInteractive = isExpandedContentInteractive
        updatePhysicalNotchSize(physicalNotchSize)
    }

    public func updateLayout(
        physicalNotchSize: CGSize?,
        compactSurfaceSize: CGSize,
        expandedSurfaceSize: CGSize
    ) {
        updatePhysicalNotchSize(physicalNotchSize)
        self.compactSurfaceSize = Self.normalizedSize(compactSurfaceSize)
        self.expandedSurfaceSize = Self.normalizedSize(expandedSurfaceSize)
    }

    public func setExpansionTarget(_ target: CGFloat) {
        expansionTarget = target < 0.5 ? 0 : 1
    }

    public func updatePresentationSurfaceSize(_ size: CGSize) {
        presentationSurfaceSize = Self.normalizedSize(size)
    }

    public func setExpandedContentInteractive(_ expanded: Bool) {
        isExpandedContentInteractive = expanded
    }

    public func updatePhysicalNotchSize(_ size: CGSize?) {
        guard let size, size.width > 0, size.height > 0 else {
            physicalNotchSize = nil
            return
        }
        physicalNotchSize = CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private static func normalizedSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(0, size.width), height: max(0, size.height))
    }
}

enum IslandCompactLayout {
    static let horizontalPadding: CGFloat = 10

    static func sideReservation(leadingWidth: CGFloat, trailingWidth: CGFloat) -> CGFloat {
        max(0, max(leadingWidth, trailingWidth))
    }

    static func notchMidX(
        leadingWidth: CGFloat,
        trailingWidth: CGFloat,
        physicalNotchWidth: CGFloat,
        horizontalPadding: CGFloat
    ) -> CGFloat {
        max(0, horizontalPadding)
            + sideReservation(leadingWidth: leadingWidth, trailingWidth: trailingWidth)
            + max(0, physicalNotchWidth) / 2
    }

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
        let side = sideReservation(leadingWidth: leadingWidth, trailingWidth: trailingWidth)
        return ceil(max(baseWidth, side * 2 + physicalNotchWidth + max(0, horizontalPadding) * 2))
    }
}

enum IslandExpandedLayout {
    static let contentInsets = EdgeInsets(
        top: 16,
        leading: 28,
        bottom: 28,
        trailing: 28
    )

    static func contentSize(surfaceSize: CGSize) -> CGSize {
        CGSize(
            width: max(0, surfaceSize.width - contentInsets.leading - contentInsets.trailing),
            height: max(0, surfaceSize.height - contentInsets.top - contentInsets.bottom)
        )
    }
}

enum IslandSurfaceLayout {
    static func size(
        compact: CGSize,
        expanded: CGSize,
        expansion: CGFloat
    ) -> CGSize {
        let progress = min(1, max(0, expansion))
        return CGSize(
            width: compact.width + (expanded.width - compact.width) * progress,
            height: compact.height + (expanded.height - compact.height) * progress
        )
    }
}

enum IslandSurfaceMetrics {
    static let compact = (top: CGFloat(6), bottom: CGFloat(14))
    static let expanded = (top: CGFloat(19), bottom: CGFloat(24))

    static func cornerRadii(expansion: CGFloat) -> (top: CGFloat, bottom: CGFloat) {
        let progress = min(1, max(0, expansion))
        return (
            top: compact.top + (expanded.top - compact.top) * progress,
            bottom: compact.bottom + (expanded.bottom - compact.bottom) * progress
        )
    }
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
