import Foundation
import Observation

@MainActor
@Observable
final class SchedulerEditorDraft {
    let original: SchedulerEvent
    let allowsRecurrenceEditing: Bool
    var title: String
    var notes: String
    var location: String
    var color: String
    var timeDraft: SchedulerEventTimeFormDraft
    var frequency: String
    var interval: Int

    init(event: SchedulerEvent, allowsRecurrenceEditing: Bool) {
        original = event
        self.allowsRecurrenceEditing = allowsRecurrenceEditing
        title = event.title; notes = event.notes ?? ""; location = event.location ?? ""
        color = event.colorHex; timeDraft = SchedulerEventTimeFormDraft(time: event.time)
        frequency = event.recurrence?.frequency.rawValue ?? "none"
        interval = event.recurrence?.interval ?? 1
    }

    var hasChanges: Bool {
        title != original.title || notes != (original.notes ?? "") || location != (original.location ?? "")
            || color != original.colorHex || timeDraft != SchedulerEventTimeFormDraft(time: original.time)
            || frequency != (original.recurrence?.frequency.rawValue ?? "none") || interval != (original.recurrence?.interval ?? 1)
    }

    var updatedEvent: SchedulerEvent? {
        let originalDraft = SchedulerEventTimeFormDraft(time: original.time)
        guard let time = timeDraft == originalDraft ? original.time : timeDraft.resolvedTime() else { return nil }
        let recurrence: SchedulerRecurrence?
        if !allowsRecurrenceEditing || (frequency == (original.recurrence?.frequency.rawValue ?? "none") && interval == (original.recurrence?.interval ?? 1)) {
            recurrence = original.recurrence
        } else if frequency == "none" {
            recurrence = nil
        } else {
            guard let frequency = SchedulerFrequency(rawValue: frequency),
                  let value = try? SchedulerRecurrence(frequency: frequency, interval: interval) else {
                return nil
            }
            recurrence = value
        }
        return try? SchedulerEvent(
            id: original.id,
            sourceID: original.sourceID,
            sourceUID: original.sourceUID,
            sourceSegmentKey: original.sourceSegmentKey,
            title: title,
            notes: notes.isEmpty ? nil : notes,
            location: location.isEmpty ? nil : location,
            colorHex: color,
            time: time,
            recurrence: recurrence,
            createdAtMilliseconds: original.createdAtMilliseconds,
            updatedAtMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        )
    }

}
