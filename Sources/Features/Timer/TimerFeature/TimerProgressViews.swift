import SwiftUI

enum TimerIslandAppearance {
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.58)
    static let track = Color.white.opacity(0.14)
}

struct TimerTaskProgressBar: View {
    let ratio: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(TimerIslandAppearance.track)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * clampedRatio)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("任务进度")
        .accessibilityValue("\(percentage)%")
    }

    private var clampedRatio: Double {
        min(max(ratio, 0), 1)
    }

    private var percentage: Int {
        Int((clampedRatio * 100).rounded())
    }
}

struct TimerCompletionRing: View {
    let ratio: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(TimerIslandAppearance.track, lineWidth: 8)
            Circle()
                .trim(from: 0, to: clampedRatio)
                .stroke(
                    Color.accentColor,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(clampedRatio, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(TimerIslandAppearance.primaryText)
        }
        .frame(width: 120, height: 120)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日完成度")
        .accessibilityValue("\(percentage)%")
    }

    private var clampedRatio: Double {
        min(max(ratio, 0), 1)
    }

    private var percentage: Int {
        Int((clampedRatio * 100).rounded())
    }
}
