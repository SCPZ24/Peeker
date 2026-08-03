import Foundation
import PeekerCore

public protocol TimerRepository: Sendable {
    func loadTemplates() async throws -> [TimerTemplate]
    func saveTemplate(_ template: TimerTemplate) async throws
    func deleteTemplate(id: UUID) async throws
    func loadOrCreateDay(_ day: BusinessDay) async throws -> TimerDayState
    func saveDay(_ state: TimerDayState) async throws
    func beginSession(_ session: TimerSession) async throws
    func commitStart(state: TimerDayState, session: TimerSession) async throws
    func completeSession(_ completion: TimerSessionCompletion) async throws
    func interruptSession(_ interruption: TimerSessionInterruption) async throws
    func commitCompletion(state: TimerDayState, completion: TimerSessionCompletion) async throws
    func saveSnapshot(_ snapshot: TimerDailySnapshot) async throws
    func loadSnapshots(from startMilliseconds: Int64, to endMilliseconds: Int64) async throws -> [TimerDailySnapshot]
}
