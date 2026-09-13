import SwiftUI

 enum TargetorFeedbackAnimation {
    static func duration(for state: TargetorCheckinState) -> TimeInterval {
        switch state {
        case .notStarted: 0
        case .started: 0.4
        case .progressing: 0.65
        case .completed: 0.9
        }
    }
}

struct TargetorFeedbackEffect: View {
    static let height: CGFloat = 38

    let feedback: TargetorFeedback
    let reduceMotion: Bool
    @State private var settled = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.green)
                .offset(y: settled || reduceMotion ? 0 : 8)
                .opacity(settled || reduceMotion ? 1 : 0.4)
            Text(L10n.text("打卡成功"))
                .font(.callout)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: Self.height)
        .task(id: feedback.token) {
            settled = false
            withAnimation(reduceMotion ? nil : .easeOut(duration: TargetorFeedbackAnimation.duration(for: feedback.state))) {
                settled = true
            }
        }
    }

    private var symbol: String {
        switch feedback.state {
        case .notStarted, .started: "chevron.up"
        case .progressing: "paperplane"
        case .completed: "checkmark.seal"
        }
    }
}
