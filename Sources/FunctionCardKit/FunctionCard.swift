import CoreGraphics
import Observation
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
@Observable
public final class FunctionCardLayoutState {
    public var currentExpandedSize: CGSize

    public init(currentExpandedSize: CGSize) {
        self.currentExpandedSize = currentExpandedSize
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
    public let iconDescriptor: FunctionCardIconDescriptor
    public let settingsIconDescriptor: FunctionCardIconDescriptor
    public let iconManifest: FunctionCardIconManifest?
    public let defaultOrder: Int
    public let introducedConfigurationVersion: Int
    public let defaultEnabled: Bool
    public let metrics: FunctionCardMetrics
    public let layoutState: FunctionCardLayoutState
    public let compactProvider: FunctionCardCompactProvider?
    public let makeExpandedView: () -> AnyView
    public let makeSettingsView: () -> AnyView

    public var systemImage: String {
        guard case let .systemSymbol(name) = iconDescriptor else { return "square" }
        return name
    }

    public var settingsSystemImage: String {
        guard case let .systemSymbol(name) = settingsIconDescriptor else { return "square" }
        return name
    }

    public init(
        id: FeatureID,
        name: String,
        iconDescriptor: FunctionCardIconDescriptor,
        settingsIconDescriptor: FunctionCardIconDescriptor? = nil,
        iconManifest: FunctionCardIconManifest? = nil,
        defaultOrder: Int,
        introducedConfigurationVersion: Int = 1,
        defaultEnabled: Bool = true,
        metrics: FunctionCardMetrics,
        layoutState: FunctionCardLayoutState? = nil,
        isCompactEligible: @escaping () -> Bool = { true },
        makeCompactLeadingView: (() -> AnyView)? = nil,
        makeCompactTrailingView: (() -> AnyView)? = nil,
        makeExpandedView: @escaping () -> AnyView,
        makeSettingsView: @escaping () -> AnyView
    ) {
        self.id = id
        self.name = name
        self.iconDescriptor = iconDescriptor
        self.settingsIconDescriptor = settingsIconDescriptor ?? iconDescriptor
        self.iconManifest = iconManifest
        self.defaultOrder = defaultOrder
        self.introducedConfigurationVersion = introducedConfigurationVersion
        self.defaultEnabled = defaultEnabled
        self.metrics = metrics
        self.layoutState = layoutState ?? FunctionCardLayoutState(
            currentExpandedSize: CGSize(width: metrics.expandedWidth, height: metrics.expandedHeight)
        )
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

    public init(
        id: FeatureID,
        name: String,
        systemImage: String,
        settingsSystemImage: String? = nil,
        defaultOrder: Int,
        introducedConfigurationVersion: Int = 1,
        defaultEnabled: Bool = true,
        metrics: FunctionCardMetrics,
        layoutState: FunctionCardLayoutState? = nil,
        isCompactEligible: @escaping () -> Bool = { true },
        makeCompactLeadingView: (() -> AnyView)? = nil,
        makeCompactTrailingView: (() -> AnyView)? = nil,
        makeExpandedView: @escaping () -> AnyView,
        makeSettingsView: @escaping () -> AnyView
    ) {
        self.init(
            id: id,
            name: name,
            iconDescriptor: .systemSymbol(name: systemImage),
            settingsIconDescriptor: .systemSymbol(name: settingsSystemImage ?? systemImage),
            defaultOrder: defaultOrder,
            introducedConfigurationVersion: introducedConfigurationVersion,
            defaultEnabled: defaultEnabled,
            metrics: metrics,
            layoutState: layoutState,
            isCompactEligible: isCompactEligible,
            makeCompactLeadingView: makeCompactLeadingView,
            makeCompactTrailingView: makeCompactTrailingView,
            makeExpandedView: makeExpandedView,
            makeSettingsView: makeSettingsView
        )
    }
}
