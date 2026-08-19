import CoreGraphics
import XCTest
@testable import FunctionCardKit

@MainActor
final class IslandSurfaceTests: XCTestCase {
    func testExpandedLogicalStateMakesOnlyExpandedContentInteractive() {
        let policy = IslandContentInteractivity(isExpanded: true)

        XCTAssertTrue(policy.expandedAllowsHitTesting)
        XCTAssertFalse(policy.compactAllowsHitTesting)
    }

    func testCompactLogicalStateMakesOnlyCompactContentInteractive() {
        let policy = IslandContentInteractivity(isExpanded: false)

        XCTAssertFalse(policy.expandedAllowsHitTesting)
        XCTAssertTrue(policy.compactAllowsHitTesting)
    }

    func testRestingHidesExpandedContentBeforeSurfaceExpansionStartsCollapsing() {
        XCTAssertEqual(
            IslandContentTransition.expandedOpacity(expansion: 1, isResting: true),
            0
        )
    }

    func testNonRestingExpandedContentContinuesFollowingExpansionProgress() {
        XCTAssertEqual(
            IslandContentTransition.expandedOpacity(expansion: 1, isResting: false),
            1
        )
        XCTAssertEqual(
            IslandContentTransition.expandedOpacity(expansion: 0.4, isResting: false),
            0.4
        )
        XCTAssertEqual(
            IslandContentTransition.expandedOpacity(expansion: -0.2, isResting: false),
            0
        )
        XCTAssertEqual(
            IslandContentTransition.expandedOpacity(expansion: 1.2, isResting: false),
            1
        )
    }

    func testDisplayContextCanMoveFromPhysicalNotchToNonNotchedScreen() {
        let context = IslandDisplayContext()

        context.updateLayout(
            physicalNotchSize: CGSize(width: 224, height: 32),
            compactSurfaceSize: CGSize(width: 425, height: 32),
            expandedSurfaceSize: CGSize(width: 800, height: 460)
        )
        XCTAssertEqual(context.physicalNotchSize, CGSize(width: 224, height: 32))
        XCTAssertEqual(context.compactSurfaceSize, CGSize(width: 425, height: 32))
        XCTAssertEqual(context.expandedSurfaceSize, CGSize(width: 800, height: 460))
        XCTAssertEqual(context.presentationSurfaceSize, CGSize.zero)

        context.updateLayout(
            physicalNotchSize: nil,
            compactSurfaceSize: CGSize(width: 260, height: 32),
            expandedSurfaceSize: CGSize(width: 768, height: 460)
        )
        XCTAssertNil(context.physicalNotchSize)
        XCTAssertEqual(context.compactSurfaceSize, CGSize(width: 260, height: 32))
        XCTAssertEqual(context.expandedSurfaceSize, CGSize(width: 768, height: 460))
    }

    func testDisplayContextNormalizesExpansionTargetToEndpoints() {
        let context = IslandDisplayContext()

        context.setExpansionTarget(-0.2)
        XCTAssertEqual(context.expansionTarget, 0)

        context.setExpansionTarget(0.4)
        XCTAssertEqual(context.expansionTarget, 0)

        context.setExpansionTarget(0.6)
        XCTAssertEqual(context.expansionTarget, 1)

        context.setExpansionTarget(1.4)
        XCTAssertEqual(context.expansionTarget, 1)
    }

    func testSurfaceLayoutInterpolatesSizeWithoutChangingTheEndpoints() {
        let compact = CGSize(width: 425, height: 32)
        let expanded = CGSize(width: 800, height: 460)

        XCTAssertEqual(
            IslandSurfaceLayout.size(compact: compact, expanded: expanded, expansion: 0),
            compact
        )
        XCTAssertEqual(
            IslandSurfaceLayout.size(compact: compact, expanded: expanded, expansion: 0.5),
            CGSize(width: 612.5, height: 246)
        )
        XCTAssertEqual(
            IslandSurfaceLayout.size(compact: compact, expanded: expanded, expansion: 1),
            expanded
        )
    }

    func testSurfaceRadiiInterpolateTogetherAcrossExpansion() {
        let midpoint = IslandSurfaceMetrics.cornerRadii(expansion: 0.5)

        XCTAssertEqual(midpoint.top, 12.5)
        XCTAssertEqual(midpoint.bottom, 19)
    }

    func testCompactWidthCompressesTimerWingsBySixtyFourPointsAroundPhysicalNotch() {
        let width = IslandCompactLayout.width(
            baseWidth: 260,
            leadingWidth: 144,
            trailingWidth: 72,
            physicalNotchWidth: 189,
            horizontalPadding: 10
        )

        XCTAssertEqual(width, 369)
        XCTAssertEqual(
            IslandCompactLayout.sideReservation(leadingWidth: 144, trailingWidth: 72),
            80
        )
        XCTAssertEqual(
            IslandCompactLayout.notchMidX(
                leadingWidth: 144,
                trailingWidth: 72,
                physicalNotchWidth: 189,
                horizontalPadding: 10
            ),
            width / 2
        )
    }

    func testCompactWidthCompressesPusherWingsBySixtyFourPointsAroundPhysicalNotch() {
        let width = IslandCompactLayout.width(
            baseWidth: 340,
            leadingWidth: 128,
            trailingWidth: 184,
            physicalNotchWidth: 189,
            horizontalPadding: 10
        )

        XCTAssertEqual(width, 449)
        XCTAssertEqual(
            IslandCompactLayout.sideReservation(leadingWidth: 128, trailingWidth: 184),
            120
        )
        XCTAssertEqual(
            IslandCompactLayout.notchMidX(
                leadingWidth: 128,
                trailingWidth: 184,
                physicalNotchWidth: 189,
                horizontalPadding: 10
            ),
            width / 2
        )
    }

    func testCompactWidthKeepsBaseWidthWithoutPhysicalNotch() {
        let width = IslandCompactLayout.width(
            baseWidth: 260,
            leadingWidth: 144,
            trailingWidth: 72,
            physicalNotchWidth: nil,
            horizontalPadding: 10
        )

        XCTAssertEqual(width, 260)
    }

    func testCardMetricsResolveCompactSizeAroundPhysicalNotch() {
        let metrics = FunctionCardMetrics(
            compactWidth: 260,
            compactHeight: 32,
            compactLeadingWidth: 144,
            compactTrailingWidth: 72,
            expandedWidth: 800,
            expandedHeight: 460
        )

        XCTAssertEqual(
            metrics.compactSize(physicalNotchSize: CGSize(width: 189, height: 32)),
            CGSize(width: 369, height: 32)
        )
        XCTAssertEqual(
            metrics.compactSize(physicalNotchSize: nil),
            CGSize(width: 260, height: 32)
        )
    }

    func testPresentationSurfaceCanBeUpdatedIndependentlyFromTarget() {
        let context = IslandDisplayContext(
            compactSurfaceSize: CGSize(width: 497, height: 32),
            expandedSurfaceSize: CGSize(width: 800, height: 460)
        )

        context.setExpansionTarget(1)
        context.updatePresentationSurfaceSize(CGSize(width: 600, height: 180))

        XCTAssertEqual(context.expansionTarget, 1)
        XCTAssertEqual(context.presentationSurfaceSize, CGSize(width: 600, height: 180))
    }

    func testBlackSurfaceVisibilityIsIndependentFromExpansionTarget() {
        let context = IslandDisplayContext(expansionTarget: 1, drawsBlackSurface: true)

        context.setExpansionTarget(0)
        XCTAssertTrue(context.drawsBlackSurface)

        context.setDrawsBlackSurface(false)
        XCTAssertEqual(context.expansionTarget, 0)
        XCTAssertFalse(context.drawsBlackSurface)
    }

    func testSurfaceRadiiProduceSoftRectanglesInsteadOfCapsules() {
        XCTAssertEqual(IslandSurfaceMetrics.compact.top, 6)
        XCTAssertEqual(IslandSurfaceMetrics.compact.bottom, 14)
        XCTAssertEqual(IslandSurfaceMetrics.expanded.top, 19)
        XCTAssertEqual(IslandSurfaceMetrics.expanded.bottom, 24)
        XCTAssertLessThan(IslandSurfaceMetrics.compact.bottom, 32 / 2)
    }

    func testExpandedContentInsetsKeepContentOutsideTheSoftCorners() {
        let insets = IslandExpandedLayout.contentInsets
        let contentSize = IslandExpandedLayout.contentSize(
            surfaceSize: CGSize(width: 800, height: 460)
        )

        XCTAssertEqual(insets.top, 16)
        XCTAssertEqual(insets.leading, 28)
        XCTAssertEqual(insets.bottom, 28)
        XCTAssertEqual(insets.trailing, 28)
        XCTAssertGreaterThanOrEqual(insets.leading, IslandSurfaceMetrics.expanded.top)
        XCTAssertGreaterThanOrEqual(insets.trailing, IslandSurfaceMetrics.expanded.top)
        XCTAssertGreaterThanOrEqual(insets.bottom, IslandSurfaceMetrics.expanded.bottom)
        XCTAssertEqual(contentSize, CGSize(width: 744, height: 416))
    }

    func testTopAttachedShapeAnimatesBothRadiiAndCoversTopCenter() {
        let shape = TopAttachedRoundedRectangle(topCornerRadius: 6, bottomCornerRadius: 14)
        let rect = CGRect(x: 0, y: 0, width: 340, height: 38)
        let path = shape.path(in: rect)

        XCTAssertEqual(shape.animatableData.first, 6)
        XCTAssertEqual(shape.animatableData.second, 14)
        XCTAssertEqual(path.boundingRect, rect)
        XCTAssertTrue(path.contains(CGPoint(x: rect.midX, y: 0.5)))
        XCTAssertFalse(path.contains(CGPoint(x: 0.5, y: rect.maxY - 0.5)))
    }
}
