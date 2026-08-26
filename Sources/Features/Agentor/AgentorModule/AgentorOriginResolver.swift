import AgentorProtocol
import AppKit
import Darwin
import Foundation

struct AgentorOriginIdentity: Sendable, Equatable {
    let pid: pid_t
    let startedAt: Date
}

enum AgentorProcessInspector {
    private static let startTimeTolerance: TimeInterval = 0.002

    static func processInfo(_ pid: pid_t) -> (parent: pid_t, startedAt: Date)? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size else { return nil }
        let startedAt = Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
        return (pid_t(info.pbi_ppid), startedAt)
    }

    static func startTimeMatches(_ expected: Date?, actual: Date) -> Bool {
        guard let expected else { return true }
        return abs(expected.timeIntervalSince(actual)) <= startTimeTolerance
    }

    static func nearestRunningApplication(from pid: pid_t) -> AgentorOriginIdentity? {
        var current = pid
        var visited = Set<pid_t>()
        for _ in 0..<16 {
            guard current > 1, visited.insert(current).inserted,
                  let info = processInfo(current) else { return nil }
            if let application = NSRunningApplication(processIdentifier: current),
               application.activationPolicy == .regular {
                return AgentorOriginIdentity(pid: current, startedAt: info.startedAt)
            }
            current = info.parent
        }
        return nil
    }

    @MainActor
    static func activate(_ identity: AgentorOriginIdentity) -> Bool {
        guard let current = processInfo(identity.pid), startTimeMatches(identity.startedAt, actual: current.startedAt),
              let application = NSRunningApplication(processIdentifier: identity.pid),
              !application.isTerminated else { return false }
        return application.activate()
    }
}
