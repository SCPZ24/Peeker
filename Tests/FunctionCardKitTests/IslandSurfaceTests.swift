import CoreGraphics
import XCTest
@testable import FunctionCardKit

@MainActor
final class IslandSurfaceTests: XCTestCase {
    func testDisplayContextCanMoveFromPhysicalNotchToNonNotchedScreen() {
        let context = IslandDisplayContext()

        context.updatePhysicalNotchSize(CGSize(width: 224, height: 32))
        XCTAssertEqual(context.physicalNotchSize, CGSize(width: 224, height: 32))

        context.updatePhysicalNotchSize(nil)
        XCTAssertNil(context.physicalNotchSize)
    }

    func testCompactWidthReservesBothWingsAndPhysicalNotch() {
        let width = IslandCompactLayout.width(
            baseWidth: 340,
            leadingWidth: 120,
            trailingWidth: 140,
            physicalNotchWidth: 224,
            horizontalPadding: 14
        )

        XCTAssertEqual(width, 512)
    }

    func testCompactWidthKeepsBaseWidthWithoutPhysicalNotch() {
        let width = IslandCompactLayout.width(
            baseWidth: 340,
            leadingWidth: 120,
            trailingWidth: 140,
            physicalNotchWidth: nil,
            horizontalPadding: 14
        )

        XCTAssertEqual(width, 340)
    }

    func testCardMetricsResolveCompactSizeAroundPhysicalNotch() {
        let metrics = FunctionCardMetrics(
            compactWidth: 340,
            compactHeight: 38,
            compactLeadingWidth: 120,
            compactTrailingWidth: 140,
            expandedWidth: 760,
            expandedHeight: 420
        )

        XCTAssertEqual(
            metrics.compactSize(physicalNotchSize: CGSize(width: 224, height: 32)),
            CGSize(width: 512, height: 38)
        )
        XCTAssertEqual(
            metrics.compactSize(physicalNotchSize: nil),
            CGSize(width: 340, height: 38)
        )
    }

    func testSurfaceRadiiProduceSoftRectanglesInsteadOfCapsules() {
        XCTAssertEqual(IslandSurfaceMetrics.compact.top, 6)
        XCTAssertEqual(IslandSurfaceMetrics.compact.bottom, 14)
        XCTAssertEqual(IslandSurfaceMetrics.expanded.top, 19)
        XCTAssertEqual(IslandSurfaceMetrics.expanded.bottom, 24)
        XCTAssertLessThan(IslandSurfaceMetrics.compact.bottom, 38 / 2)
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
