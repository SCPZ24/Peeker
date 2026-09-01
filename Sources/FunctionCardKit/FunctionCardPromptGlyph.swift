import SwiftUI

struct FunctionCardPromptGlyph: View {
    let prompt: FunctionCardPrompt
    let manifest: FunctionCardIconManifest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || prompt.style == .standard)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(prompt.occurredAt)
            glyph(elapsed: max(0, elapsed))
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func glyph(elapsed: TimeInterval) -> some View {
        switch prompt.style {
        case .standard:
            image.foregroundStyle(.primary)
        case .activity:
            ZStack {
                image.foregroundStyle(.blue)
                Circle()
                    .trim(from: 0.08, to: 0.48)
                    .stroke(.blue.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(reduceMotion ? .zero : .degrees(elapsed.truncatingRemainder(dividingBy: 1.8) / 1.8 * 360))
            }
        case .success:
            ZStack {
                image.foregroundStyle(.green)
                Circle()
                    .trim(from: 0, to: reduceMotion ? 1 : min(1, elapsed / 0.55))
                    .stroke(.green.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        case .failure:
            image
                .foregroundStyle(.red)
                .scaleEffect(reduceMotion ? 1 : 0.94 + 0.06 * pulse(elapsed, duration: 0.8))
        case .attention:
            ZStack {
                image.foregroundStyle(.orange)
                Circle()
                    .stroke(.orange.opacity(reduceMotion ? 0.55 : 0.7 * (1 - pulse(elapsed, duration: 1.2))))
                    .scaleEffect(reduceMotion ? 1 : 0.72 + 0.5 * pulse(elapsed, duration: 1.2))
            }
        }
    }

    private var image: some View {
        FunctionCardIconView(descriptor: prompt.iconDescriptor, manifest: manifest)
            .font(.title3.weight(.semibold))
    }

    private func pulse(_ elapsed: TimeInterval, duration: TimeInterval) -> CGFloat {
        CGFloat(elapsed.truncatingRemainder(dividingBy: duration) / duration)
    }
}
