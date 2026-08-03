import CoreGraphics
import SwiftUI
import PeekerCore

public struct FunctionCardMetrics: Equatable, Sendable {
    public let compactWidth: CGFloat
    public let compactHeight: CGFloat
    public let compactLeadingWidth: CGFloat
    public let compactTrailingWidth: CGFloat
    public let expandedWidth: CGFloat
    public let expandedHeight: CGFloat

    public init(
        compactWidth: CGFloat,
        compactHeight: CGFloat,
        compactLeadingWidth: CGFloat,
        compactTrailingWidth: CGFloat,
        expandedWidth: CGFloat,
        expandedHeight: CGFloat
    ) {
        self.compactWidth = compactWidth
        self.compactHeight = compactHeight
        self.compactLeadingWidth = compactLeadingWidth
        self.compactTrailingWidth = compactTrailingWidth
        self.expandedWidth = expandedWidth
        self.expandedHeight = expandedHeight
    }

    public func compactSize(physicalNotchSize: CGSize?) -> CGSize {
        CGSize(
            width: IslandCompactLayout.width(
                baseWidth: compactWidth,
                leadingWidth: compactLeadingWidth,
                trailingWidth: compactTrailingWidth,
                physicalNotchWidth: physicalNotchSize?.width,
                horizontalPadding: 14
            ),
            height: max(compactHeight, physicalNotchSize?.height ?? 0)
        )
    }
}

@MainActor
public struct FunctionCardRegistration: Identifiable {
    public let id: FeatureID
    public let name: String
    public let systemImage: String
    public let defaultOrder: Int
    public let metrics: FunctionCardMetrics
    public let makeCompactLeadingView: () -> AnyView
    public let makeCompactTrailingView: () -> AnyView
    public let makeExpandedView: () -> AnyView
    public let makeSettingsView: () -> AnyView

    public init(
        id: FeatureID,
        name: String,
        systemImage: String,
        defaultOrder: Int,
        metrics: FunctionCardMetrics,
        makeCompactLeadingView: @escaping () -> AnyView,
        makeCompactTrailingView: @escaping () -> AnyView,
        makeExpandedView: @escaping () -> AnyView,
        makeSettingsView: @escaping () -> AnyView
    ) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.defaultOrder = defaultOrder
        self.metrics = metrics
        self.makeCompactLeadingView = makeCompactLeadingView
        self.makeCompactTrailingView = makeCompactTrailingView
        self.makeExpandedView = makeExpandedView
        self.makeSettingsView = makeSettingsView
    }
}
