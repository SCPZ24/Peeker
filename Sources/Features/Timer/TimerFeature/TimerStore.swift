import Foundation
import Observation
import SwiftUI
import PeekerCore

public enum TimerStatisticsMode: String, CaseIterable, Sendable {
    case progress
    case heatmap
}

@MainActor
@Observable
public final class TimerStore {
    public private(set) var templates: [TimerTemplate] = []
    public private(set) var dayState: TimerDayState?
    public private(set) var snapshots: [TimerDailySnapshot] = []
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var refreshTime: RefreshTime
    public var statisticsMode: TimerStatisticsMode

    @ObservationIgnored private let repository: any TimerRepository
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let resolver: BusinessDayResolver
    @ObservationIgnored private let eventHub: TemporalEventHub
    @ObservationIgnored private let onNaturalCompletion: @MainActor (TimerTaskInstance) -> Void
    @ObservationIgnored private let onRefreshTimeChanged: @MainActor (RefreshTime) -> Void
    @ObservationIgnored private let onStatisticsModeChanged: @MainActor (TimerStatisticsMode) -> Void
    @ObservationIgnored private var loadedSnapshotInterval: DateInterval?
    @ObservationIgnored private var snapshotCache: [BusinessDayID: TimerDailySnapshot] = [:]
    @ObservationIgnored private var snapshotLoadGeneration = 0
    @ObservationIgnored private let mutationGate = TimerMutationGate()

    private let targetKey = TemporalEventKey("timer.target")
    private let boundaryKey = TemporalEventKey("timer.boundary")

    public init(
        repository: any TimerRepository,
        clock: any Clock,
        resolver: BusinessDayResolver,
        eventHub: TemporalEventHub,
        onNaturalCompletion: @escaping @MainActor (TimerTaskInstance) -> Void = { _ in },
        refreshTime: RefreshTime = .midnight,
        statisticsMode: TimerStatisticsMode = .progress,
        onRefreshTimeChanged: @escaping @MainActor (RefreshTime) -> Void = { _ in },
        onStatisticsModeChanged: @escaping @MainActor (TimerStatisticsMode) -> Void = { _ in }
    ) {
        self.repository = repository
        self.clock = clock
        self.resolver = resolver
        self.eventHub = eventHub
        self.onNaturalCompletion = onNaturalCompletion
        self.refreshTime = refreshTime
        self.statisticsMode = statisticsMode
        self.onRefreshTimeChanged = onRefreshTimeChanged
        self.onStatisticsModeChanged = onStatisticsModeChanged
    }

    public func load() async {
        await withMutation { await loadUnlocked() }
    }

    private func loadUnlocked() async {
        isLoading = true
        defer { isLoading = false }
        do {
            templates = try await repository.loadTemplates()
            let day = resolver.businessDay(
                containing: clock.now(),
                featureID: .timer,
                refreshTime: refreshTime
            )
            dayState = try await repository.loadOrBootstrapCurrentDay(resolvedToday: day)
            try await recoverThroughNow(allowPrompt: false)
            try await reloadSnapshots(for: clock.now())
            await scheduleEvents()
            errorMessage = nil
        } catch {
            errorMessage = "Timer 无法载入：\(error.localizedDescription)"
        }
    }

    public func createTemplate(
        name: String,
        targetSeconds: Int64,
        colorHex: String
    ) async {
        await withMutation {
            await createTemplateUnlocked(name: name, targetSeconds: targetSeconds, colorHex: colorHex)
        }
    }

    private func createTemplateUnlocked(
        name: String,
        targetSeconds: Int64,
        colorHex: String
    ) async {
        do {
            try await prepareCurrentDayForMutation()
        } catch {
            return
        }
        do {
            let template = try TimerTemplate(
                name: name,
                targetSeconds: targetSeconds,
                colorHex: colorHex,
                position: templates.count
            )
            try await repository.saveTemplate(template)
            templates.append(template)
            if let current = dayState {
                dayState = try await repository.loadOrCreateDay(current.businessDay)
            }
            errorMessage = nil
        } catch {
            errorMessage = "无法创建计时任务：\(error.localizedDescription)"
        }
    }

    public func updateTemplate(_ template: TimerTemplate) async {
        await withMutation { await updateTemplateUnlocked(template) }
    }

    private func updateTemplateUnlocked(_ template: TimerTemplate) async {
        do {
            try await prepareCurrentDayForMutation()
        } catch {
            return
        }
        if let state = dayState,
           let active = state.activeSession,
           let activeTask = state.tasks.first(where: { $0.id == active.taskID && $0.templateID == template.id }) {
            let elapsed = max(0, clock.now().millisecondsSince1970 - active.startedAtMilliseconds) / 1_000
            if template.targetSeconds <= activeTask.accumulatedSeconds + elapsed {
                try? await pauseUnlocked(reason: .paused)
            }
        }
        let oldTemplates = templates
        let oldState = dayState
        do {
            try await repository.saveTemplate(template)
            if let index = templates.firstIndex(where: { $0.id == template.id }) {
                templates[index] = template
                templates.sort { $0.position < $1.position }
            }
            dayState?.updateTemplate(template)
            if let state = dayState { try await repository.saveDay(state) }
            await scheduleEvents()
            errorMessage = nil
        } catch {
            templates = oldTemplates
            dayState = oldState
            errorMessage = "无法保存计时任务：\(error.localizedDescription)"
        }
    }

    public func deleteTemplate(id: UUID) async {
        await withMutation { await deleteTemplateUnlocked(id: id) }
    }

    private func deleteTemplateUnlocked(id: UUID) async {
        do {
            try await prepareCurrentDayForMutation()
        } catch {
            return
        }
        let oldTemplates = templates
        let oldState = dayState
        do {
            if dayState?.activeSession?.taskID == dayState?.tasks.first(where: { $0.templateID == id })?.id {
                try await pauseUnlocked(reason: .taskDeleted)
            }
            try await repository.deleteTemplate(id: id)
            templates.removeAll { $0.id == id }
            dayState?.tasks.removeAll { $0.templateID == id }
            errorMessage = nil
        } catch {
            templates = oldTemplates
            dayState = oldState
            errorMessage = "无法删除计时任务：\(error.localizedDescription)"
        }
    }

    public func reorderTemplates(fromOffsets: IndexSet, toOffset: Int) async {
        await withMutation {
            await reorderTemplatesUnlocked(fromOffsets: fromOffsets, toOffset: toOffset)
        }
    }

    private func reorderTemplatesUnlocked(fromOffsets: IndexSet, toOffset: Int) async {
        do {
            try await prepareCurrentDayForMutation()
        } catch {
            return
        }
        let old = templates
        templates.move(fromOffsets: fromOffsets, toOffset: toOffset)
        do {
            for index in templates.indices {
                var template = templates[index]
                template.position = index
                template.updatedAtMilliseconds = clock.now().millisecondsSince1970
                templates[index] = template
                try await repository.saveTemplate(template)
                dayState?.updateTemplate(template)
            }
            if let state = dayState { try await repository.saveDay(state) }
        } catch {
            templates = old
            errorMessage = "无法保存任务顺序：\(error.localizedDescription)"
        }
    }

    public func start(taskID: UUID) async {
        await withMutation { await startUnlocked(taskID: taskID) }
    }

    private func startUnlocked(taskID: UUID) async {
        do {
            try await prepareCurrentDayForMutation()
            guard var state = dayState else { return }
            try state.start(taskID: taskID, atMilliseconds: clock.now().millisecondsSince1970)
            guard let session = state.activeSession else { return }
            try await repository.commitStart(state: state, session: session)
            dayState = state
            errorMessage = nil
            await scheduleEvents()
        } catch {
            errorMessage = "无法开始计时：\(error.localizedDescription)"
        }
    }

    public func pause(reason: TimerSessionEndReason = .paused) async throws {
        try await withMutation { try await pauseUnlocked(reason: reason) }
    }

    private func pauseUnlocked(reason: TimerSessionEndReason) async throws {
        do {
            try await prepareCurrentDayForMutation()
            guard var state = dayState else { return }
            guard let completion = try state.pause(
                atMilliseconds: clock.now().millisecondsSince1970,
                reason: reason
            ) else { return }
            try await repository.commitCompletion(state: state, completion: completion)
            dayState = state
            errorMessage = nil
            await scheduleEvents()
        } catch {
            errorMessage = "无法暂停计时：\(error.localizedDescription)"
            throw error
        }
    }

    public var runningTask: TimerTaskInstance? {
        guard let session = dayState?.activeSession else { return nil }
        return dayState?.tasks.first { $0.id == session.taskID && $0.status == .running }
    }

    public func remainingSeconds(for task: TimerTaskInstance, at date: Date = Date()) -> Int64 {
        guard task.status == .running,
              let session = dayState?.activeSession,
              session.taskID == task.id else {
            return task.remainingSeconds
        }
        let elapsed = max(0, date.millisecondsSince1970 - session.startedAtMilliseconds) / 1_000
        return max(0, task.targetSeconds - task.accumulatedSeconds - elapsed)
    }

    public func updateRefreshTime(_ refreshTime: RefreshTime) async {
        await withMutation { await updateRefreshTimeUnlocked(refreshTime) }
    }

    private func updateRefreshTimeUnlocked(_ refreshTime: RefreshTime) async {
        do {
            try await recoverThroughNow(allowPrompt: false)
            if let current = dayState {
                let adjusted = resolver.businessDay(
                    preservingStartOf: current.businessDay,
                    at: clock.now(),
                    refreshTime: refreshTime
                )
                try await repository.updateCurrentBusinessDay(adjusted)
                dayState = TimerDayState(
                    businessDay: adjusted,
                    tasks: current.tasks,
                    activeSession: current.activeSession
                )
            }
            self.refreshTime = refreshTime
            onRefreshTimeChanged(refreshTime)
            await scheduleEvents()
            errorMessage = nil
        } catch {
            errorMessage = "Timer 无法更新刷新时间：\(error.localizedDescription)"
        }
    }

    public func updateStatisticsMode(_ mode: TimerStatisticsMode) {
        statisticsMode = mode
        onStatisticsModeChanged(mode)
    }

    public func loadSnapshots(for displayedMonth: Date) async {
        do {
            try await reloadSnapshots(for: displayedMonth)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = "Timer 月历无法载入：\(error.localizedDescription)"
        }
    }

    public func handleWake() async {
        await handleTemporalEvent(reason: .wakeRecovery)
    }

    public func handleTemporalEvent(reason: TemporalTriggerReason) async {
        await withMutation { await handleTemporalEventUnlocked(reason: reason) }
    }

    private func handleTemporalEventUnlocked(reason: TemporalTriggerReason) async {
        do {
            try await recoverThroughNow(allowPrompt: reason == .scheduled)
            await scheduleEvents()
        } catch {
            errorMessage = "Timer 恢复失败：\(error.localizedDescription)"
        }
    }

    private func recoverThroughNow(allowPrompt: Bool) async throws {
        guard var state = dayState else { return }
        let nowMilliseconds = clock.now().millisecondsSince1970

        while state.businessDay.end.millisecondsSince1970 <= nowMilliseconds {
            let boundary = state.businessDay.end.millisecondsSince1970
            var continuingTemplateID: UUID?
            var completion: TimerSessionCompletion?
            var completedTask: TimerTaskInstance?
            var shouldPromptAfterCommit = false
            if let session = state.activeSession,
               let task = state.tasks.first(where: { $0.id == session.taskID }) {
                let target = session.startedAtMilliseconds + task.remainingSeconds * 1_000
                if target <= boundary {
                    completion = try state.pause(atMilliseconds: target, reason: .targetReached)!
                    completedTask = state.tasks.first(where: { $0.id == task.id })
                    shouldPromptAfterCommit = shouldPublishCompletionPrompt(
                        targetMilliseconds: target,
                        nowMilliseconds: nowMilliseconds,
                        allowPrompt: allowPrompt
                    )
                } else {
                    continuingTemplateID = task.templateID
                    completion = try state.pause(atMilliseconds: boundary, reason: .businessDayBoundary)!
                }
            }

            let snapshot = TimerDailySnapshot(
                businessDayID: state.businessDay.id,
                completionRatio: state.completionRatio,
                completedAtMilliseconds: boundary
            )
            let nextDay = resolver.businessDay(
                startingAtBoundary: Date(millisecondsSince1970: boundary),
                featureID: .timer,
                refreshTime: refreshTime
            )
            state = try await repository.advanceDay(
                TimerDayTransition(
                    settledState: state,
                    completion: completion,
                    snapshot: snapshot,
                    nextDay: nextDay,
                    continuingTemplateID: continuingTemplateID,
                    boundaryMilliseconds: boundary
                )
            )
            dayState = state
            cache(snapshot)
            if shouldPromptAfterCommit, let completedTask { onNaturalCompletion(completedTask) }
        }

        if let session = state.activeSession,
           let task = state.tasks.first(where: { $0.id == session.taskID }) {
            let target = session.startedAtMilliseconds + task.remainingSeconds * 1_000
            if target <= nowMilliseconds {
                let completion = try state.pause(atMilliseconds: target, reason: .targetReached)!
                try await repository.commitCompletion(state: state, completion: completion)
                if shouldPublishCompletionPrompt(
                    targetMilliseconds: target,
                    nowMilliseconds: nowMilliseconds,
                    allowPrompt: allowPrompt
                ), let completedTask = state.tasks.first(where: { $0.id == task.id }) {
                    onNaturalCompletion(completedTask)
                }
            }
        }
        dayState = state
    }

    private func shouldPublishCompletionPrompt(
        targetMilliseconds: Int64,
        nowMilliseconds: Int64,
        allowPrompt: Bool
    ) -> Bool {
        allowPrompt && (0...2_000).contains(nowMilliseconds - targetMilliseconds)
    }

    private func prepareCurrentDayForMutation() async throws {
        do {
            try await recoverThroughNow(allowPrompt: false)
            await scheduleEvents()
        } catch {
            await scheduleEvents()
            errorMessage = "Timer 跨日恢复失败：\(error.localizedDescription)"
            throw error
        }
    }

    private func cache(_ snapshot: TimerDailySnapshot) {
        snapshotCache[snapshot.businessDayID] = snapshot
        let date = Date(millisecondsSince1970: snapshot.businessDayID.startAtMilliseconds)
        guard loadedSnapshotInterval?.contains(date) == true else { return }
        publishCachedSnapshots()
    }

    private func reloadSnapshots(for displayedMonth: Date) async throws {
        let currentStart = dayState?.businessDay.start ?? clock.now()
        let grid = CalendarMonthGrid(
            displaying: displayedMonth,
            currentBusinessDayStart: currentStart
        )
        let interval = grid.snapshotQueryInterval()
        snapshotLoadGeneration += 1
        let generation = snapshotLoadGeneration
        loadedSnapshotInterval = interval
        publishCachedSnapshots()
        let loaded = try await repository.loadSnapshots(
            from: interval.start.millisecondsSince1970,
            to: interval.end.millisecondsSince1970
        )
        try Task.checkCancellation()
        guard generation == snapshotLoadGeneration else { return }
        for snapshot in loaded { snapshotCache[snapshot.businessDayID] = snapshot }
        publishCachedSnapshots()
    }

    private func publishCachedSnapshots() {
        guard let interval = loadedSnapshotInterval else { return }
        snapshots = snapshotCache.values
            .filter {
                interval.contains(Date(millisecondsSince1970: $0.businessDayID.startAtMilliseconds))
            }
            .sorted {
                $0.businessDayID.startAtMilliseconds < $1.businessDayID.startAtMilliseconds
            }
    }

    private func withMutation<T>(
        _ operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        await mutationGate.lock()
        do {
            let value = try await operation()
            await mutationGate.unlock()
            return value
        } catch {
            await mutationGate.unlock()
            throw error
        }
    }

    private func scheduleEvents() async {
        guard let state = dayState else { return }
        await eventHub.set(boundaryKey, at: state.businessDay.end, priority: 1) { [weak self] reason in
            await self?.handleTemporalEvent(reason: reason)
        }

        let targetDate: Date?
        if let session = state.activeSession,
           let task = state.tasks.first(where: { $0.id == session.taskID }) {
            targetDate = Date(
                millisecondsSince1970: session.startedAtMilliseconds + task.remainingSeconds * 1_000
            )
        } else {
            targetDate = nil
        }
        await eventHub.set(targetKey, at: targetDate, priority: 0) { [weak self] reason in
            await self?.handleTemporalEvent(reason: reason)
        }
    }
}

private actor TimerMutationGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func unlock() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
