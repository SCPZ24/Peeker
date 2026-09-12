import XCTest
@testable import TargetorFeature

final class TargetorFeedbackAnimationTests: XCTestCase {
    func testFeedbackHasBoundedStageSpecificLifetimesAndNoNotStartedCelebration() {
        XCTAssertEqual(TargetorFeedbackAnimation.duration(for: .notStarted), 0)
        XCTAssertEqual(TargetorFeedbackAnimation.duration(for: .started), 0.4)
        XCTAssertEqual(TargetorFeedbackAnimation.duration(for: .progressing), 0.65)
        XCTAssertEqual(TargetorFeedbackAnimation.duration(for: .completed), 0.9)
    }
}
