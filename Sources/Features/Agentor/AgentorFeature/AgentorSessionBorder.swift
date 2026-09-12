import Foundation
import Observation
import SwiftUI
import FunctionCardKit

@MainActor
@Observable
final class AgentorVisualClock {
    private(set) var phase = 0.0
    @ObservationIgnored private let clock = ContinuousClock()
    @ObservationIgnored private let epoch: ContinuousClock.Instant
    @ObservationIgnored private var clients = Set<UUID>()
    @ObservationIgnored private var task: Task<Void, Never>?

    init() { epoch = clock.now }
    deinit { task?.cancel() }

    static func phase(at seconds: Double) -> Double {
        (max(0, seconds) / 3.2).truncatingRemainder(dividingBy: 1)
    }

    var intensity: Double { 0.5 - 0.5 * cos(phase * .pi * 2) }
    var isRunning: Bool { task != nil }

    func setActive(_ active: Bool, client: UUID) {
        if active { clients.insert(client) } else { clients.remove(client) }
        if clients.isEmpty {
            task?.cancel()
            task = nil
        } else if task == nil {
            update()
            task = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(34)) }
                    catch { return }
                    self?.update()
                }
            }
        }
    }

    private func update() {
        let duration = epoch.duration(to: clock.now).components
        phase = Self.phase(at: Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
    }
}

struct AgentorVisualScope: ViewModifier {
    let clock: AgentorVisualClock
    let hasSessions: Bool
    @Environment(\.isVisualActivityEnabled) private var isVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var client = UUID()

    private var active: Bool { isVisible && hasSessions && !reduceMotion }

    func body(content: Content) -> some View {
        content
            .onAppear { clock.setActive(active, client: client) }
            .onChange(of: active) { _, active in clock.setActive(active, client: client) }
            .onDisappear { clock.setActive(false, client: client) }
    }
}

struct AgentorSessionBorder: View {
    let status: AgentorExecutionStatus
    let clock: AgentorVisualClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(status == .waitingForAnswer ? Color.orange.opacity(0.6) : Color.white.opacity(reduceMotion ? 0.16 : 0.10 + clock.intensity * 0.12), lineWidth: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
