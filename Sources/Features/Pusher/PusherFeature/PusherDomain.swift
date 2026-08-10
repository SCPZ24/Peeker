import Foundation
import PeekerCore

public enum PusherDomainError: Error, Equatable {
    case blankTitle
    case taskNotFound
    case invalidDestination
    case duplicateTask
}

public enum PusherUrgency: String, Codable, CaseIterable, Equatable, Sendable {
    case urgent
    case progress
    case planning
}

public enum PusherStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case planned
    case processing
    case done
}

public struct PusherTask: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var seriesID: UUID?
    public var title: String
    public var urgency: PusherUrgency
    public var status: PusherStatus
    public var position: Int
    public var businessDayID: BusinessDayID
    public var createdAtMilliseconds: Int64
    public var updatedAtMilliseconds: Int64

    public init(
        id: UUID = UUID(),
        seriesID: UUID? = nil,
        title: String,
        urgency: PusherUrgency,
        status: PusherStatus = .planned,
        position: Int = 0,
        businessDayID: BusinessDayID,
        createdAtMilliseconds: Int64 = Date().millisecondsSince1970,
        updatedAtMilliseconds: Int64 = Date().millisecondsSince1970
    ) throws {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw PusherDomainError.blankTitle }
        self.id = id
        self.seriesID = seriesID
        self.title = normalized
        self.urgency = urgency
        self.status = status
        self.position = position
        self.businessDayID = businessDayID
        self.createdAtMilliseconds = createdAtMilliseconds
        self.updatedAtMilliseconds = updatedAtMilliseconds
    }

    public var repeatsDaily: Bool { seriesID != nil }

    public mutating func setRepeatsDaily(_ repeats: Bool) {
        if repeats, seriesID == nil { seriesID = UUID() }
        if !repeats { seriesID = nil }
    }
}

public struct PusherSummary: Codable, Equatable, Sendable {
    public let planned: Int
    public let processing: Int
    public let done: Int

    public init(planned: Int, processing: Int, done: Int) {
        self.planned = planned
        self.processing = processing
        self.done = done
    }
}

public struct PusherCompactSummary: Equatable, Sendable {
    public let planned: Int
    public let processing: Int
    public let done: Int
    public let urgentProcessing: Int
    public let progressProcessing: Int
    public let planningProcessing: Int

    public init(
        planned: Int,
        processing: Int,
        done: Int,
        urgentProcessing: Int,
        progressProcessing: Int,
        planningProcessing: Int
    ) {
        self.planned = planned
        self.processing = processing
        self.done = done
        self.urgentProcessing = urgentProcessing
        self.progressProcessing = progressProcessing
        self.planningProcessing = planningProcessing
    }

    public static let zero = PusherCompactSummary(
        planned: 0,
        processing: 0,
        done: 0,
        urgentProcessing: 0,
        progressProcessing: 0,
        planningProcessing: 0
    )

    var processingStatusCounts: [PusherCompactStatusCount] {
        [
            PusherCompactStatusCount(urgency: .urgent, count: urgentProcessing),
            PusherCompactStatusCount(urgency: .progress, count: progressProcessing),
            PusherCompactStatusCount(urgency: .planning, count: planningProcessing),
        ]
    }
}

struct PusherCompactStatusCount: Equatable, Identifiable, Sendable {
    let urgency: PusherUrgency
    let count: Int

    var id: String { urgency.rawValue }
}

public struct PusherBoard: Codable, Equatable, Sendable {
    public let businessDay: BusinessDay
    public private(set) var allTasks: [PusherTask]

    public init(businessDay: BusinessDay, tasks: [PusherTask]) {
        self.businessDay = businessDay
        self.allTasks = tasks
        normalizeAll()
    }

    public var summary: PusherSummary {
        PusherSummary(
            planned: tasks(in: .planned).count,
            processing: tasks(in: .processing).count,
            done: tasks(in: .done).count
        )
    }

    public var compactSummary: PusherCompactSummary {
        let processingTasks = tasks(in: .processing)
        return PusherCompactSummary(
            planned: tasks(in: .planned).count,
            processing: processingTasks.count,
            done: tasks(in: .done).count,
            urgentProcessing: processingTasks.count { $0.urgency == .urgent },
            progressProcessing: processingTasks.count { $0.urgency == .progress },
            planningProcessing: processingTasks.count { $0.urgency == .planning }
        )
    }

    public func tasks(in status: PusherStatus) -> [PusherTask] {
        allTasks.filter { $0.status == status }.sorted { $0.position < $1.position }
    }

    func hasSameTaskPlacement(as other: PusherBoard) -> Bool {
        businessDay == other.businessDay
            && PusherStatus.allCases.allSatisfy { status in
                tasks(in: status).map(\.id) == other.tasks(in: status).map(\.id)
            }
    }

    public mutating func insert(_ task: PusherTask) throws {
        guard !allTasks.contains(where: { $0.id == task.id }) else { throw PusherDomainError.duplicateTask }
        var inserted = task
        inserted.status = .planned
        inserted.position = tasks(in: .planned).count
        inserted.businessDayID = businessDay.id
        allTasks.append(inserted)
        normalize(.planned)
    }

    public mutating func update(_ task: PusherTask) throws {
        guard let index = allTasks.firstIndex(where: { $0.id == task.id }) else {
            throw PusherDomainError.taskNotFound
        }
        var updated = task
        updated.status = allTasks[index].status
        updated.position = allTasks[index].position
        updated.businessDayID = businessDay.id
        allTasks[index] = updated
    }

    public mutating func remove(taskID: UUID) throws {
        guard let index = allTasks.firstIndex(where: { $0.id == taskID }) else {
            throw PusherDomainError.taskNotFound
        }
        let status = allTasks[index].status
        allTasks.remove(at: index)
        normalize(status)
    }

    public mutating func move(taskID: UUID, to status: PusherStatus, at destination: Int) throws {
        guard let sourceIndex = allTasks.firstIndex(where: { $0.id == taskID }) else {
            throw PusherDomainError.taskNotFound
        }
        let sourceStatus = allTasks[sourceIndex].status
        let sourcePosition = tasks(in: sourceStatus).firstIndex { $0.id == taskID }
        let visibleDestinationCount = tasks(in: status).count
        guard destination >= 0, destination <= visibleDestinationCount else {
            throw PusherDomainError.invalidDestination
        }
        let normalizedDestination: Int
        if sourceStatus == status, let sourcePosition, destination > sourcePosition {
            normalizedDestination = destination - 1
        } else {
            normalizedDestination = destination
        }

        var task = allTasks.remove(at: sourceIndex)
        var destinationTasks = tasks(in: status)
        task.status = status
        destinationTasks.insert(task, at: normalizedDestination)
        for index in destinationTasks.indices {
            destinationTasks[index].position = index
        }

        allTasks.removeAll { $0.status == status }
        allTasks.append(contentsOf: destinationTasks)
        if sourceStatus != status { normalize(sourceStatus) }
    }

    private mutating func normalizeAll() {
        for status in PusherStatus.allCases { normalize(status) }
    }

    private mutating func normalize(_ status: PusherStatus) {
        let orderedIDs = tasks(in: status).map(\.id)
        for (position, id) in orderedIDs.enumerated() {
            if let index = allTasks.firstIndex(where: { $0.id == id }) {
                allTasks[index].position = position
            }
        }
    }
}

public struct PusherDailySnapshot: Codable, Equatable, Sendable {
    public let businessDayID: BusinessDayID
    public let doneCount: Int
    public let totalCount: Int
    public let completedAtMilliseconds: Int64

    public init(
        businessDayID: BusinessDayID,
        doneCount: Int,
        totalCount: Int,
        completedAtMilliseconds: Int64
    ) {
        self.businessDayID = businessDayID
        self.doneCount = doneCount
        self.totalCount = totalCount
        self.completedAtMilliseconds = completedAtMilliseconds
    }
}

public struct PusherSettlement: Equatable, Sendable {
    public let settledBoard: PusherBoard
    public let snapshot: PusherDailySnapshot
    public let nextBoard: PusherBoard

    public static func settle(
        _ board: PusherBoard,
        into nextDay: BusinessDay,
        carryIncomplete: Bool,
        atMilliseconds: Int64
    ) -> PusherSettlement {
        let snapshot = PusherDailySnapshot(
            businessDayID: board.businessDay.id,
            doneCount: board.summary.done,
            totalCount: board.allTasks.count,
            completedAtMilliseconds: atMilliseconds
        )
        var nextTasks: [PusherTask] = []

        for task in board.allTasks.sorted(by: { $0.position < $1.position }) {
            if let seriesID = task.seriesID {
                let recreated = try! PusherTask(
                    seriesID: seriesID,
                    title: task.title,
                    urgency: task.urgency,
                    status: .planned,
                    position: nextTasks.filter { $0.status == .planned }.count,
                    businessDayID: nextDay.id,
                    createdAtMilliseconds: atMilliseconds,
                    updatedAtMilliseconds: atMilliseconds
                )
                nextTasks.append(recreated)
            } else if task.status != .done, carryIncomplete {
                var carried = task
                carried.businessDayID = nextDay.id
                carried.updatedAtMilliseconds = atMilliseconds
                nextTasks.append(carried)
            }
        }

        return PusherSettlement(
            settledBoard: board,
            snapshot: snapshot,
            nextBoard: PusherBoard(businessDay: nextDay, tasks: nextTasks)
        )
    }
}
