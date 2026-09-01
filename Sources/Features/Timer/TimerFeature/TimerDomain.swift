import Foundation
import PeekerCore

public enum TimerDomainError: Error, Equatable {
    case blankName
    case targetOutOfRange
    case taskNotFound
    case anotherTaskIsRunning
    case taskCompleted
    case noActiveSession
    case invalidPresetColor
    case temporaryCreationDisabled
}

public struct TimerTemplate: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var targetSeconds: Int64
    public var colorHex: String
    public var position: Int
    public var updatedAtMilliseconds: Int64

    public init(
        id: UUID = UUID(),
        name: String,
        targetSeconds: Int64,
        colorHex: String,
        position: Int,
        updatedAtMilliseconds: Int64 = Date().millisecondsSince1970
    ) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw TimerDomainError.blankName }
        guard (1...86_399).contains(targetSeconds) else { throw TimerDomainError.targetOutOfRange }
        self.id = id
        self.name = normalizedName
        self.targetSeconds = targetSeconds
        self.colorHex = colorHex
        self.position = position
        self.updatedAtMilliseconds = updatedAtMilliseconds
    }
}

public enum TimerTaskStatus: String, Codable, Equatable, Sendable {
    case idle
    case running
    case paused
    case completed
}

public enum TimerTaskKind: String, Codable, Equatable, Sendable {
    case daily
    case temporary
}

public enum TimerTaskIdentity: Codable, Equatable, Hashable, Sendable {
    case daily(instanceID: UUID)
    case temporary(taskID: UUID)

    public var kind: TimerTaskKind {
        switch self { case .daily: .daily; case .temporary: .temporary }
    }

    public var taskID: UUID {
        switch self { case let .daily(id), let .temporary(id): id }
    }
}

public enum TimerTemporaryArchiveReason: String, Codable, Equatable, Sendable {
    case expiredAtBoundary
    case completedAtBoundary
    case deleted
}

public struct TimerTemporaryTask: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var targetSeconds: Int64
    public var colorHex: String
    public var accumulatedSeconds: Int64
    public var status: TimerTaskStatus
    public var expireOnRefresh: Bool
    public let createdAtMilliseconds: Int64
    public var updatedAtMilliseconds: Int64
    public var archivedAtMilliseconds: Int64?
    public var archiveReason: TimerTemporaryArchiveReason?

    public init(
        id: UUID = UUID(), name: String, targetSeconds: Int64, colorHex: String,
        accumulatedSeconds: Int64 = 0, status: TimerTaskStatus = .idle,
        expireOnRefresh: Bool = false,
        createdAtMilliseconds: Int64 = Date().millisecondsSince1970,
        updatedAtMilliseconds: Int64 = Date().millisecondsSince1970,
        archivedAtMilliseconds: Int64? = nil,
        archiveReason: TimerTemporaryArchiveReason? = nil
    ) throws {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw TimerDomainError.blankName }
        guard (1...86_399).contains(targetSeconds) else { throw TimerDomainError.targetOutOfRange }
        guard PeekerPresetColor(rawValue: colorHex.uppercased()) != nil else { throw TimerDomainError.invalidPresetColor }
        self.id = id
        self.name = normalizedName
        self.targetSeconds = targetSeconds
        self.colorHex = colorHex.uppercased()
        self.accumulatedSeconds = min(max(0, accumulatedSeconds), targetSeconds)
        self.status = self.accumulatedSeconds >= targetSeconds ? .completed : status
        self.expireOnRefresh = expireOnRefresh
        self.createdAtMilliseconds = createdAtMilliseconds
        self.updatedAtMilliseconds = updatedAtMilliseconds
        self.archivedAtMilliseconds = archivedAtMilliseconds
        self.archiveReason = archiveReason
    }

    public var remainingSeconds: Int64 { max(0, targetSeconds - accumulatedSeconds) }
}

public struct TimerTaskInstance: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let templateID: UUID
    public let businessDayID: BusinessDayID
    public var name: String
    public var targetSeconds: Int64
    public var colorHex: String
    public var position: Int
    public var accumulatedSeconds: Int64
    public var status: TimerTaskStatus
    public var lastActionAtMilliseconds: Int64?
    public var isVisible: Bool

    public init(
        id: UUID = UUID(),
        template: TimerTemplate,
        businessDayID: BusinessDayID,
        accumulatedSeconds: Int64 = 0,
        status: TimerTaskStatus = .idle,
        lastActionAtMilliseconds: Int64? = nil,
        isVisible: Bool = true
    ) throws {
        self.id = id
        self.templateID = template.id
        self.businessDayID = businessDayID
        self.name = template.name
        self.targetSeconds = template.targetSeconds
        self.colorHex = template.colorHex
        self.position = template.position
        self.accumulatedSeconds = min(max(0, accumulatedSeconds), template.targetSeconds)
        self.status = self.accumulatedSeconds >= template.targetSeconds ? .completed : status
        self.lastActionAtMilliseconds = lastActionAtMilliseconds
        self.isVisible = isVisible
    }

    public var remainingSeconds: Int64 {
        max(0, targetSeconds - accumulatedSeconds)
    }
}

public enum TimerSessionEndReason: String, Codable, Equatable, Sendable {
    case paused
    case targetReached
    case businessDayBoundary
    case taskDeleted
}

public struct TimerSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let taskID: UUID
    public let taskKind: TimerTaskKind
    public let businessDayID: BusinessDayID
    public let startedAtMilliseconds: Int64

    public var identity: TimerTaskIdentity {
        taskKind == .daily ? .daily(instanceID: taskID) : .temporary(taskID: taskID)
    }

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        taskKind: TimerTaskKind = .daily,
        businessDayID: BusinessDayID,
        startedAtMilliseconds: Int64
    ) {
        self.id = id
        self.taskID = taskID
        self.taskKind = taskKind
        self.businessDayID = businessDayID
        self.startedAtMilliseconds = startedAtMilliseconds
    }
}

public struct TimerSessionCompletion: Codable, Equatable, Sendable {
    public let session: TimerSession
    public let endedAtMilliseconds: Int64
    public let creditedSeconds: Int64
    public let endReason: TimerSessionEndReason

    public init(
        session: TimerSession,
        endedAtMilliseconds: Int64,
        creditedSeconds: Int64,
        endReason: TimerSessionEndReason
    ) {
        self.session = session
        self.endedAtMilliseconds = endedAtMilliseconds
        self.creditedSeconds = creditedSeconds
        self.endReason = endReason
    }
}

public typealias TimerSessionInterruption = TimerSessionCompletion

public struct TimerDayState: Codable, Equatable, Sendable {
    public let businessDay: BusinessDay
    public var tasks: [TimerTaskInstance]
    public var temporaryTasks: [TimerTemporaryTask]
    public private(set) var activeSession: TimerSession?

    public init(
        businessDay: BusinessDay,
        tasks: [TimerTaskInstance],
        temporaryTasks: [TimerTemporaryTask] = [],
        activeSession: TimerSession? = nil
    ) {
        self.businessDay = businessDay
        self.tasks = tasks.sorted { $0.position < $1.position }
        self.temporaryTasks = temporaryTasks
            .filter { $0.archivedAtMilliseconds == nil }
            .sorted { ($0.createdAtMilliseconds, $0.id.uuidString) < ($1.createdAtMilliseconds, $1.id.uuidString) }
        self.activeSession = activeSession
    }

    public var visibleTasks: [TimerTaskInstance] {
        tasks.filter(\.isVisible).sorted { $0.position < $1.position }
    }

    public var activeTemporaryTasks: [TimerTemporaryTask] {
        temporaryTasks.filter { $0.archivedAtMilliseconds == nil }
            .sorted { ($0.createdAtMilliseconds, $0.id.uuidString) < ($1.createdAtMilliseconds, $1.id.uuidString) }
    }

    public var completionRatio: Double? {
        let dailyTarget = visibleTasks.reduce(Int64(0)) { $0 + $1.targetSeconds }
        let temporaryTarget = activeTemporaryTasks.reduce(Int64(0)) { $0 + $1.targetSeconds }
        let target = dailyTarget + temporaryTarget
        guard target > 0 else { return nil }
        let dailyAccumulated = visibleTasks.reduce(Int64(0)) { $0 + min($1.accumulatedSeconds, $1.targetSeconds) }
        let temporaryAccumulated = activeTemporaryTasks.reduce(Int64(0)) { $0 + min($1.accumulatedSeconds, $1.targetSeconds) }
        return min(1, Double(dailyAccumulated + temporaryAccumulated) / Double(target))
    }

    public var summaryTask: TimerTaskInstance? {
        if activeSession?.taskKind == .daily,
           let running = visibleTasks.first(where: { $0.id == activeSession?.taskID }) { return running }
        if let recent = visibleTasks
            .filter({ $0.lastActionAtMilliseconds != nil })
            .max(by: { ($0.lastActionAtMilliseconds ?? 0) < ($1.lastActionAtMilliseconds ?? 0) }) {
            return recent
        }
        return visibleTasks.first
    }

    public var runningIdentity: TimerTaskIdentity? { activeSession?.identity }

    public mutating func start(taskID: UUID, atMilliseconds: Int64) throws {
        try start(identity: .daily(instanceID: taskID), atMilliseconds: atMilliseconds)
    }

    public mutating func start(identity: TimerTaskIdentity, atMilliseconds: Int64) throws {
        guard activeSession == nil else { throw TimerDomainError.anotherTaskIsRunning }
        switch identity {
        case let .daily(taskID):
            guard let index = tasks.firstIndex(where: { $0.id == taskID && $0.isVisible }) else {
                throw TimerDomainError.taskNotFound
            }
            guard tasks[index].status != .completed else { throw TimerDomainError.taskCompleted }
            tasks[index].status = .running
            tasks[index].lastActionAtMilliseconds = atMilliseconds
        case let .temporary(taskID):
            guard let index = temporaryTasks.firstIndex(where: { $0.id == taskID && $0.archivedAtMilliseconds == nil }) else {
                throw TimerDomainError.taskNotFound
            }
            guard temporaryTasks[index].status != .completed else { throw TimerDomainError.taskCompleted }
            temporaryTasks[index].status = .running
            temporaryTasks[index].updatedAtMilliseconds = atMilliseconds
        }
        activeSession = TimerSession(
            taskID: identity.taskID,
            taskKind: identity.kind,
            businessDayID: businessDay.id,
            startedAtMilliseconds: atMilliseconds
        )
    }

    @discardableResult
    public mutating func pause(
        atMilliseconds: Int64,
        reason requestedReason: TimerSessionEndReason = .paused
    ) throws -> TimerSessionCompletion? {
        guard let session = activeSession else { throw TimerDomainError.noActiveSession }
        let available: Int64
        switch session.identity {
        case let .daily(taskID):
            guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { throw TimerDomainError.taskNotFound }
            available = tasks[index].remainingSeconds
            let credited = Self.credited(session: session, available: available, atMilliseconds: atMilliseconds)
            tasks[index].accumulatedSeconds += credited
            tasks[index].status = tasks[index].accumulatedSeconds >= tasks[index].targetSeconds ? .completed : .paused
            tasks[index].lastActionAtMilliseconds = atMilliseconds
        case let .temporary(taskID):
            guard let index = temporaryTasks.firstIndex(where: { $0.id == taskID }) else { throw TimerDomainError.taskNotFound }
            available = temporaryTasks[index].remainingSeconds
            let credited = Self.credited(session: session, available: available, atMilliseconds: atMilliseconds)
            temporaryTasks[index].accumulatedSeconds += credited
            temporaryTasks[index].status = temporaryTasks[index].accumulatedSeconds >= temporaryTasks[index].targetSeconds ? .completed : .paused
            temporaryTasks[index].updatedAtMilliseconds = atMilliseconds
        }
        let credited = Self.credited(session: session, available: available, atMilliseconds: atMilliseconds)
        let reachedTarget = credited >= available
        activeSession = nil
        return TimerSessionCompletion(
            session: session,
            endedAtMilliseconds: reachedTarget
                ? min(atMilliseconds, session.startedAtMilliseconds + available * 1_000)
                : atMilliseconds,
            creditedSeconds: credited,
            endReason: reachedTarget ? .targetReached : requestedReason
        )
    }

    public mutating func updateTemplate(_ template: TimerTemplate) {
        guard let index = tasks.firstIndex(where: { $0.templateID == template.id && $0.isVisible }) else { return }
        tasks[index].name = template.name
        tasks[index].colorHex = template.colorHex
        tasks[index].position = template.position
        tasks[index].targetSeconds = template.targetSeconds
        tasks[index].accumulatedSeconds = min(tasks[index].accumulatedSeconds, template.targetSeconds)
        if tasks[index].accumulatedSeconds >= template.targetSeconds { tasks[index].status = .completed }
        else if tasks[index].status == .completed { tasks[index].status = .paused }
        tasks.sort { $0.position < $1.position }
    }

    public mutating func updateTemporaryTask(_ task: TimerTemporaryTask) {
        guard let index = temporaryTasks.firstIndex(where: { $0.id == task.id }) else { return }
        temporaryTasks[index] = task
    }

    private static func credited(
        session: TimerSession, available: Int64, atMilliseconds: Int64
    ) -> Int64 {
        let elapsed = max(0, atMilliseconds - session.startedAtMilliseconds) / 1_000
        return min(available, elapsed)
    }
}

public struct TimerDailySnapshot: Codable, Equatable, Sendable {
    public let businessDayID: BusinessDayID
    public let completionRatio: Double?
    public let completedAtMilliseconds: Int64

    public init(businessDayID: BusinessDayID, completionRatio: Double?, completedAtMilliseconds: Int64) {
        self.businessDayID = businessDayID
        self.completionRatio = completionRatio
        self.completedAtMilliseconds = completedAtMilliseconds
    }
}

public struct TimerDayTransition: Equatable, Sendable {
    public let settledState: TimerDayState
    public let completion: TimerSessionCompletion?
    public let snapshot: TimerDailySnapshot
    public let nextDay: BusinessDay
    public let continuingTemplateID: UUID?
    public let continuingTemporaryTaskID: UUID?
    public let boundaryMilliseconds: Int64

    public var continuingIdentity: TimerTaskIdentity? {
        if let continuingTemporaryTaskID { return .temporary(taskID: continuingTemporaryTaskID) }
        return nil
    }

    public init(
        settledState: TimerDayState,
        completion: TimerSessionCompletion?,
        snapshot: TimerDailySnapshot,
        nextDay: BusinessDay,
        continuingTemplateID: UUID?,
        continuingTemporaryTaskID: UUID? = nil,
        boundaryMilliseconds: Int64
    ) {
        self.settledState = settledState
        self.completion = completion
        self.snapshot = snapshot
        self.nextDay = nextDay
        self.continuingTemplateID = continuingTemplateID
        self.continuingTemporaryTaskID = continuingTemporaryTaskID
        self.boundaryMilliseconds = boundaryMilliseconds
    }
}
