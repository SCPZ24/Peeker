import Foundation
import PeekerCore
import TimerFeature
import PusherFeature

struct StartupPersistenceError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

final class UnavailableTimerRepository: TimerRepository, Sendable {
    private let error: StartupPersistenceError
    init(error: StartupPersistenceError) { self.error = error }
    func loadTemplates() async throws -> [TimerTemplate] { throw error }
    func saveTemplate(_ template: TimerTemplate) async throws { throw error }
    func deleteTemplate(id: UUID) async throws { throw error }
    func loadOrCreateDay(_ day: BusinessDay) async throws -> TimerDayState { throw error }
    func saveDay(_ state: TimerDayState) async throws { throw error }
    func beginSession(_ session: TimerSession) async throws { throw error }
    func commitStart(state: TimerDayState, session: TimerSession) async throws { throw error }
    func completeSession(_ completion: TimerSessionCompletion) async throws { throw error }
    func interruptSession(_ interruption: TimerSessionInterruption) async throws { throw error }
    func commitCompletion(state: TimerDayState, completion: TimerSessionCompletion) async throws { throw error }
    func saveSnapshot(_ snapshot: TimerDailySnapshot) async throws { throw error }
    func loadSnapshots(from startMilliseconds: Int64, to endMilliseconds: Int64) async throws -> [TimerDailySnapshot] { throw error }
}

final class UnavailablePusherRepository: PusherRepository, Sendable {
    private let error: StartupPersistenceError
    init(error: StartupPersistenceError) { self.error = error }
    func loadOrCreateDay(_ day: BusinessDay) async throws -> PusherBoard { throw error }
    func saveBoard(_ board: PusherBoard) async throws { throw error }
    func insertTask(_ task: PusherTask, at index: Int) async throws { throw error }
    func updateTask(_ task: PusherTask) async throws { throw error }
    func deleteTask(id: UUID) async throws { throw error }
    func reorderTasks(businessDayID: BusinessDayID, orderedTasks: [PusherTask]) async throws { throw error }
    func saveSnapshot(_ snapshot: PusherDailySnapshot) async throws { throw error }
    func loadSnapshots(from startMilliseconds: Int64, to endMilliseconds: Int64) async throws -> [PusherDailySnapshot] { throw error }
}
