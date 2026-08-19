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

struct IslandPanelTransitionEnvironment: Equatable {
    let selectedCardID: String
    let screenID: String
    let screenFrame: CGRect
    let safeTopInset: CGFloat
    let auxiliaryTopLeftWidth: CGFloat?
    let auxiliaryTopRightWidth: CGFloat?
}

struct IslandPanelTransitionRequest: Equatable {
    let targetExpanded: Bool
    let environment: IslandPanelTransitionEnvironment
    let compactFrame: CGRect
    let expandedFrame: CGRect
}

struct IslandPanelTransitionState {
    private(set) var generation: UInt64 = 0
    private(set) var targetExpanded = false
    private(set) var request: IslandPanelTransitionRequest?
    private var finishedGeneration: UInt64?

    mutating func begin(request: IslandPanelTransitionRequest) -> UInt64? {
        guard self.request != request else { return nil }
        generation &+= 1
        self.request = request
        targetExpanded = request.targetExpanded
        finishedGeneration = nil
        return generation
    }

    func acceptsCompletion(generation: UInt64, targetExpanded: Bool) -> Bool {
        self.generation == generation && self.targetExpanded == targetExpanded
    }

    mutating func finish(generation: UInt64, targetExpanded: Bool) -> Bool {
        guard acceptsCompletion(generation: generation, targetExpanded: targetExpanded),
              finishedGeneration != generation else { return false }
        finishedGeneration = generation
        return true
    }
}

public enum IslandPanelGeometry {
    public static func restingSize(physicalNotchSize: CGSize?) -> CGSize {
        if let physicalNotchSize {
            return CGSize(width: ceil(physicalNotchSize.width + 32), height: ceil(physicalNotchSize.height))
        }
        return CGSize(width: 220, height: 8)
    }

    public static func transitionHostFrame(
        compactFrame: CGRect,
        expandedFrame: CGRect,
        minimumHostSize: CGSize = .zero
    ) -> CGRect {
        let width = max(compactFrame.width, expandedFrame.width, max(0, minimumHostSize.width))
        let height = max(compactFrame.height, expandedFrame.height, max(0, minimumHostSize.height))
        return CGRect(
            x: expandedFrame.midX - width / 2,
            y: expandedFrame.maxY - height,
            width: width,
            height: height
        )
    }

    public static func surfaceFrame(size: CGSize, within hostFrame: CGRect) -> CGRect {
        CGRect(
            x: hostFrame.midX - size.width / 2,
            y: hostFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

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
