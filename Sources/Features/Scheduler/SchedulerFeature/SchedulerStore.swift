import Foundation
import FunctionCardKit
import Observation
import PeekerCore

@MainActor
@Observable
public final class SchedulerStore {
    public private(set) var events: [SchedulerEvent] = []
    public private(set) var occurrences: [SchedulerOccurrence] = []
    public private(set) var sources: [SchedulerSource] = []
    public private(set) var warnings: [SchedulerImportWarning] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var visibleFrom: Date
    public private(set) var visibleTo: Date
    public var reminderMinutes: Int?
    public var isEnabled: Bool

    private let repository: any SchedulerRepository
    private let eventHub: TemporalEventHub
    private let publishPrompt: @MainActor (FunctionCardPrompt) -> Void
    private let revokePrompt: @MainActor (String) -> Void
    private let onReminderChanged: @MainActor (Int?) -> Void
    private let calendar: Calendar
    private let mutationGate = SchedulerMutationGate()
    private let reminderKey = TemporalEventKey("scheduler.reminder")
    private var loadTask: Task<Void, Never>?
    private var snapshot = SchedulerSnapshot(events: [], overrides: [])
    private var scheduledTokens = Set<String>()

    public init(
        repository: any SchedulerRepository,
        eventHub: TemporalEventHub,
        reminderMinutes: Int? = 10,
        isEnabled: Bool = true,
        calendar: Calendar = Calendar(identifier: .gregorian),
        publishPrompt: @escaping @MainActor (FunctionCardPrompt) -> Void = { _ in },
        revokePrompt: @escaping @MainActor (String) -> Void = { _ in },
        onReminderChanged: @escaping @MainActor (Int?) -> Void = { _ in }
    ) {
        self.repository=repository; self.eventHub=eventHub; self.reminderMinutes=reminderMinutes
        self.isEnabled=isEnabled; self.calendar=calendar; self.publishPrompt=publishPrompt
        self.revokePrompt=revokePrompt; self.onReminderChanged=onReminderChanged
        let week = Self.weekInterval(containing: Date(), calendar: calendar)
        visibleFrom=week.start; visibleTo=week.end
    }

    public func load() async {
        if let loadTask { await loadTask.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadUnlocked()
        }
        loadTask = task
        await task.value
    }

    private func loadUnlocked() async {
        isLoading = true; defer { isLoading = false }
        do {
            snapshot = try await repository.snapshot()
            events = snapshot.events
            sources = try await repository.sources()
            publishVisibleOccurrences()
            await scheduleNextReminder(now: Date())
            errorMessage = nil
        } catch { errorMessage = "Scheduler 无法载入：\(error.localizedDescription)" }
    }

    public func showWeek(containing date: Date) {
        let week = Self.weekInterval(containing: date, calendar: calendar)
        visibleFrom=week.start; visibleTo=week.end; publishVisibleOccurrences()
    }

    public func list(from: Date, to: Date) async throws -> [SchedulerOccurrence] {
        await load()
        return SchedulerRecurrenceExpander.expand(snapshot: snapshot, from: from, to: to, calendar: calendar)
    }

    public func event(id: UUID) async throws -> SchedulerEvent {
        await load()
        guard let event = events.first(where: { $0.id == id }) else { throw SchedulerError.eventNotFound }
        return event
    }

    @discardableResult
    public func create(_ event: SchedulerEvent) async throws -> SchedulerEvent {
        try await withMutation {
            let saved = try await repository.save(event)
            try await reloadAfterMutation()
            return saved
        }
    }

    @discardableResult
    public func update(
        _ replacement: SchedulerEvent,
        occurrenceKey: String? = nil,
        scope: SchedulerMutationScope? = nil
    ) async throws -> (SchedulerEvent, Int) {
        try await withMutation {
            guard let current = try await repository.event(id: replacement.id) else { throw SchedulerError.eventNotFound }
            if current.recurrence == nil {
                guard occurrenceKey == nil, scope == nil else { throw SchedulerError.scopeNotAllowed }
                let saved = try await repository.save(replacement)
                try await reloadAfterMutation(); return (saved, 0)
            }
            guard let occurrenceKey, let scope else { throw SchedulerError.scopeRequired }
            guard occurrenceExists(event: current, key: occurrenceKey) else { throw SchedulerError.occurrenceNotFound }
            switch scope {
            case .this:
                let occurrence = SchedulerOccurrence(
                    eventID: current.id, originalKey: occurrenceKey, title: replacement.title,
                    notes: replacement.notes, location: replacement.location, colorHex: replacement.colorHex,
                    time: replacement.time, recurring: true, isException: true, sourceID: current.sourceID
                )
                try await repository.saveOverride(SchedulerOccurrenceOverride(
                    eventID: current.id, occurrenceKey: occurrenceKey, isCancelled: false, replacement: occurrence
                ))
                try await reloadAfterMutation(); return (current, 0)
            case .all:
                let cleared = try await repository.deleteOverrides(eventID: current.id, fromKey: nil)
                let saved = try await repository.save(replacement)
                try await reloadAfterMutation(); return (saved, cleared)
            case .future:
                let cleared = try await repository.deleteOverrides(eventID: current.id, fromKey: occurrenceKey)
                var old = current
                old.recurrence = try truncated(current.recurrence!, before: occurrenceKey, event: current)
                _ = try await repository.save(old)
                var future = replacement; future.id = UUID()
                _ = try await repository.save(future)
                try await reloadAfterMutation(); return (future, cleared)
            }
        }
    }

    public func delete(id: UUID, occurrenceKey: String? = nil, scope: SchedulerMutationScope? = nil) async throws -> Int {
        try await withMutation {
            guard let event = try await repository.event(id: id) else { throw SchedulerError.eventNotFound }
            if event.recurrence == nil {
                guard occurrenceKey == nil, scope == nil else { throw SchedulerError.scopeNotAllowed }
                _ = try await repository.deleteEvent(id: id); try await reloadAfterMutation(); return 0
            }
            guard let occurrenceKey, let scope else { throw SchedulerError.scopeRequired }
            guard occurrenceExists(event: event, key: occurrenceKey) else { throw SchedulerError.occurrenceNotFound }
            let cleared: Int
            switch scope {
            case .this:
                try await repository.saveOverride(SchedulerOccurrenceOverride(eventID: id, occurrenceKey: occurrenceKey, isCancelled: true, replacement: nil)); cleared = 0
            case .future:
                cleared = try await repository.deleteOverrides(eventID: id, fromKey: occurrenceKey)
                var old = event; old.recurrence = try truncated(event.recurrence!, before: occurrenceKey, event: event)
                _ = try await repository.save(old)
            case .all:
                cleared = try await repository.deleteOverrides(eventID: id, fromKey: nil)
                _ = try await repository.deleteEvent(id: id)
            }
            try await reloadAfterMutation(); return cleared
        }
    }

    public func importICS(fileURL: URL, sourceID: UUID? = nil) async throws -> (SchedulerImportCommit, [SchedulerImportWarning]) {
        try await withMutation {
            let canonical = fileURL.standardizedFileURL.resolvingSymlinksInPath()
            guard canonical.isFileURL, FileManager.default.isReadableFile(atPath: canonical.path) else { throw SchedulerError.sourceUnreadable }
            let data = try Data(contentsOf: canonical)
            let parsed = try SchedulerICSParser.parse(data)
            let existingSources = try await repository.sources()
            let existing: SchedulerSource?
            if let sourceID {
                existing = existingSources.first(where: { $0.id == sourceID })
                guard existing != nil else { throw SchedulerError.sourceNotFound }
                if existingSources.contains(where: { $0.id != sourceID && $0.canonicalPath == canonical.path }) { throw SchedulerError.sourcePathConflict }
            } else { existing = existingSources.first(where: { $0.canonicalPath == canonical.path }) }
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            var source = existing ?? SchedulerSource(canonicalPath: canonical.path, displayName: canonical.lastPathComponent)
            source.canonicalPath=canonical.path; source.displayName=canonical.lastPathComponent
            source.lastAttemptAtMilliseconds=now; source.lastSuccessfulImportAtMilliseconds=now
            source.lastResult="created=\(parsed.series.count), skipped=\(parsed.protectedUIDs.count)"
            let commit = try await repository.replaceSource(source, series: parsed.series, protectedUIDs: parsed.protectedUIDs)
            warnings=parsed.warnings; try await reloadAfterMutation()
            return (commit, parsed.warnings)
        }
    }

    public func removeSource(id: UUID) async throws -> Int {
        try await withMutation { let count = try await repository.removeSource(id: id); try await reloadAfterMutation(); return count }
    }

    public func setReminder(minutes: Int?) async throws {
        if let minutes, !(1...60).contains(minutes) { throw SchedulerError.invalidTimeRange }
        reminderMinutes=minutes; onReminderChanged(minutes); await scheduleNextReminder(now: Date())
    }

    public func setEnabled(_ enabled: Bool) async {
        isEnabled=enabled
        if !enabled {
            await eventHub.remove(reminderKey)
            scheduledTokens.forEach(revokePrompt); scheduledTokens.removeAll()
        } else { await scheduleNextReminder(now: Date()) }
    }

    public func temporalContextChanged() async { publishVisibleOccurrences(); await scheduleNextReminder(now: Date()) }

    private func reloadAfterMutation() async throws {
        scheduledTokens.forEach(revokePrompt); scheduledTokens.removeAll()
        snapshot = try await repository.snapshot(); events=snapshot.events; sources=try await repository.sources()
        publishVisibleOccurrences(); await scheduleNextReminder(now: Date())
    }

    private func publishVisibleOccurrences() {
        occurrences = SchedulerRecurrenceExpander.expand(snapshot: snapshot, from: visibleFrom, to: visibleTo, calendar: calendar)
    }

    private func scheduleNextReminder(now: Date) async {
        guard isEnabled, let reminderMinutes else { await eventHub.remove(reminderKey); return }
        let horizon = calendar.date(byAdding: .year, value: 5, to: now) ?? now.addingTimeInterval(5 * 365 * 86_400)
        let candidates = SchedulerRecurrenceExpander.expand(snapshot: snapshot, from: now.addingTimeInterval(-3600), to: horizon, calendar: calendar)
            .compactMap { occurrence -> (SchedulerOccurrence, Date)? in
                guard case let .timed(start, _, _) = occurrence.time else { return nil }
                let trigger = Date(timeIntervalSince1970: Double(start) / 1000).addingTimeInterval(Double(-reminderMinutes * 60))
                return trigger > now ? (occurrence, trigger) : nil
            }.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.id < $1.0.id }
        guard let next = candidates.first else { await eventHub.remove(reminderKey); return }
        await eventHub.set(reminderKey, at: next.1) { [weak self] reason in
            await self?.fireReminders(at: next.1, reason: reason)
        }
    }

    private func fireReminders(at trigger: Date, reason: TemporalTriggerReason) async {
        guard reason == .scheduled, isEnabled, let reminderMinutes else { await scheduleNextReminder(now: Date()); return }
        let due = SchedulerRecurrenceExpander.expand(snapshot: snapshot, from: trigger, to: trigger.addingTimeInterval(Double(reminderMinutes * 60 + 1)), calendar: calendar)
            .filter { occurrence in
                guard case let .timed(start, _, _) = occurrence.time else { return false }
                return abs(Date(timeIntervalSince1970: Double(start) / 1000).addingTimeInterval(Double(-reminderMinutes * 60)).timeIntervalSince(trigger)) < 0.5
            }
        for occurrence in due {
            let token = "scheduler:\(occurrence.eventID.uuidString):\(occurrence.originalKey)"
            scheduledTokens.insert(token)
            publishPrompt(FunctionCardPrompt(
                token: token, sourceID: .scheduler, systemImage: "calendar",
                moduleName: "Scheduler", summary: "\(occurrence.title) · \(localStart(occurrence.time))"
            ))
        }
        await scheduleNextReminder(now: trigger.addingTimeInterval(1))
    }

    private func occurrenceExists(event: SchedulerEvent, key: String) -> Bool {
        let start: Date; let end: Date
        switch event.time {
        case .timed: guard let value = Int64(key) else { return false }; start=Date(timeIntervalSince1970: Double(value)/1000-1); end=start.addingTimeInterval(2)
        case .allDay: guard let value=SchedulerLocalDate(key), let date=value.date(in: .current) else { return false }; start=date; end=date.addingTimeInterval(86_400)
        }
        return !SchedulerRecurrenceExpander.expand(snapshot: SchedulerSnapshot(events: [event], overrides: []), from: start, to: end, calendar: calendar).isEmpty
    }

    private func truncated(_ recurrence: SchedulerRecurrence, before key: String, event: SchedulerEvent) throws -> SchedulerRecurrence {
        let end: SchedulerRecurrenceEnd
        switch event.time {
        case .timed: guard let value=Int64(key) else { throw SchedulerError.occurrenceNotFound }; end = .untilTimed(value - 1)
        case .allDay: guard let day=SchedulerLocalDate(key), let previous=day.adding(days: -1, in: .current) else { throw SchedulerError.occurrenceNotFound }; end = .untilDate(previous)
        }
        return try SchedulerRecurrence(frequency: recurrence.frequency, interval: recurrence.interval, weekdays: recurrence.weekdays, end: end)
    }

    private func localStart(_ time: SchedulerEventTime) -> String {
        switch time {
        case let .timed(start, _, _): return Date(timeIntervalSince1970: Double(start)/1000).formatted(date: .omitted, time: .shortened)
        case let .allDay(start, _): return start.description
        }
    }

    private func withMutation<T>(_ operation: @MainActor () async throws -> T) async rethrows -> T {
        await mutationGate.lock()
        do {
            let result = try await operation()
            await mutationGate.unlock()
            return result
        } catch {
            await mutationGate.unlock()
            throw error
        }
    }

    public static func weekInterval(containing date: Date, calendar input: Calendar) -> DateInterval {
        var calendar=input; calendar.firstWeekday=2
        let day=calendar.startOfDay(for: date); let weekday=calendar.component(.weekday, from: day)
        let offset=(weekday-calendar.firstWeekday+7)%7
        let start=calendar.date(byAdding: .day, value: -offset, to: day)!
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!)
    }
}

private actor SchedulerMutationGate {
    private var locked=false; private var waiters:[CheckedContinuation<Void,Never>]=[]
    func lock() async { if !locked { locked=true; return }; await withCheckedContinuation { waiters.append($0) } }
    func unlock() { if waiters.isEmpty { locked=false } else { waiters.removeFirst().resume() } }
}
