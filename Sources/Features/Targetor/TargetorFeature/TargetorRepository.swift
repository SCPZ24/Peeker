import Foundation
import PeekerCore

public enum TargetorArchiveScope: Sendable {
    case active
    case all
    case only
}

public protocol TargetorRepository: Sendable {
    func recover(now: Date, refreshTime: RefreshTime, resolver: TargetorPeriodResolver) async throws
    func snapshot(scope: TargetorArchiveScope) async throws -> TargetorSnapshot
    func create(target: TargetorTarget, firstPeriod: TargetorPeriod) async throws
    func update(
        target: TargetorTarget,
        replacingCurrentWith period: TargetorPeriod?,
        settleAtMilliseconds: Int64?
    ) async throws
    func archive(targetID: UUID, atMilliseconds: Int64) async throws -> TargetorTargetState
    func reorder(activeTargetIDs: [UUID], atMilliseconds: Int64) async throws
    func checkin(targetID: UUID, eventID: UUID, atMilliseconds: Int64) async throws -> TargetorCheckinResult
    func uncheck(eventID: UUID) async throws -> TargetorTargetState
    func history(targetID: UUID, fromMilliseconds: Int64?, toMilliseconds: Int64?) async throws -> TargetorHistory
}
