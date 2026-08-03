import Foundation
import Observation
import SwiftUI
import PeekerCore

@MainActor
@Observable
public final class PusherStore {
    public private(set) var board: PusherBoard?
    public private(set) var snapshots: [PusherDailySnapshot] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var carryIncomplete: Bool
    public var refreshTime: RefreshTime

    @ObservationIgnored private let repository: any PusherRepository
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let resolver: BusinessDayResolver
    @ObservationIgnored private let eventHub: TemporalEventHub
    @ObservationIgnored private let onRefreshTimeChanged: @MainActor (RefreshTime) -> Void
    @ObservationIgnored private let onCarryIncompleteChanged: @MainActor (Bool) -> Void
    private let boundaryKey = TemporalEventKey("pusher.boundary")

    public init(
        repository: any PusherRepository,
        clock: any Clock,
        resolver: BusinessDayResolver,
        eventHub: TemporalEventHub,
        carryIncomplete: Bool = true,
        refreshTime: RefreshTime = .midnight,
        onRefreshTimeChanged: @escaping @MainActor (RefreshTime) -> Void = { _ in },
        onCarryIncompleteChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.repository = repository
        self.clock = clock
        self.resolver = resolver
        self.eventHub = eventHub
        self.carryIncomplete = carryIncomplete
        self.refreshTime = refreshTime
        self.onRefreshTimeChanged = onRefreshTimeChanged
        self.onCarryIncompleteChanged = onCarryIncompleteChanged
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let day = resolver.businessDay(
                containing: clock.now(),
                featureID: .pusher,
                refreshTime: refreshTime
            )
            board = try await repository.loadOrCreateDay(day)
            snapshots = try await repository.loadSnapshots(
                from: clock.now().addingTimeInterval(-370 * 86_400).millisecondsSince1970,
                to: clock.now().addingTimeInterval(32 * 86_400).millisecondsSince1970
            )
            try await recoverThroughNow()
            await scheduleBoundary()
            errorMessage = nil
        } catch {
            errorMessage = "Pusher 无法载入：\(error.localizedDescription)"
        }
    }

    public func create(title: String, urgency: PusherUrgency, repeatsDaily: Bool) async -> Bool {
        guard var current = board else { return false }
        let old = current
        do {
            var task = try PusherTask(
                title: title,
                urgency: urgency,
                businessDayID: current.businessDay.id
            )
            task.setRepeatsDaily(repeatsDaily)
            try current.insert(task)
            board = current
            try await repository.saveBoard(current)
            errorMessage = nil
            return true
        } catch {
            board = old
            errorMessage = "无法创建任务：\(error.localizedDescription)"
            return false
        }
    }

    public func update(
        taskID: UUID,
        title: String,
        urgency: PusherUrgency,
        repeatsDaily: Bool
    ) async -> Bool {
        guard var current = board,
              var task = current.allTasks.first(where: { $0.id == taskID }) else { return false }
        let old = current
        do {
            let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { throw PusherDomainError.blankTitle }
            task.title = normalized
            task.urgency = urgency
            task.setRepeatsDaily(repeatsDaily)
            task.updatedAtMilliseconds = clock.now().millisecondsSince1970
            try current.update(task)
            board = current
            try await repository.saveBoard(current)
            errorMessage = nil
            return true
        } catch {
            board = old
            errorMessage = "无法编辑任务：\(error.localizedDescription)"
            return false
        }
    }

    public func delete(taskID: UUID) async -> Bool {
        guard var current = board else { return false }
        let old = current
        do {
            try current.remove(taskID: taskID)
            board = current
            try await repository.deleteTask(id: taskID)
            errorMessage = nil
            return true
        } catch {
            board = old
            errorMessage = "无法删除任务：\(error.localizedDescription)"
            return false
        }
    }

    public func move(taskID: UUID, to status: PusherStatus, at position: Int) async -> Bool {
        guard var current = board else { return false }
        let old = current
        do {
            try current.move(taskID: taskID, to: status, at: position)
            board = current
            try await repository.reorderTasks(
                businessDayID: current.businessDay.id,
                orderedTasks: current.allTasks
            )
            errorMessage = nil
            return true
        } catch {
            board = old
            errorMessage = "无法移动任务，已恢复原位置：\(error.localizedDescription)"
            return false
        }
    }

    public func updateRefreshTime(_ refreshTime: RefreshTime) async {
        self.refreshTime = refreshTime
        onRefreshTimeChanged(refreshTime)
        await scheduleBoundary()
    }

    public func updateCarryIncomplete(_ enabled: Bool) {
        carryIncomplete = enabled
        onCarryIncompleteChanged(enabled)
    }

    public func handleWake() async {
        do {
            try await recoverThroughNow()
            await scheduleBoundary()
        } catch {
            errorMessage = "Pusher 跨日恢复失败：\(error.localizedDescription)"
        }
    }

    private func recoverThroughNow() async throws {
        guard var current = board else { return }
        let now = clock.now().millisecondsSince1970
        while current.businessDay.end.millisecondsSince1970 <= now {
            let boundary = current.businessDay.end.millisecondsSince1970
            let nextDay = resolver.businessDay(
                startingAtBoundary: Date(millisecondsSince1970: boundary),
                featureID: .pusher,
                refreshTime: refreshTime
            )
            let settlement = PusherSettlement.settle(
                current,
                into: nextDay,
                carryIncomplete: carryIncomplete,
                atMilliseconds: boundary
            )
            try await repository.saveSnapshot(settlement.snapshot)
            try await repository.saveBoard(settlement.nextBoard)
            current = settlement.nextBoard
        }
        board = current
    }

    private func scheduleBoundary() async {
        await eventHub.set(boundaryKey, at: board?.businessDay.end, priority: 1) { [weak self] in
            await self?.handleWake()
        }
    }
}
