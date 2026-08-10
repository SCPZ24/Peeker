import Foundation

public enum TimerCalendarRingColor: Equatable, Sendable {
    case yellow
    case blue
}

public enum TimerCalendarRingState: Equatable, Sendable {
    case future
    case missing
    case noTasks
    case progress(ratio: Double, color: TimerCalendarRingColor)
    case completed

    public static func recorded(ratio: Double?) -> TimerCalendarRingState {
        guard let ratio else { return .noTasks }
        let clamped = min(max(ratio, 0), 1)
        if clamped >= 1 { return .completed }
        return .progress(
            ratio: clamped,
            color: clamped <= 0.25 ? .yellow : .blue
        )
    }
}
