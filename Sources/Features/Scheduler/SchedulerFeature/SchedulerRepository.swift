import Foundation

public struct SchedulerImportCommit: Sendable {
    public let source: SchedulerSource
    public let created: Int
    public let updated: Int
    public let deleted: Int
    public let skipped: Int

    public init(source: SchedulerSource, created: Int, updated: Int, deleted: Int, skipped: Int) {
        self.source=source; self.created=created; self.updated=updated; self.deleted=deleted; self.skipped=skipped
    }
}

public struct SchedulerSnapshot: Sendable {
    public let events: [SchedulerEvent]
    public let overrides: [SchedulerOccurrenceOverride]
    public init(events: [SchedulerEvent], overrides: [SchedulerOccurrenceOverride]) { self.events=events; self.overrides=overrides }
}

public protocol SchedulerRepository: Sendable {
    func snapshot() async throws -> SchedulerSnapshot
    func event(id: UUID) async throws -> SchedulerEvent?
    func save(_ event: SchedulerEvent) async throws -> SchedulerEvent
    func deleteEvent(id: UUID) async throws -> Bool
    func saveOverride(_ override: SchedulerOccurrenceOverride) async throws
    func deleteOverrides(eventID: UUID, fromKey: String?) async throws -> Int
    func sources() async throws -> [SchedulerSource]
    func source(id: UUID) async throws -> SchedulerSource?
    func saveSource(_ source: SchedulerSource) async throws
    func removeSource(id: UUID) async throws -> Int
    func replaceSource(
        _ source: SchedulerSource,
        series: [SchedulerImportedSeries],
        protectedUIDs: Set<String>
    ) async throws -> SchedulerImportCommit
}
