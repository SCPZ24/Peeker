import XCTest
import PeekerCore
@testable import SchedulerFeature

@MainActor
final class SchedulerEditorDraftTests: XCTestCase {
    func testNativePluralResourcesUseIntegerCounts() {
        let context = AppLanguageContext()
        context.selection = .english
        XCTAssertEqual(context.text("minute_count", bundle: L10n.resourceBundle, arguments: [1]), "1 minute")
        XCTAssertEqual(context.text("minute_count", bundle: L10n.resourceBundle, arguments: [2]), "2 minutes")
        context.selection = .japanese
        XCTAssertEqual(context.text("minute_count", bundle: L10n.resourceBundle, arguments: [2]), "2 分")
    }

    func testTitleEditPreservesFullRecurrenceAndExactTime() throws {
        let rule = try SchedulerRecurrence(frequency: .weekly, interval: 2, weekdays: [.mon, .fri], end: .count(12))
        let event = try SchedulerEvent(title: "Original", time: .timed(startMilliseconds: 1_800_000_000_123, endMilliseconds: 1_800_001_800_123, timeZoneID: "America/Los_Angeles"), recurrence: rule)
        let draft = SchedulerEditorDraft(event: event, allowsRecurrenceEditing: true)
        XCTAssertFalse(draft.hasChanges)
        draft.title = "Changed"
        XCTAssertTrue(draft.hasChanges)
        XCTAssertEqual(draft.updatedEvent?.recurrence, rule)
        XCTAssertEqual(draft.updatedEvent?.time, event.time)
        XCTAssertEqual(draft.updatedEvent?.id, event.id)
    }

    func testLocaleChangeDoesNotMutateUnsavedForm() throws {
        let context = AppLanguageContext.shared
        let previous = context.selection
        defer { context.selection = previous }
        let event = try SchedulerEvent(title: "Original", time: .allDay(start: SchedulerLocalDate(year: 2026, month: 12, day: 31), endExclusive: SchedulerLocalDate(year: 2027, month: 1, day: 2)))
        let draft = SchedulerEditorDraft(event: event, allowsRecurrenceEditing: false)
        draft.notes = "未保存のメモ"
        context.selection = .japanese
        context.selection = .english
        XCTAssertEqual(draft.notes, "未保存のメモ")
        XCTAssertEqual(draft.updatedEvent?.time, event.time)
    }
}
