import Foundation
import SwiftUI

struct TargetorFeedbackBandSnapshot: Equatable, Sendable {
    let index: Int
    let center: Double
    let opacity: Double
}

struct TargetorFeedbackAnimationSnapshot: Equatable, Sendable {
    static let empty = TargetorFeedbackAnimationSnapshot(
        borderOpacity: 0,
        fillOpacity: 0,
        bands: []
    )

    let borderOpacity: Double
    let fillOpacity: Double
    let bands: [TargetorFeedbackBandSnapshot]
}

enum TargetorFeedbackAnimation {
    static let duration: TimeInterval = 1

    private static let flashHoldDuration: TimeInterval = 0.12
    private static let reducedMotionHoldDuration: TimeInterval = 0.70
    private static let bandTravelDuration: TimeInterval = 0.70
    private static let bandStarts: [TimeInterval] = [0.05, 0.25]
    private static let minimumBandCenter = -0.12
    private static let maximumBandCenter = 1.12

    static func snapshot(
        state: TargetorCheckinState,
        elapsed: TimeInterval,
        reduceMotion: Bool
    ) -> TargetorFeedbackAnimationSnapshot {
        guard elapsed >= 0, elapsed < duration else { return .empty }

        if reduceMotion {
            let intensity = heldFade(
                elapsed: elapsed,
                holdDuration: reducedMotionHoldDuration
            )
            return TargetorFeedbackAnimationSnapshot(
                borderOpacity: 0.80 * intensity,
                fillOpacity: 0.16 * intensity,
                bands: []
            )
        }

        switch state {
        case .notStarted:
            return .empty
        case .started:
            return TargetorFeedbackAnimationSnapshot(
                borderOpacity: 0.95 * heldFade(
                    elapsed: elapsed,
                    holdDuration: flashHoldDuration
                ),
                fillOpacity: 0,
                bands: []
            )
        case .progressing:
            return TargetorFeedbackAnimationSnapshot(
                borderOpacity: 0,
                fillOpacity: 0,
                bands: bandStarts.enumerated().compactMap { index, start in
                    band(index: index, start: start, elapsed: elapsed)
                }
            )
        case .completed:
            return TargetorFeedbackAnimationSnapshot(
                borderOpacity: 0,
                fillOpacity: 0.50 * heldFade(
                    elapsed: elapsed,
                    holdDuration: flashHoldDuration
                ),
                bands: []
            )
        }
    }

    private static func heldFade(
        elapsed: TimeInterval,
        holdDuration: TimeInterval
    ) -> Double {
        guard elapsed > holdDuration else { return 1 }
        let progress = clamped((elapsed - holdDuration) / (duration - holdDuration))
        return 1 - smoothstep(progress)
    }

    private static func band(
        index: Int,
        start: TimeInterval,
        elapsed: TimeInterval
    ) -> TargetorFeedbackBandSnapshot? {
        let end = start + bandTravelDuration
        guard elapsed >= start, elapsed < end else { return nil }
        let progress = clamped((elapsed - start) / bandTravelDuration)
        let center = minimumBandCenter
            + (maximumBandCenter - minimumBandCenter) * progress
        return TargetorFeedbackBandSnapshot(
            index: index,
            center: clamped(
                center,
                lowerBound: minimumBandCenter,
                upperBound: maximumBandCenter
            ),
            opacity: clamped(sin(.pi * progress) * 0.78)
        )
    }

    private static func smoothstep(_ value: Double) -> Double {
        let value = clamped(value)
        return value * value * (3 - 2 * value)
    }

    private static func clamped(
        _ value: Double,
        lowerBound: Double = 0,
        upperBound: Double = 1
    ) -> Double {
        min(upperBound, max(lowerBound, value))
    }
}

struct TargetorFeedbackEffect: View {
    let feedback: TargetorFeedback
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let snapshot = TargetorFeedbackAnimation.snapshot(
                state: feedback.state,
                elapsed: timeline.date.timeIntervalSince(feedback.startedAt),
                reduceMotion: reduceMotion
            )
            GeometryReader { geometry in
                effect(snapshot: snapshot, size: geometry.size)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func effect(
        snapshot: TargetorFeedbackAnimationSnapshot,
        size: CGSize
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(snapshot.fillOpacity))

            ForEach(snapshot.bands, id: \.index) { band in
                Rectangle()
                    .fill(.white.opacity(band.opacity))
                    .frame(width: size.width * 0.24, height: size.height)
                    .position(x: size.width * band.center, y: size.height / 2)
            }

            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(snapshot.borderOpacity), lineWidth: 3)
        }
        .compositingGroup()
    }
}
