struct TimerProgressSnapshot: Equatable, Sendable {
    let targetSeconds: Int64
    let remainingSeconds: Int64

    var ratio: Double {
        guard targetSeconds > 0 else { return 0 }
        let clampedRemaining = min(max(remainingSeconds, 0), targetSeconds)
        return Double(targetSeconds - clampedRemaining) / Double(targetSeconds)
    }
}

enum TimerProgressMetrics {
    static func totalRatio(_ snapshots: [TimerProgressSnapshot]) -> Double? {
        let valid = snapshots.filter { $0.targetSeconds > 0 }
        let target = valid.reduce(Int64(0)) { $0 + $1.targetSeconds }
        guard target > 0 else { return nil }

        let progressed = valid.reduce(Int64(0)) { partial, snapshot in
            let remaining = min(max(snapshot.remainingSeconds, 0), snapshot.targetSeconds)
            return partial + snapshot.targetSeconds - remaining
        }
        return min(1, max(0, Double(progressed) / Double(target)))
    }
}
