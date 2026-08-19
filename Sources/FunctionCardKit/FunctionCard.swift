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
                horizontalPadding: IslandCompactLayout.horizontalPadding
            ),
            height: max(compactHeight, physicalNotchSize?.height ?? 0)
        )
    }
}

@MainActor
public struct FunctionCardCompactProvider {
    public let isEligible: () -> Bool
    public let makeLeadingView: () -> AnyView
    public let makeTrailingView: () -> AnyView

    public init(
        isEligible: @escaping () -> Bool,
        makeLeadingView: @escaping () -> AnyView,
        makeTrailingView: @escaping () -> AnyView
    ) {
        self.isEligible = isEligible
        self.makeLeadingView = makeLeadingView
        self.makeTrailingView = makeTrailingView
    }
}

@MainActor
public struct FunctionCardRegistration: Identifiable {
    public let id: FeatureID
    public let name: String
    public let systemImage: String
    public let settingsSystemImage: String
    public let defaultOrder: Int
    public let introducedConfigurationVersion: Int
    public let defaultEnabled: Bool
    public let metrics: FunctionCardMetrics
    public let compactProvider: FunctionCardCompactProvider?
    public let makeExpandedView: () -> AnyView
    public let makeSettingsView: () -> AnyView

    public init(
        id: FeatureID,
        name: String,
        systemImage: String,
        settingsSystemImage: String? = nil,
        defaultOrder: Int,
        introducedConfigurationVersion: Int = 1,
        defaultEnabled: Bool = true,
        metrics: FunctionCardMetrics,
        isCompactEligible: @escaping () -> Bool = { true },
        makeCompactLeadingView: (() -> AnyView)? = nil,
        makeCompactTrailingView: (() -> AnyView)? = nil,
        makeExpandedView: @escaping () -> AnyView,
        makeSettingsView: @escaping () -> AnyView
    ) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.settingsSystemImage = settingsSystemImage ?? systemImage
        self.defaultOrder = defaultOrder
        self.introducedConfigurationVersion = introducedConfigurationVersion
        self.defaultEnabled = defaultEnabled
        self.metrics = metrics
        if let makeCompactLeadingView, let makeCompactTrailingView {
            compactProvider = FunctionCardCompactProvider(
                isEligible: isCompactEligible,
                makeLeadingView: makeCompactLeadingView,
                makeTrailingView: makeCompactTrailingView
            )
        } else {
            compactProvider = nil
        }
        self.makeExpandedView = makeExpandedView
        self.makeSettingsView = makeSettingsView
    }
}
