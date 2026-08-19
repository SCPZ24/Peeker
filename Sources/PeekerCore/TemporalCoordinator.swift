import Foundation

public enum TemporalTriggerReason: Equatable, Sendable {
    case scheduled
    case wakeRecovery
    case clockOrTimeZoneRecovery
}

public actor TemporalCoordinator {
    public typealias EventProvider = @Sendable () async -> Date?
    public typealias EventHandler = @Sendable (TemporalTriggerReason) async -> Void

    private let scheduler: any TemporalScheduling
    private var generation = 0

    public init(scheduler: any TemporalScheduling) { self.scheduler = scheduler }

    public func reschedule(nextEvent: @escaping EventProvider, handle: @escaping EventHandler) async {
        generation += 1
        let scheduledGeneration = generation
        await scheduler.cancelAll()
        guard let date = await nextEvent() else { return }
        await scheduler.schedule(at: date) { [weak self] in
            Task {
                guard let self, await self.generation == scheduledGeneration else { return }
                await handle(.scheduled)
                await self.reschedule(nextEvent: nextEvent, handle: handle)
            }
        }
    }

    public func cancel() async {
        generation += 1
        await scheduler.cancelAll()
    }
}

public struct TemporalEventKey: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

public actor TemporalEventHub {
    public typealias EventHandler = @Sendable (TemporalTriggerReason) async -> Void

    private struct ScheduledEvent: Sendable {
        let date: Date
        let priority: Int
        let handler: EventHandler
    }

    private let clock: any Clock
    private let scheduler: any TemporalScheduling
    private var events: [TemporalEventKey: ScheduledEvent] = [:]
    private var generation = 0
    private var isSleeping = false

    public init(clock: any Clock, scheduler: any TemporalScheduling) {
        self.clock = clock
        self.scheduler = scheduler
    }

    public func set(
        _ key: TemporalEventKey,
        at date: Date?,
        priority: Int = 0,
        handler: @escaping EventHandler
    ) async {
        if let date { events[key] = ScheduledEvent(date: date, priority: priority, handler: handler) }
        else { events.removeValue(forKey: key) }
        await scheduleEarliest()
    }

    public func remove(_ key: TemporalEventKey) async {
        events.removeValue(forKey: key)
        await scheduleEarliest()
    }

    public func sleep() async {
        isSleeping = true
        generation += 1
        await scheduler.cancelAll()
    }

    public func wake() async {
        isSleeping = false
        await fireDueEvents(reason: .wakeRecovery)
    }

    public func clockOrTimeZoneChanged() async {
        await fireDueEvents(reason: .clockOrTimeZoneRecovery)
    }

    private func scheduleEarliest() async {
        generation += 1
        let scheduledGeneration = generation
        await scheduler.cancelAll()
        guard !isSleeping, let date = events.values.map(\.date).min() else { return }
        await scheduler.schedule(at: date) { [weak self] in
            Task {
                guard let self, await self.generation == scheduledGeneration else { return }
                await self.fireDueEvents(reason: .scheduled)
            }
        }
    }

    private func fireDueEvents(reason: TemporalTriggerReason) async {
        let now = clock.now()
        let due = events
            .filter { $0.value.date <= now }
            .sorted {
                if $0.value.date != $1.value.date { return $0.value.date < $1.value.date }
                return $0.value.priority < $1.value.priority
            }
        for (key, event) in due {
            events.removeValue(forKey: key)
            await event.handler(reason)
        }
        await scheduleEarliest()
    }
}
