import XCTest
@testable import TimerFeature

final class TimerGoalFormModelTests: XCTestCase {
    func testDurationDraftAcceptsBoundaryValues() {
        XCTAssertEqual(
            TimerDurationDraft(hours: "00", minutes: "00", seconds: "01").targetSeconds,
            1
        )
        XCTAssertEqual(
            TimerDurationDraft(hours: "23", minutes: "59", seconds: "59").targetSeconds,
            86_399
        )
    }

    func testDurationDraftRejectsInvalidTextRangesAndZero() {
        XCTAssertNil(TimerDurationDraft(hours: "", minutes: "00", seconds: "01").targetSeconds)
        XCTAssertNil(TimerDurationDraft(hours: "abc", minutes: "00", seconds: "01").targetSeconds)
        XCTAssertNil(TimerDurationDraft(hours: "1.5", minutes: "00", seconds: "01").targetSeconds)
        XCTAssertNil(TimerDurationDraft(hours: "-1", minutes: "00", seconds: "01").targetSeconds)
        XCTAssertNil(TimerDurationDraft(hours: "24", minutes: "00", seconds: "00").targetSeconds)
        XCTAssertNil(TimerDurationDraft(hours: "00", minutes: "60", seconds: "00").targetSeconds)
        XCTAssertNil(TimerDurationDraft(hours: "00", minutes: "00", seconds: "60").targetSeconds)
        XCTAssertNil(TimerDurationDraft(hours: "00", minutes: "00", seconds: "00").targetSeconds)
    }

    func testAdjustChangesOneComponentAndClampsItsRange() {
        var draft = TimerDurationDraft(hours: "22", minutes: "58", seconds: "58")

        draft.adjust(.hours, by: 1)
        draft.adjust(.hours, by: 1)
        draft.adjust(.minutes, by: 1)
        draft.adjust(.minutes, by: 1)
        draft.adjust(.seconds, by: 1)
        draft.adjust(.seconds, by: 1)

        XCTAssertEqual(draft, TimerDurationDraft(hours: "23", minutes: "59", seconds: "59"))

        draft.adjust(.hours, by: -100)
        draft.adjust(.minutes, by: -100)
        draft.adjust(.seconds, by: -100)

        XCTAssertEqual(draft, TimerDurationDraft(hours: "00", minutes: "00", seconds: "00"))
    }

    func testAdjustRecoversInvalidComponentFromItsLowerBound() {
        var draft = TimerDurationDraft(hours: "invalid", minutes: "invalid", seconds: "invalid")

        draft.adjust(.hours, by: 1)
        draft.adjust(.minutes, by: -1)
        draft.adjust(.seconds, by: 2)

        XCTAssertEqual(draft, TimerDurationDraft(hours: "01", minutes: "00", seconds: "02"))
    }

    func testDurationDraftRoundTripsDomainDurations() {
        for seconds: Int64 in [1, 1_800, 3_661, 86_399] {
            XCTAssertEqual(TimerDurationDraft(targetSeconds: seconds).targetSeconds, seconds)
        }
    }

    func testPresetColorsHaveStableOrderNamesAndHexValues() {
        XCTAssertEqual(
            TimerPresetColor.allCases.map(\.localizedName),
            ["正红", "浅黄", "湖蓝", "浅绿", "紫", "粉", "青"]
        )
        XCTAssertEqual(
            TimerPresetColor.allCases.map(\.rawValue),
            ["#FF3B30", "#FFD60A", "#4F9DFF", "#34C759", "#AF52DE", "#FF2D55", "#64D2FF"]
        )
        XCTAssertEqual(TimerPresetColor.allCases.count, 7)
    }
}
