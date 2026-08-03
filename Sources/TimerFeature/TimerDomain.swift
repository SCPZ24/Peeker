import Foundation
import PeekerCore

public enum TimerDomainError: Error, Equatable {
    case blankName
    case targetOutOfRange
    case taskNotFound
    case anotherTaskIsRunning
    case taskCompleted
    case noActiveSession
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
    public let businessDayID: BusinessDayID
    public let startedAtMilliseconds: Int64

    public init(
        id: UUID = UUID(),
        taskID: UUID,
        businessDayID: BusinessDayID,
        startedAtMilliseconds: Int64
    ) {
        self.id = id
        self.taskID = taskID
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
    public private(set) var activeSession: TimerSession?

    public init(
        businessDay: BusinessDay,
        tasks: [TimerTaskInstance],
        activeSession: TimerSession? = nil
    ) {
        self.businessDay = businessDay
        self.tasks = tasks.sorted { $0.position < $1.position }
        self.activeSession = activeSession
    }

    public var visibleTasks: [TimerTaskInstance] {
        tasks.filter(\.isVisible).sorted { $0.position < $1.position }
    }

    public var completionRatio: Double? {
        let visible = visibleTasks
        let target = visible.reduce(Int64(0)) { $0 + $1.targetSeconds }
        guard target > 0 else { return nil }
        let accumulated = visible.reduce(Int64(0)) { $0 + min($1.accumulatedSeconds, $1.targetSeconds) }
        return min(1, Double(accumulated) / Double(target))
    }

    public var summaryTask: TimerTaskInstance? {
        if let running = visibleTasks.first(where: { $0.status == .running }) { return running }
        if let recent = visibleTasks
            .filter({ $0.lastActionAtMilliseconds != nil })
            .max(by: { ($0.lastActionAtMilliseconds ?? 0) < ($1.lastActionAtMilliseconds ?? 0) }) {
            return recent
        }
        return visibleTasks.first
    }

    public mutating func start(taskID: UUID, atMilliseconds: Int64) throws {
        guard activeSession == nil else { throw TimerDomainError.anotherTaskIsRunning }
        guard let index = tasks.firstIndex(where: { $0.id == taskID && $0.isVisible }) else {
            throw TimerDomainError.taskNotFound
        }
        guard tasks[index].status != .completed else { throw TimerDomainError.taskCompleted }

        tasks[index].status = .running
        tasks[index].lastActionAtMilliseconds = atMilliseconds
        activeSession = TimerSession(
            taskID: taskID,
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
        guard let index = tasks.firstIndex(where: { $0.id == session.taskID }) else {
            throw TimerDomainError.taskNotFound
        }

        let available = tasks[index].remainingSeconds
        let elapsedMilliseconds = max(0, atMilliseconds - session.startedAtMilliseconds)
        let elapsedSeconds = Int64(Double(elapsedMilliseconds) / 1_000.0)
        let credited = min(available, elapsedSeconds)
        tasks[index].accumulatedSeconds += credited
        let reachedTarget = tasks[index].accumulatedSeconds >= tasks[index].targetSeconds
        tasks[index].status = reachedTarget ? .completed : .paused
        tasks[index].lastActionAtMilliseconds = atMilliseconds
        activeSession = nil

        let reason: TimerSessionEndReason = reachedTarget ? .targetReached : requestedReason
        let effectiveEnd = reachedTarget
            ? min(atMilliseconds, session.startedAtMilliseconds + available * 1_000)
            : atMilliseconds
        return TimerSessionCompletion(
            session: session,
            endedAtMilliseconds: effectiveEnd,
            creditedSeconds: credited,
            endReason: reason
        )
    }

    public mutating func updateTemplate(_ template: TimerTemplate) {
        guard let index = tasks.firstIndex(where: { $0.templateID == template.id && $0.isVisible }) else { return }
        tasks[index].name = template.name
        tasks[index].colorHex = template.colorHex
        tasks[index].position = template.position
        tasks[index].targetSeconds = template.targetSeconds
        tasks[index].accumulatedSeconds = min(tasks[index].accumulatedSeconds, template.targetSeconds)
        if tasks[index].accumulatedSeconds >= template.targetSeconds {
            tasks[index].status = .completed
        } else if tasks[index].status == .completed {
            tasks[index].status = .paused
        }
        tasks.sort { $0.position < $1.position }
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
