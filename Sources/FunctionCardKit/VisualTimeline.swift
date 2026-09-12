import SwiftUI

public struct VisualTimeline<Content: View>: View {
    private let isRunning: Bool
    private let interval: TimeInterval
    private let content: (Date) -> Content
    @Environment(\.isVisualActivityEnabled) private var isVisible

    public init(isRunning: Bool = true, interval: TimeInterval = 1, @ViewBuilder content: @escaping (Date) -> Content) {
        self.isRunning = isRunning
        self.interval = interval
        self.content = content
    }

    public var body: some View {
        TimelineView(VisualTimelineSchedule(interval: interval, paused: !isVisible || !isRunning)) { context in
            content(context.date)
        }
    }
}

struct VisualTimelineSchedule: TimelineSchedule {
    let interval: TimeInterval
    let paused: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        AnySequence(sequence(state: Optional(startDate)) { next in
            guard let date = next else { return nil }
            next = paused ? nil : date.addingTimeInterval(interval)
            return date
        })
    }
}
