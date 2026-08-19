import Foundation
import Observation
import PeekerCore

public struct FunctionCardPrompt: Equatable, Identifiable, Sendable {
    public let token: String
    public let sourceID: FeatureID
    public let systemImage: String
    public let moduleName: String
    public let summary: String
    public let occurredAt: Date

    public var id: String { token }

    public init(
        token: String,
        sourceID: FeatureID,
        systemImage: String,
        moduleName: String,
        summary: String,
        occurredAt: Date = Date()
    ) {
        self.token = token
        self.sourceID = sourceID
        self.systemImage = systemImage
        self.moduleName = moduleName
        self.summary = summary
        self.occurredAt = occurredAt
    }
}

@MainActor
@Observable
public final class PromptCenter {
    public static let capacity = 100
    public static let displayDuration: Duration = .seconds(6)
    public static let postExpansionDelay: Duration = .milliseconds(1_500)

    public private(set) var current: FunctionCardPrompt?
    public private(set) var pending: [FunctionCardPrompt] = []
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var playbackAllowed = true
    @ObservationIgnored private var knownTokens = Set<String>()
    @ObservationIgnored private var onCurrentChanged: @MainActor (FunctionCardPrompt?) -> Void = { _ in }

    public init() {}

    deinit {
        playbackTask?.cancel()
        timeoutTask?.cancel()
    }

    public var count: Int { pending.count + (current == nil ? 0 : 1) }

    public func setCurrentChangedHandler(
        _ handler: @escaping @MainActor (FunctionCardPrompt?) -> Void
    ) {
        onCurrentChanged = handler
    }

    @discardableResult
    public func publish(_ item: FunctionCardPrompt) -> Bool {
        guard count < Self.capacity, knownTokens.insert(item.token).inserted else { return false }
        pending.append(item)
        if playbackAllowed, current == nil { scheduleNext(after: .zero) }
        return true
    }

    public func setPlaybackAllowed(_ allowed: Bool, after delay: Duration = .zero) {
        playbackAllowed = allowed
        playbackTask?.cancel()
        if !allowed {
            timeoutTask?.cancel()
            return
        }
        if current == nil { scheduleNext(after: delay) }
        else { scheduleTimeout() }
    }

    @discardableResult
    public func consumeCurrent() -> FunctionCardPrompt? {
        timeoutTask?.cancel()
        guard let item = current else { return nil }
        knownTokens.remove(item.token)
        current = nil
        onCurrentChanged(nil)
        if playbackAllowed { scheduleNext(after: .zero) }
        return item
    }

    public func revoke(token: String) {
        pending.removeAll { item in
            guard item.token == token else { return false }
            knownTokens.remove(item.token)
            return true
        }
        if current?.token == token { _ = consumeCurrent() }
    }

    public func clear(sourceID: FeatureID) {
        let removed = pending.filter { $0.sourceID == sourceID }.map(\.token)
        pending.removeAll { $0.sourceID == sourceID }
        knownTokens.subtract(removed)
        if current?.sourceID == sourceID { _ = consumeCurrent() }
    }

    private func scheduleNext(after delay: Duration) {
        playbackTask?.cancel()
        guard playbackAllowed, current == nil, !pending.isEmpty else { return }
        playbackTask = Task { [weak self] in
            if delay > .zero {
                do { try await Task.sleep(for: delay) }
                catch { return }
            }
            guard let self, self.playbackAllowed, self.current == nil, !self.pending.isEmpty else { return }
            self.current = self.pending.removeFirst()
            self.onCurrentChanged(self.current)
            self.scheduleTimeout()
        }
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        guard playbackAllowed, current != nil else { return }
        timeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.displayDuration) }
            catch { return }
            guard let self, self.playbackAllowed else { return }
            _ = self.consumeCurrent()
        }
    }
}
