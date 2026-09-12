import SwiftUI

struct FunctionCardPromptGlyph: View {
    let prompt: FunctionCardPrompt
    let displayedAt: Date?
    let manifest: FunctionCardIconManifest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isVisualActivityEnabled) private var isVisible
    @State private var entered = false

    var body: some View {
        Group {
            if prompt.style == .activity && isVisible && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    image.rotationEffect(.degrees(context.date.timeIntervalSince(displayedAt ?? context.date)
                        .truncatingRemainder(dividingBy: 3.2) / 3.2 * 360))
                }
            } else {
                image
                    .opacity(entered || reduceMotion ? 1 : 0.5)
                    .scaleEffect(entered || reduceMotion ? 1 : 0.85)
            }
        }
        .foregroundStyle(color)
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
        .task(id: prompt.token) {
            let remaining = max(0, 0.45 - Date().timeIntervalSince(displayedAt ?? Date()))
            entered = remaining == 0
            withAnimation(reduceMotion || remaining == 0 ? nil : .easeOut(duration: remaining)) { entered = true }
        }
    }

    private var color: Color {
        switch prompt.style {
        case .standard: .primary
        case .activity: .blue
        case .success: .green
        case .failure: .red
        case .attention: .orange
        }
    }

    private var image: some View {
        FunctionCardIconView(descriptor: prompt.iconDescriptor, manifest: manifest)
            .font(.title3.weight(.semibold))
    }
}
