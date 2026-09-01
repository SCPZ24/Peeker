import Foundation
import PeekerCore

public protocol TimerRepository: Sendable {
    func loadOrBootstrapCurrentDay(resolvedToday: BusinessDay) async throws -> TimerDayState
    func advanceDay(_ transition: TimerDayTransition) async throws -> TimerDayState
    func updateCurrentBusinessDay(_ day: BusinessDay) async throws
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
    func loadSnapshots(from startMilliseconds: Int64, to endMilliseconds: Int64) async throws -> [TimerDailySnapshot]
    func loadTemporaryTasks() async throws -> [TimerTemporaryTask]
    func saveTemporaryTask(_ task: TimerTemporaryTask) async throws
    func archiveTemporaryTask(
        _ task: TimerTemporaryTask,
        completion: TimerSessionCompletion?,
        reason: TimerTemporaryArchiveReason,
        atMilliseconds: Int64
    ) async throws
    func commitTemporaryStart(state: TimerDayState, task: TimerTemporaryTask, session: TimerSession) async throws
    func commitTemporaryCompletion(
        state: TimerDayState,
        task: TimerTemporaryTask,
        completion: TimerSessionCompletion
    ) async throws
}

public extension TimerRepository {
    func loadTemporaryTasks() async throws -> [TimerTemporaryTask] { [] }
    func saveTemporaryTask(_ task: TimerTemporaryTask) async throws { throw TimerDomainError.taskNotFound }
    func archiveTemporaryTask(
        _ task: TimerTemporaryTask,
        completion: TimerSessionCompletion?,
        reason: TimerTemporaryArchiveReason,
        atMilliseconds: Int64
    ) async throws { throw TimerDomainError.taskNotFound }
    func commitTemporaryStart(
        state: TimerDayState,
        task: TimerTemporaryTask,
        session: TimerSession
    ) async throws { throw TimerDomainError.taskNotFound }
    func commitTemporaryCompletion(
        state: TimerDayState,
        task: TimerTemporaryTask,
        completion: TimerSessionCompletion
    ) async throws { throw TimerDomainError.taskNotFound }
}
