import Foundation
import SwiftUI

struct AgentorSessionBorderMetrics: Equatable {
    let sweepProgress: Double?
    let strokeOpacity: Double
    let glowOpacity: Double
}

enum AgentorSessionBorderAnimation {
    static let normalPeriod: TimeInterval = 3.2
    static let waitingPeriod: TimeInterval = 1.8
    static let transitionDuration: TimeInterval = 0.85
    static let transitionAppearanceDuration: TimeInterval = 0.12
    static let transitionPeakEnd: TimeInterval = 0.35

    static func normal(
        at elapsed: TimeInterval,
        phaseOffset: Double,
        reduceMotion: Bool
    ) -> AgentorSessionBorderMetrics {
        guard !reduceMotion else {
            return AgentorSessionBorderMetrics(sweepProgress: nil, strokeOpacity: 0, glowOpacity: 0)
        }
        let phase = cyclePhase(at: elapsed, period: normalPeriod, offset: phaseOffset)
        let pulse = sinePulse(phase)
        return AgentorSessionBorderMetrics(
            sweepProgress: phase,
            strokeOpacity: 0.38 + 0.34 * pulse,
            glowOpacity: 0.10 + 0.12 * pulse
        )
    }

    static func waiting(at elapsed: TimeInterval, reduceMotion: Bool) -> AgentorSessionBorderMetrics {
        guard !reduceMotion else {
            return AgentorSessionBorderMetrics(sweepProgress: nil, strokeOpacity: 0.78, glowOpacity: 0)
        }
        let pulse = sinePulse(cyclePhase(at: elapsed, period: waitingPeriod, offset: 0))
        return AgentorSessionBorderMetrics(
            sweepProgress: nil,
            strokeOpacity: 0.38 + 0.54 * pulse,
            glowOpacity: 0.12 + 0.28 * pulse
        )
    }

    static func transition(at elapsed: TimeInterval, reduceMotion: Bool) -> AgentorSessionBorderMetrics? {
        guard elapsed >= 0, elapsed < transitionDuration else { return nil }
        if reduceMotion {
            return AgentorSessionBorderMetrics(sweepProgress: nil, strokeOpacity: 0.85, glowOpacity: 0)
        }
        let intensity: Double
        if elapsed < transitionAppearanceDuration {
            intensity = elapsed / transitionAppearanceDuration
        } else if elapsed <= transitionPeakEnd {
            intensity = 1
        } else {
            let progress = (elapsed - transitionPeakEnd) / (transitionDuration - transitionPeakEnd)
            intensity = 1 - smoothStep(progress)
        }
        return AgentorSessionBorderMetrics(
            sweepProgress: nil,
            strokeOpacity: 0.95 * intensity,
            glowOpacity: 0.28 * intensity
        )
    }

    private static func cyclePhase(at elapsed: TimeInterval, period: TimeInterval, offset: Double) -> Double {
        let raw = max(0, elapsed) / period + offset
        let remainder = raw.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }

    private static func sinePulse(_ phase: Double) -> Double {
        0.5 - 0.5 * cos(phase * 2 * .pi)
    }

    private static func smoothStep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

enum AgentorSessionBorderTransitionPolicy {
    static func shouldFlash(
        from previous: AgentorExecutionStatus?,
        to next: AgentorExecutionStatus,
        generationChanged: Bool = false
    ) -> Bool {
        guard !generationChanged, let previous, previous != next, next != .waitingForAnswer else { return false }
        return true
    }
}

@MainActor
struct AgentorSessionBorder: View {
    let status: AgentorExecutionStatus
    let generation: UInt64
    let startedAt: Date
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashStartedAt: Date?
    @State private var flashCleanupTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            GeometryReader { geometry in
                border(at: timeline.date, size: geometry.size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: visualState) { previous, next in
            handleChange(from: previous, to: next)
        }
        .onDisappear { flashCleanupTask?.cancel() }
    }

    private var visualState: AgentorSessionBorderVisualState {
        AgentorSessionBorderVisualState(status: status, generation: generation)
    }

    @ViewBuilder
    private func border(at date: Date, size: CGSize) -> some View {
        if status == .waitingForAnswer {
            waitingBorder(at: date)
        } else if let flashStartedAt,
                  let metrics = AgentorSessionBorderAnimation.transition(
                    at: date.timeIntervalSince(flashStartedAt),
                    reduceMotion: reduceMotion
                  ) {
            transitionBorder(metrics: metrics)
        } else {
            normalBorder(at: date, size: size)
        }
    }

    private func normalBorder(at date: Date, size: CGSize) -> some View {
        let metrics = AgentorSessionBorderAnimation.normal(
            at: date.timeIntervalSince(startedAt),
            phaseOffset: Double(generation % 23) / 23,
            reduceMotion: reduceMotion
        )
        return ZStack {
            borderShape.stroke(.white.opacity(0.14), lineWidth: 1)
            if let progress = metrics.sweepProgress {
                borderShape
                    .stroke(.white.opacity(metrics.glowOpacity), lineWidth: 3.6)
                    .blur(radius: 2)
                    .mask(sweepMask(size: size, progress: progress))
                borderShape
                    .stroke(.white.opacity(metrics.strokeOpacity), lineWidth: 1.4)
                    .mask(sweepMask(size: size, progress: progress))
            }
        }
        .compositingGroup()
    }

    private func waitingBorder(at date: Date) -> some View {
        let metrics = AgentorSessionBorderAnimation.waiting(
            at: date.timeIntervalSince(startedAt),
            reduceMotion: reduceMotion
        )
        return ZStack {
            borderShape.stroke(waitingBlue.opacity(0.34), lineWidth: 1.2)
            borderShape
                .stroke(waitingBlue.opacity(metrics.glowOpacity), lineWidth: 4.2)
                .blur(radius: 2.5)
            borderShape.stroke(waitingBlue.opacity(metrics.strokeOpacity), lineWidth: 1.6)
        }
        .compositingGroup()
    }

    private func transitionBorder(metrics: AgentorSessionBorderMetrics) -> some View {
        ZStack {
            borderShape.stroke(.white.opacity(0.14), lineWidth: 1)
            borderShape
                .stroke(transitionGreen.opacity(metrics.glowOpacity), lineWidth: 4.6)
                .blur(radius: 2.8)
            borderShape.stroke(transitionGreen.opacity(metrics.strokeOpacity), lineWidth: 1.8)
        }
        .compositingGroup()
    }

    private func sweepMask(size: CGSize, progress: Double) -> some View {
        let bandWidth = max(48, size.width * 0.26)
        let travel = size.width + bandWidth * 2
        let offset = -bandWidth + travel * progress
        return LinearGradient(
            colors: [.clear, .white.opacity(0.2), .white, .white.opacity(0.2), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: bandWidth)
        .offset(x: offset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var borderShape: some InsettableShape {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).inset(by: 1)
    }

    private var waitingBlue: Color {
        Color(red: 0.25, green: 0.58, blue: 1)
    }

    private var transitionGreen: Color {
        Color(red: 0.25, green: 0.95, blue: 0.52)
    }

    private func handleChange(
        from previous: AgentorSessionBorderVisualState,
        to next: AgentorSessionBorderVisualState
    ) {
        if previous.generation != next.generation || next.status == .waitingForAnswer {
            clearFlash()
            return
        }
        guard AgentorSessionBorderTransitionPolicy.shouldFlash(from: previous.status, to: next.status) else { return }
        startFlash(at: Date())
    }

    private func startFlash(at date: Date) {
        let initialElapsed = flashStartedAt == nil ? 0 : AgentorSessionBorderAnimation.transitionAppearanceDuration
        flashStartedAt = date.addingTimeInterval(-initialElapsed)
        flashCleanupTask?.cancel()
        let remaining = AgentorSessionBorderAnimation.transitionDuration - initialElapsed
        flashCleanupTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(Int(remaining * 1_000))) }
            catch { return }
            flashStartedAt = nil
            flashCleanupTask = nil
        }
    }

    private func clearFlash() {
        flashCleanupTask?.cancel()
        flashCleanupTask = nil
        flashStartedAt = nil
    }
}

private struct AgentorSessionBorderVisualState: Equatable {
    let status: AgentorExecutionStatus
    let generation: UInt64
}
