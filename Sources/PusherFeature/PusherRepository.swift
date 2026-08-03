import Foundation
import PeekerCore

public protocol PusherRepository: Sendable {
    func loadOrCreateDay(_ day: BusinessDay) async throws -> PusherBoard
    func saveBoard(_ board: PusherBoard) async throws
    func insertTask(_ task: PusherTask, at index: Int) async throws
    func updateTask(_ task: PusherTask) async throws
    func deleteTask(id: UUID) async throws
    func reorderTasks(businessDayID: BusinessDayID, orderedTasks: [PusherTask]) async throws
    func saveSnapshot(_ snapshot: PusherDailySnapshot) async throws
    func loadSnapshots(from startMilliseconds: Int64, to endMilliseconds: Int64) async throws -> [PusherDailySnapshot]
}
