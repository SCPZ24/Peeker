import Foundation
import Observation
import SwiftUI
import PeekerCore

enum PusherMovePreparation {
    case rejected
    case unchanged
    case started(PusherMoveTransaction)
}

@MainActor
@Observable
public final class PusherStore {
    public private(set) var board: PusherBoard?
    public private(set) var snapshots: [PusherDailySnapshot] = []
    public private(set) var isLoading = false
    public private(set) var isMovePending = false
    public private(set) var errorMessage: String?
    public var carryIncomplete: Bool
    public var refreshTime: RefreshTime

    @ObservationIgnored private let repository: any PusherRepository
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let resolver: BusinessDayResolver
    @ObservationIgnored private let eventHub: TemporalEventHub
    @ObservationIgnored private let onRefreshTimeChanged: @MainActor (RefreshTime) -> Void
    @ObservationIgnored private let onCarryIncompleteChanged: @MainActor (Bool) -> Void
    @ObservationIgnored private var pendingMoveID: UUID?
    @ObservationIgnored private var hasDeferredWake = false
    @ObservationIgnored private var isBoardMutationPending = false
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
        guard acquireBoardMutation() else { return }
        isLoading = true
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
        isLoading = false
        await finishBoardMutation()
    }

    public func create(title: String, urgency: PusherUrgency, repeatsDaily: Bool) async -> Bool {
        guard var current = board, acquireBoardMutation() else { return false }
        let old = current
        let succeeded: Bool
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
            succeeded = true
        } catch {
            board = old
            errorMessage = "无法创建任务：\(error.localizedDescription)"
            succeeded = false
        }
        await finishBoardMutation()
        return succeeded
    }

    public func update(
        taskID: UUID,
        title: String,
        urgency: PusherUrgency,
        repeatsDaily: Bool
    ) async -> Bool {
        guard var current = board,
              var task = current.allTasks.first(where: { $0.id == taskID }),
              acquireBoardMutation() else { return false }
        let old = current
        let succeeded: Bool
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
            succeeded = true
        } catch {
            board = old
            errorMessage = "无法编辑任务：\(error.localizedDescription)"
            succeeded = false
        }
        await finishBoardMutation()
        return succeeded
    }

    public func delete(taskID: UUID) async -> Bool {
        guard var current = board, acquireBoardMutation() else { return false }
        let old = current
        let succeeded: Bool
        do {
            try current.remove(taskID: taskID)
            board = current
            try await repository.deleteTask(id: taskID)
            errorMessage = nil
            succeeded = true
        } catch {
            board = old
            errorMessage = "无法删除任务：\(error.localizedDescription)"
            succeeded = false
        }
        await finishBoardMutation()
        return succeeded
    }

    func beginMove(
        taskID: UUID,
        to status: PusherStatus,
        insertionIndex: Int
    ) -> PusherMovePreparation {
        guard let current = board, acquireBoardMutation() else { return .rejected }
        do {
            var moved = current
            try moved.move(taskID: taskID, to: status, at: insertionIndex)
            guard !moved.hasSameTaskPlacement(as: current) else {
                isBoardMutationPending = false
                return .unchanged
            }

            let transaction = PusherMoveTransaction(before: current, after: moved)
            board = moved
            isMovePending = true
            pendingMoveID = transaction.id
            errorMessage = nil
            return .started(transaction)
        } catch {
            isBoardMutationPending = false
            return .rejected
        }
    }

    @discardableResult
    func persistMove(_ transaction: PusherMoveTransaction) async -> Bool {
        guard pendingMoveID == transaction.id else { return false }
        await Task.yield()
        do {
            try await repository.reorderTasks(
                businessDayID: transaction.after.businessDay.id,
                orderedTasks: transaction.after.allTasks
            )
            guard pendingMoveID == transaction.id else { return false }
            errorMessage = nil
            await finishMoveTransaction()
            return true
        } catch {
            guard pendingMoveID == transaction.id else { return false }
            withAnimation(.easeInOut(duration: 0.12)) {
                board = transaction.before
            }
            errorMessage = "无法移动任务，已恢复原位置：\(error.localizedDescription)"
            await finishMoveTransaction()
            return false
        }
    }

    public func move(taskID: UUID, to status: PusherStatus, at position: Int) async -> Bool {
        switch beginMove(
            taskID: taskID,
            to: status,
            insertionIndex: position
        ) {
        case .rejected:
            return false
        case .unchanged:
            return true
        case let .started(transaction):
            return await persistMove(transaction)
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
        guard acquireBoardMutation() else {
            hasDeferredWake = true
            return
        }
        await recoverAndScheduleBoundary()
        await finishBoardMutation()
    }

    private func recoverAndScheduleBoundary() async {
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

    private func finishMoveTransaction() async {
        pendingMoveID = nil
        await finishBoardMutation()
        isMovePending = false
    }

    private func acquireBoardMutation() -> Bool {
        guard !isBoardMutationPending else { return false }
        isBoardMutationPending = true
        return true
    }

    private func finishBoardMutation() async {
        while hasDeferredWake {
            hasDeferredWake = false
            await recoverAndScheduleBoundary()
        }
        isBoardMutationPending = false
    }
}
