import Foundation
import PeekerCore

public enum TargetorError: Error, Equatable, Sendable {
    case invalidTitle
    case invalidIcon
    case invalidPeriod
    case invalidMaxCount
    case targetNotFound
    case ambiguousSelector([UUID])
    case targetArchived
    case cycleComplete
    case eventNotFound
    case eventNotCurrent
    case invalidHistoryRange
    case noActualChange
}

public enum TargetorFrequency: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
}

public enum TargetorWeekday: String, Codable, CaseIterable, Sendable {
    case mon, tue, wed, thu, fri, sat, sun

    public var calendarWeekday: Int {
        switch self {
        case .sun: 1
        case .mon: 2
        case .tue: 3
        case .wed: 4
        case .thu: 5
        case .fri: 6
        case .sat: 7
        }
    }
}

public struct TargetorPeriodRule: Codable, Equatable, Hashable, Sendable {
    public let frequency: TargetorFrequency
    public let weekday: TargetorWeekday?
    public let monthDay: Int?

    public init(
        frequency: TargetorFrequency,
        weekday: TargetorWeekday? = nil,
        monthDay: Int? = nil
    ) throws {
        switch frequency {
        case .daily:
            guard weekday == nil, monthDay == nil else { throw TargetorError.invalidPeriod }
        case .weekly:
            guard weekday != nil, monthDay == nil else { throw TargetorError.invalidPeriod }
        case .monthly:
            guard weekday == nil, let monthDay, (0...30).contains(monthDay) else {
                throw TargetorError.invalidPeriod
            }
        }
        self.frequency = frequency
        self.weekday = weekday
        self.monthDay = monthDay
    }

    public static let daily = try! TargetorPeriodRule(frequency: .daily)
}

public enum TargetorCheckinState: String, Codable, Equatable, Sendable {
    case notStarted
    case started
    case progressing
    case completed

    public static func resolve(count: Int, maxCount: Int) -> TargetorCheckinState {
        guard count > 0 else { return .notStarted }
        let ratio = Double(count) / Double(max(1, maxCount))
        if ratio >= 1 { return .completed }
        if ratio <= 0.5 { return .started }
        return .progressing
    }
}

public struct TargetorTarget: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var description: String?
    public var iconName: String
    public var periodRule: TargetorPeriodRule
    public var maxCount: Int
    public var position: Int
    public let createdAtMilliseconds: Int64
    public var updatedAtMilliseconds: Int64
    public var archivedAtMilliseconds: Int64?

    public init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        iconName: String = "target",
        periodRule: TargetorPeriodRule = .daily,
        maxCount: Int = 1,
        position: Int = 0,
        createdAtMilliseconds: Int64 = Date().millisecondsSince1970,
        updatedAtMilliseconds: Int64 = Date().millisecondsSince1970,
        archivedAtMilliseconds: Int64? = nil
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { throw TargetorError.invalidTitle }
        guard Self.isCanonicalIconName(iconName) else { throw TargetorError.invalidIcon }
        guard (1...99).contains(maxCount) else { throw TargetorError.invalidMaxCount }
        self.id = id
        self.title = normalizedTitle
        self.description = description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.iconName = iconName
        self.periodRule = periodRule
        self.maxCount = maxCount
        self.position = position
        self.createdAtMilliseconds = createdAtMilliseconds
        self.updatedAtMilliseconds = updatedAtMilliseconds
        self.archivedAtMilliseconds = archivedAtMilliseconds
    }

    public static func isCanonicalIconName(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil
    }
}

public struct TargetorPeriod: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let targetID: UUID
    public let sequence: Int
    public let startMilliseconds: Int64
    public let endMilliseconds: Int64
    public let ruleSnapshot: TargetorPeriodRule
    public let maxCountSnapshot: Int
    public let createdAtMilliseconds: Int64
    public let settledAtMilliseconds: Int64?
    public let count: Int

    public init(
        id: UUID = UUID(), targetID: UUID, sequence: Int,
        startMilliseconds: Int64, endMilliseconds: Int64,
        ruleSnapshot: TargetorPeriodRule, maxCountSnapshot: Int,
        createdAtMilliseconds: Int64, settledAtMilliseconds: Int64? = nil,
        count: Int = 0
    ) {
        self.id = id
        self.targetID = targetID
        self.sequence = sequence
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.ruleSnapshot = ruleSnapshot
        self.maxCountSnapshot = maxCountSnapshot
        self.createdAtMilliseconds = createdAtMilliseconds
        self.settledAtMilliseconds = settledAtMilliseconds
        self.count = count
    }

    public var ratio: Double { min(1, Double(count) / Double(max(1, maxCountSnapshot))) }
    public var state: TargetorCheckinState { .resolve(count: count, maxCount: maxCountSnapshot) }
    public var isCurrent: Bool { settledAtMilliseconds == nil }
}

public struct TargetorCheckin: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let targetID: UUID
    public let periodID: UUID
    public let occurredAtMilliseconds: Int64

    public init(
        id: UUID = UUID(), targetID: UUID, periodID: UUID,
        occurredAtMilliseconds: Int64
    ) {
        self.id = id
        self.targetID = targetID
        self.periodID = periodID
        self.occurredAtMilliseconds = occurredAtMilliseconds
    }
}

public struct TargetorTargetState: Codable, Equatable, Identifiable, Sendable {
    public let target: TargetorTarget
    public let currentPeriod: TargetorPeriod?
    public let lastPeriod: TargetorPeriod?
    public var id: UUID { target.id }

    public init(target: TargetorTarget, currentPeriod: TargetorPeriod?, lastPeriod: TargetorPeriod?) {
        self.target = target
        self.currentPeriod = currentPeriod
        self.lastPeriod = lastPeriod
    }
}

public struct TargetorSnapshot: Equatable, Sendable {
    public let targets: [TargetorTargetState]
    public let issues: [String]

    public init(targets: [TargetorTargetState], issues: [String] = []) {
        self.targets = targets
        self.issues = issues
    }
}

public struct TargetorCheckinResult: Equatable, Sendable {
    public let target: TargetorTargetState
    public let event: TargetorCheckin

    public init(target: TargetorTargetState, event: TargetorCheckin) {
        self.target = target
        self.event = event
    }
}

public struct TargetorHistory: Equatable, Sendable {
    public let target: TargetorTarget
    public let fromMilliseconds: Int64
    public let toMilliseconds: Int64
    public let periods: [TargetorPeriod]
    public let events: [TargetorCheckin]

    public init(
        target: TargetorTarget, fromMilliseconds: Int64, toMilliseconds: Int64,
        periods: [TargetorPeriod], events: [TargetorCheckin]
    ) {
        self.target = target
        self.fromMilliseconds = fromMilliseconds
        self.toMilliseconds = toMilliseconds
        self.periods = periods
        self.events = events
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
