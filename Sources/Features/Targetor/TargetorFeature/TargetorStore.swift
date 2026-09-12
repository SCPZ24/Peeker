import Foundation
import Observation
import PeekerCore

public struct TargetorFeedback: Equatable, Sendable {
    public let targetID: UUID
    public let state: TargetorCheckinState
    public let token: UUID
    let startedAt: Date
}

@MainActor
@Observable
public final class TargetorStore {
    public var isPresentationVisible = false
    public var reduceMotion = false
    public private(set) var targets: [TargetorTargetState] = []
    public private(set) var issues: [String] = []
    public private(set) var isLoading = false
    private var localizedError: LocalizedMessage?
    public var errorMessage: String? { localizedError?.diagnosticDescription }
    public var localizedErrorMessage: String? { localizedError?.resolve() }
    public private(set) var feedback: TargetorFeedback?
    public private(set) var calendarRevision = 0
    public var refreshTime: RefreshTime

    @ObservationIgnored private let repository: any TargetorRepository
    @ObservationIgnored private let clock: any Clock
    @ObservationIgnored private let resolver: TargetorPeriodResolver
    @ObservationIgnored private let eventHub: TemporalEventHub
    @ObservationIgnored private let isValidIcon: @Sendable (String) -> Bool
    @ObservationIgnored private let publishCheckin: @MainActor (TargetorCheckinResult) -> Void
    @ObservationIgnored private let onRefreshTimeChanged: @MainActor (RefreshTime) -> Void
    @ObservationIgnored private let gate = TargetorMutationGate()
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?
    @ObservationIgnored private var summaryHistoryCache: [UUID: SummaryHistoryEntry] = [:]
    @ObservationIgnored private var summaryHistoryOrder: [UUID] = []
    private let boundaryKey = TemporalEventKey("targetor.boundary")

    public init(
        repository: any TargetorRepository,
        clock: any Clock,
        resolver: TargetorPeriodResolver = TargetorPeriodResolver(),
        eventHub: TemporalEventHub,
        refreshTime: RefreshTime = .midnight,
        isValidIcon: @escaping @Sendable (String) -> Bool,
        publishCheckin: @escaping @MainActor (TargetorCheckinResult) -> Void = { _ in },
        onRefreshTimeChanged: @escaping @MainActor (RefreshTime) -> Void = { _ in }
    ) {
        self.repository = repository
        self.clock = clock
        self.resolver = resolver
        self.eventHub = eventHub
        self.refreshTime = refreshTime
        self.isValidIcon = isValidIcon
        self.publishCheckin = publishCheckin
        self.onRefreshTimeChanged = onRefreshTimeChanged
    }

    deinit { feedbackTask?.cancel() }

    public func load() async {
        await withMutation {
            isLoading = true
            defer { isLoading = false }
            do {
                try await recoverAndReload()
                localizedError = nil
            } catch {
                localizedError = L10n.message("Targetor 无法载入：%1$@", String(describing: error.localizedDescription))
            }
        }
    }

    @discardableResult
    public func create(
        title: String,
        description: String?,
        iconName: String,
        periodRule: TargetorPeriodRule,
        maxCount: Int
    ) async throws -> TargetorTargetState {
        try await withMutation {
            try await recoverAndReload()
            guard isValidIcon(iconName) else { throw TargetorError.invalidIcon }
            let now = clock.now().millisecondsSince1970
            let target = try TargetorTarget(
                title: title, description: description, iconName: iconName,
                periodRule: periodRule, maxCount: maxCount, position: targets.count,
                createdAtMilliseconds: now, updatedAtMilliseconds: now
            )
            let period = TargetorPeriod(
                targetID: target.id, sequence: 0, startMilliseconds: now,
                endMilliseconds: resolver.nextBoundary(
                    after: Date(millisecondsSince1970: now), rule: periodRule, refreshTime: refreshTime
                ).millisecondsSince1970,
                ruleSnapshot: periodRule, maxCountSnapshot: maxCount,
                createdAtMilliseconds: now
            )
            try await repository.create(target: target, firstPeriod: period)
            try await reload()
            return targets.first(where: { $0.id == target.id })!
        }
    }

    @discardableResult
    public func update(
        targetID: UUID,
        title: String,
        description: String?,
        iconName: String,
        periodRule: TargetorPeriodRule,
        maxCount: Int
    ) async throws -> TargetorTargetState {
        try await withMutation {
            try await recoverAndReload()
            guard let existing = targets.first(where: { $0.id == targetID }) else { throw TargetorError.targetNotFound }
            guard isValidIcon(iconName) else { throw TargetorError.invalidIcon }
            let now = clock.now().millisecondsSince1970
            let target = try TargetorTarget(
                id: existing.target.id, title: title, description: description,
                iconName: iconName, periodRule: periodRule, maxCount: maxCount,
                position: existing.target.position,
                createdAtMilliseconds: existing.target.createdAtMilliseconds,
                updatedAtMilliseconds: now,
                archivedAtMilliseconds: existing.target.archivedAtMilliseconds
            )
            guard target != existing.target else { throw TargetorError.noActualChange }
            let ruleChanged = periodRule != existing.target.periodRule
            let replacement: TargetorPeriod?
            if ruleChanged {
                let sequence = (existing.currentPeriod ?? existing.lastPeriod)?.sequence ?? -1
                replacement = TargetorPeriod(
                    targetID: targetID, sequence: sequence + 1,
                    startMilliseconds: now,
                    endMilliseconds: resolver.nextBoundary(
                        after: Date(millisecondsSince1970: now), rule: periodRule, refreshTime: refreshTime
                    ).millisecondsSince1970,
                    ruleSnapshot: periodRule, maxCountSnapshot: maxCount,
                    createdAtMilliseconds: now
                )
            } else { replacement = nil }
            try await repository.update(
                target: target,
                replacingCurrentWith: replacement,
                settleAtMilliseconds: ruleChanged ? now : nil
            )
            try await reload()
            return targets.first(where: { $0.id == targetID })!
        }
    }

    @discardableResult
    public func archive(targetID: UUID) async throws -> TargetorTargetState {
        try await withMutation {
            try await recoverAndReload()
            let archived = try await repository.archive(
                targetID: targetID, atMilliseconds: clock.now().millisecondsSince1970
            )
            try await reload()
            return archived
        }
    }

    public func reorder(targetIDs: [UUID]) async throws {
        try await withMutation {
            try await recoverAndReload()
            try await repository.reorder(
                activeTargetIDs: targetIDs,
                atMilliseconds: clock.now().millisecondsSince1970
            )
            try await reload()
        }
    }

    @discardableResult
    public func checkin(targetID: UUID, expectedPeriodID: UUID? = nil, fromUI: Bool = false) async throws -> TargetorCheckinResult {
        try await withMutation {
            try await recoverAndReload()
            guard let state = targets.first(where: { $0.id == targetID }),
                  let period = state.currentPeriod
            else { throw TargetorError.targetNotFound }
            if let expectedPeriodID, expectedPeriodID != period.id { throw TargetorError.eventNotCurrent }
            let result = try await repository.checkin(
                targetID: targetID, eventID: UUID(), atMilliseconds: clock.now().millisecondsSince1970
            )
            if let index = targets.firstIndex(where: { $0.id == targetID }) { targets[index] = result.target }
            localizedError = nil
            do { try await reload() }
            catch { localizedError = L10n.message("打卡已保存，刷新失败；请刷新视图，不要重复打卡：%1$@", String(describing: error.localizedDescription)) }
            if fromUI && isPresentationVisible { publishFeedback(result) }
            else { publishCheckin(result) }
            return result
        }
    }

    @discardableResult
    func checkinFromUI(targetID: UUID, expectedPeriodID: UUID) async -> Bool {
        do {
            _ = try await checkin(targetID: targetID, expectedPeriodID: expectedPeriodID, fromUI: true)
            return true
        } catch {
            localizedError = LocalizedMessage("无法打卡：%1$@", bundle: L10n.resourceBundle, arguments: [.message(checkinErrorMessage(error))])
            return false
        }
    }

    @discardableResult
    public func uncheck(eventID: UUID) async throws -> TargetorTargetState {
        try await withMutation {
            try await recoverAndReload()
            let result = try await repository.uncheck(eventID: eventID)
            try await reload()
            return result
        }
    }

    public func list(scope: TargetorArchiveScope = .active) async throws -> [TargetorTargetState] {
        try await withMutation {
            try await recoverAndReload()
            if case .active = scope { return targets }
            return try await repository.snapshot(scope: scope).targets
        }
    }

    public func resolve(id: UUID?, title: String?, includeArchived: Bool = false) async throws -> TargetorTargetState {
        let scope: TargetorArchiveScope = includeArchived ? .all : .active
        let values = try await list(scope: scope)
        if let id {
            guard let value = values.first(where: { $0.id == id }) else { throw TargetorError.targetNotFound }
            return value
        }
        let normalized = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else { throw TargetorError.targetNotFound }
        let matches = values.filter { $0.target.title == normalized }
        guard !matches.isEmpty else { throw TargetorError.targetNotFound }
        guard matches.count == 1 else { throw TargetorError.ambiguousSelector(matches.map(\.id)) }
        return matches[0]
    }

    public func history(
        targetID: UUID,
        from: Date? = nil,
        to: Date? = nil
    ) async throws -> TargetorHistory {
        try await withMutation {
            try await recoverAndReload()
            guard (from == nil) == (to == nil) else { throw TargetorError.invalidHistoryRange }
            if let from, let to, to <= from { throw TargetorError.invalidHistoryRange }
            return try await repository.history(
                targetID: targetID,
                fromMilliseconds: from?.millisecondsSince1970,
                toMilliseconds: to?.millisecondsSince1970
            )
        }
    }

    public func summaryCalendar() async throws -> [TargetorCalendarCell] {
        try await withMutation {
            try await recoverAndReload()
            let now = clock.now()
            let dates = TargetorCalendarCalculator.nineWeekDates(
                containing: now, calendar: resolver.calendar
            )
            let intervals = dates.map {
                resolver.dayInterval(startingOnLocalDate: $0, refreshTime: refreshTime)
            }
            guard let from = intervals.map(\.start).min(),
                  let to = intervals.map(\.end).max()
            else { return [] }
            let allStates = try await repository.snapshot(scope: .all).targets
            let allTargets = allStates.map(\.target)
            var periods: [TargetorPeriod] = []
            let fromMS = from.millisecondsSince1970, toMS = to.millisecondsSince1970
            for state in allStates {
                if let cached = summaryHistoryCache[state.id], cached.state == state,
                   cached.from == fromMS, cached.to == toMS {
                    periods.append(contentsOf: cached.periods)
                    continue
                }
                let history = try await repository.history(targetID: state.id, fromMilliseconds: fromMS, toMilliseconds: toMS)
                periods.append(contentsOf: history.periods)
                summaryHistoryCache[state.id] = SummaryHistoryEntry(state: state, from: fromMS, to: toMS, periods: history.periods)
                summaryHistoryOrder.removeAll { $0 == state.id }
                summaryHistoryOrder.append(state.id)
                if summaryHistoryOrder.count > 64 {
                    summaryHistoryCache.removeValue(forKey: summaryHistoryOrder.removeFirst())
                }
            }
            return TargetorCalendarCalculator.aggregate(
                dates: dates, now: now, refreshTime: refreshTime,
                targets: allTargets, periods: periods, resolver: resolver
            )
        }
    }

    func targetCalendar(targetID: UUID) async throws -> TargetorTargetCalendarSnapshot {
        try await withMutation {
            try await recoverAndReload()
            guard let state = targets.first(where: { $0.id == targetID }) else {
                throw TargetorError.targetNotFound
            }
            let now = clock.now()
            let window = TargetorCalendarCalculator.targetWindow(
                frequency: state.target.periodRule.frequency,
                containing: now,
                offset: 0,
                refreshTime: refreshTime,
                resolver: resolver
            )
            let history = try await repository.history(
                targetID: targetID,
                fromMilliseconds: window.queryInterval.start.millisecondsSince1970,
                toMilliseconds: window.queryInterval.end.millisecondsSince1970
            )
            return TargetorCalendarCalculator.targetSnapshot(
                target: state.target,
                periods: history.periods,
                now: now,
                window: window
            )
        }
    }

    public func updateRefreshTime(_ value: RefreshTime) async throws {
        try await withMutation {
            try await recoverAndReload()
            refreshTime = value
            calendarRevision += 1
            onRefreshTimeChanged(value)
            await scheduleBoundary()
        }
    }

    public func handleTemporalEvent() async {
        await withMutation {
            calendarRevision += 1
            do {
                try await recoverAndReload()
                localizedError = nil
            } catch {
                localizedError = L10n.message("Targetor 周期恢复失败：%1$@", String(describing: error.localizedDescription))
            }
        }
    }

    private func recoverAndReload() async throws {
        try await repository.recover(now: clock.now(), refreshTime: refreshTime, resolver: resolver)
        try await reload()
        await scheduleBoundary()
    }

    private func reload() async throws {
        let snapshot = try await repository.snapshot(scope: .active)
        targets = snapshot.targets.sorted { $0.target.position < $1.target.position }
        issues = snapshot.issues
    }

    private func scheduleBoundary() async {
        let next = targets.compactMap(\.currentPeriod).map { Date(millisecondsSince1970: $0.endMilliseconds) }.min()
        await eventHub.set(boundaryKey, at: next, priority: 0) { [weak self] _ in
            await self?.handleTemporalEvent()
        }
    }

    private func checkinErrorMessage(_ error: Error) -> LocalizedMessage {
        guard let targetorError = error as? TargetorError else { return L10n.message("%1$@", error.localizedDescription) }
        switch targetorError {
        case .cycleComplete:
            return L10n.message("本周期已完成")
        case .eventNotCurrent:
            return L10n.message("目标周期已更新，请重新拖拽")
        case .targetNotFound, .targetArchived:
            return L10n.message("目标已不可用")
        case .invalidTitle, .invalidIcon, .invalidPeriod, .invalidMaxCount,
             .ambiguousSelector, .eventNotFound, .invalidHistoryRange, .noActualChange:
            return L10n.message("请求无效")
        }
    }

    private func publishFeedback(_ result: TargetorCheckinResult) {
        guard result.target.currentPeriod?.state != .notStarted, feedback?.token != result.event.id else { return }
        feedbackTask?.cancel()
        let value = TargetorFeedback(
            targetID: result.target.id,
            state: result.target.currentPeriod?.state ?? .notStarted,
            token: result.event.id,
            startedAt: clock.now()
        )
        feedback = value
        let duration = reduceMotion ? 0.15 : TargetorFeedbackAnimation.duration(for: value.state)
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, self?.feedback?.token == value.token else { return }
            self?.feedback = nil
        }
    }

    private func withMutation<T>(_ operation: @MainActor () async throws -> T) async rethrows -> T {
        await gate.lock()
        defer { Task { await gate.unlock() } }
        return try await operation()
    }
}

private actor TargetorMutationGate {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        guard locked else { locked = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func unlock() {
        if waiters.isEmpty { locked = false }
        else { waiters.removeFirst().resume() }
    }
}

private struct SummaryHistoryEntry {
    let state: TargetorTargetState
    let from: Int64
    let to: Int64
    let periods: [TargetorPeriod]
}
