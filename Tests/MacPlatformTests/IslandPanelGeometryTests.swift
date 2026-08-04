import XCTest
import CoreGraphics
@testable import MacPlatform

final class IslandPanelGeometryTests: XCTestCase {
    func testTransitionHostFrameContainsBothEndpointsAtTheSameTopCenterAnchor() {
        let compact = CGRect(x: 543.5, y: 950, width: 425, height: 32)
        let expanded = CGRect(x: 356, y: 522, width: 800, height: 460)

        let host = IslandPanelGeometry.transitionHostFrame(
            compactFrame: compact,
            expandedFrame: expanded
        )

        XCTAssertEqual(host, expanded)
        XCTAssertEqual(host.midX, compact.midX)
        XCTAssertEqual(host.maxY, compact.maxY)
    }

    func testTransitionHostKeepsTheCurrentLargerSurfaceUntilCompletion() {
        let compact = CGRect(x: 507.5, y: 950, width: 497, height: 32)
        let expanded = CGRect(x: 356, y: 522, width: 800, height: 460)

        let host = IslandPanelGeometry.transitionHostFrame(
            compactFrame: compact,
            expandedFrame: expanded,
            minimumHostSize: CGSize(width: 960, height: 520)
        )

        XCTAssertEqual(host, CGRect(x: 276, y: 462, width: 960, height: 520))
        XCTAssertEqual(host.midX, expanded.midX)
        XCTAssertEqual(host.maxY, expanded.maxY)
    }

    func testSurfaceFramesStayTopCenteredForEveryInterpolatedSize() {
        let host = CGRect(x: 356, y: 522, width: 800, height: 460)
        let samples: [(CGSize, CGRect)] = [
            (CGSize(width: 425, height: 32), CGRect(x: 543.5, y: 950, width: 425, height: 32)),
            (CGSize(width: 518.75, height: 139), CGRect(x: 496.625, y: 843, width: 518.75, height: 139)),
            (CGSize(width: 612.5, height: 246), CGRect(x: 449.75, y: 736, width: 612.5, height: 246)),
            (CGSize(width: 706.25, height: 353), CGRect(x: 402.875, y: 629, width: 706.25, height: 353)),
            (CGSize(width: 800, height: 460), host),
        ]

        for (size, expected) in samples {
            let surface = IslandPanelGeometry.surfaceFrame(size: size, within: host)
            XCTAssertEqual(surface, expected)
            XCTAssertEqual(surface.midX, host.midX)
            XCTAssertEqual(surface.maxY, host.maxY)
        }
    }

    func testNewTransitionGenerationInvalidatesEarlierCompletion() {
        var state = IslandPanelTransitionState()
        let expanding = state.begin(targetExpanded: true)
        let collapsing = state.begin(targetExpanded: false)

        XCTAssertFalse(state.acceptsCompletion(generation: expanding, targetExpanded: true))
        XCTAssertTrue(state.acceptsCompletion(generation: collapsing, targetExpanded: false))
        XCTAssertFalse(state.acceptsCompletion(generation: collapsing, targetExpanded: true))
    }

    func testOnlyLatestTransitionCanFinishExactlyOnce() {
        var state = IslandPanelTransitionState()
        let firstExpansion = state.begin(targetExpanded: true)
        let collapse = state.begin(targetExpanded: false)
        let finalExpansion = state.begin(targetExpanded: true)

        XCTAssertFalse(state.finish(generation: firstExpansion, targetExpanded: true))
        XCTAssertFalse(state.finish(generation: collapse, targetExpanded: false))
        XCTAssertTrue(state.finish(generation: finalExpansion, targetExpanded: true))
        XCTAssertFalse(state.finish(generation: finalExpansion, targetExpanded: true))
    }

    func testTransitionEnvironmentChangesForCardAndSameScreenGeometry() {
        let original = IslandPanelTransitionEnvironment(
            selectedCardID: "timer",
            screenID: "display-1",
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            safeTopInset: 32,
            auxiliaryTopLeftWidth: 620,
            auxiliaryTopRightWidth: 620
        )
        let changedCard = IslandPanelTransitionEnvironment(
            selectedCardID: "pusher",
            screenID: original.screenID,
            screenFrame: original.screenFrame,
            safeTopInset: original.safeTopInset,
            auxiliaryTopLeftWidth: original.auxiliaryTopLeftWidth,
            auxiliaryTopRightWidth: original.auxiliaryTopRightWidth
        )
        let changedResolution = IslandPanelTransitionEnvironment(
            selectedCardID: original.selectedCardID,
            screenID: original.screenID,
            screenFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
            safeTopInset: original.safeTopInset,
            auxiliaryTopLeftWidth: original.auxiliaryTopLeftWidth,
            auxiliaryTopRightWidth: original.auxiliaryTopRightWidth
        )
        let changedSafeArea = IslandPanelTransitionEnvironment(
            selectedCardID: original.selectedCardID,
            screenID: original.screenID,
            screenFrame: original.screenFrame,
            safeTopInset: 0,
            auxiliaryTopLeftWidth: nil,
            auxiliaryTopRightWidth: nil
        )

        XCTAssertNotEqual(original, changedCard)
        XCTAssertNotEqual(original, changedResolution)
        XCTAssertNotEqual(original, changedSafeArea)
        XCTAssertEqual(original, original)
    }

    func testCompactAndExpandedFramesShareTopCenterAnchor() {
        let screenFrame = CGRect(x: -1_600, y: 120, width: 1_440, height: 900)
        let compact = IslandPanelGeometry.frame(
            requestedSize: CGSize(width: 340, height: 38),
            screenFrame: screenFrame,
            safeTopInset: 32,
            auxiliaryTopLeftWidth: 610,
            auxiliaryTopRightWidth: 610
        )
        let expanded = IslandPanelGeometry.frame(
            requestedSize: CGSize(width: 760, height: 420),
            screenFrame: screenFrame,
            safeTopInset: 32,
            auxiliaryTopLeftWidth: 610,
            auxiliaryTopRightWidth: 610
        )

        XCTAssertEqual(compact.midX, -880)
        XCTAssertEqual(expanded.midX, -880)
        XCTAssertEqual(compact.maxY, 1_020)
        XCTAssertEqual(expanded.maxY, 1_020)
    }

    func testAnimationPolicyDisablesMotionForInitialDisplayAndReduceMotion() {
        XCTAssertNil(
            IslandPanelAnimation.duration(
                requested: false,
                isExpanded: true,
                reduceMotion: false,
                panelIsVisible: true
            )
        )
        XCTAssertNil(
            IslandPanelAnimation.duration(
                requested: true,
                isExpanded: true,
                reduceMotion: false,
                panelIsVisible: false
            )
        )
        XCTAssertNil(
            IslandPanelAnimation.duration(
                requested: true,
                isExpanded: true,
                reduceMotion: true,
                panelIsVisible: true
            )
        )
    }

    func testAnimationPolicyUsesStateSpecificDurationsForVisiblePanel() {
        XCTAssertEqual(
            IslandPanelAnimation.duration(
                requested: true,
                isExpanded: true,
                reduceMotion: false,
                panelIsVisible: true
            ),
            0.22
        )
        XCTAssertEqual(
            IslandPanelAnimation.duration(
                requested: true,
                isExpanded: false,
                reduceMotion: false,
                panelIsVisible: true
            ),
            0.18
        )
    }

    func testPanelIsTopCenteredAndClampedToVisibleWidth() {
        let frame = IslandPanelGeometry.frame(
            requestedSize: CGSize(width: 920, height: 480),
            screenFrame: CGRect(x: 100, y: 40, width: 800, height: 600),
            safeTopInset: 28,
            auxiliaryTopLeftWidth: 280,
            auxiliaryTopRightWidth: 280
        )

        XCTAssertEqual(frame.width, 768)
        XCTAssertEqual(frame.midX, 500)
        XCTAssertEqual(frame.maxY, 640)
    }

    func testNonNotchedCompactPanelKeepsRequestedSizeWhenItFits() {
        let frame = IslandPanelGeometry.frame(
            requestedSize: CGSize(width: 340, height: 38),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            safeTopInset: 0,
            auxiliaryTopLeftWidth: nil,
            auxiliaryTopRightWidth: nil
        )

        XCTAssertEqual(frame.size, CGSize(width: 340, height: 38))
        XCTAssertEqual(frame.minX, 550)
        XCTAssertEqual(frame.maxY, 900)
    }

    func testPhysicalNotchExpandsSmallRequestToCoverCameraRegion() {
        let frame = IslandPanelGeometry.frame(
            requestedSize: CGSize(width: 180, height: 24),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            safeTopInset: 32,
            auxiliaryTopLeftWidth: 610,
            auxiliaryTopRightWidth: 610
        )

        XCTAssertEqual(frame.size, CGSize(width: 224, height: 32))
        XCTAssertEqual(frame.midX, 720)
        XCTAssertEqual(frame.maxY, 900)
    }

    func testMissingAuxiliaryAreasKeepsRequestedWidthButStillCoversNotchHeight() {
        let frame = IslandPanelGeometry.frame(
            requestedSize: CGSize(width: 300, height: 24),
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            safeTopInset: 34,
            auxiliaryTopLeftWidth: nil,
            auxiliaryTopRightWidth: nil
        )

        XCTAssertEqual(frame.size, CGSize(width: 300, height: 34))
        XCTAssertEqual(frame.maxY, 900)
    }

    func testPanelClampsHeightAndLeavesBottomMargin() {
        let frame = IslandPanelGeometry.frame(
            requestedSize: CGSize(width: 600, height: 900),
            screenFrame: CGRect(x: 100, y: 40, width: 800, height: 600),
            safeTopInset: 0,
            auxiliaryTopLeftWidth: nil,
            auxiliaryTopRightWidth: nil
        )

        XCTAssertEqual(frame.height, 584)
        XCTAssertEqual(frame.maxY, 640)
        XCTAssertEqual(frame.minY, 56)
    }
}
