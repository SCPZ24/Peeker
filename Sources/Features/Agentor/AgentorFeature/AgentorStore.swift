import AgentorProtocol
import Foundation
import FunctionCardKit
import Observation

public enum AgentIntegrationState: String, Sendable, Equatable {
    case notFound
    case notIntegrated
    case integrated

    public var displayName: String {
        switch self {
        case .notFound: "未发现"
        case .notIntegrated: "未接入"
        case .integrated: "已接入"
        }
    }
}

public enum AgentCapability: String, Sendable, Equatable, CaseIterable {
    case status = "状态"
    case answer = "岛内回答"
    case reminder = "仅提醒"
}

public struct AgentIntegrationStatus: Identifiable, Sendable, Equatable {
    public let agent: AgentKind
    public let state: AgentIntegrationState
    public let paths: [String]
    public let detail: String
    public let scannedAt: Date
    public let capabilities: [AgentCapability]

    public var id: AgentKind { agent }

    public init(
        agent: AgentKind,
        state: AgentIntegrationState,
        paths: [String] = [],
        detail: String,
        scannedAt: Date = Date(),
        capabilities: [AgentCapability]
    ) {
        self.agent = agent
        self.state = state
        self.paths = paths
        self.detail = detail
        self.scannedAt = scannedAt
        self.capabilities = capabilities
    }
}

public enum AgentIntegrationAction: Sendable {
    case install
    case remove
}

public struct AgentorFeatureDependencies: Sendable {
    public let publishPrompt: @MainActor @Sendable (FunctionCardPrompt) -> Void
    public let revokePrompt: @MainActor @Sendable (String) -> Void
    public let setEditingText: @MainActor @Sendable (Bool) -> Void
    public let scanIntegrations: @Sendable () async -> [AgentIntegrationStatus]
    public let performIntegration: @Sendable (AgentKind, AgentIntegrationAction) async throws -> Void
    public let focusOrigin: @Sendable (AgentorSessionKey) async -> Bool

    public init(
        publishPrompt: @escaping @MainActor @Sendable (FunctionCardPrompt) -> Void,
        revokePrompt: @escaping @MainActor @Sendable (String) -> Void,
        setEditingText: @escaping @MainActor @Sendable (Bool) -> Void,
        scanIntegrations: @escaping @Sendable () async -> [AgentIntegrationStatus] = { [] },
        performIntegration: @escaping @Sendable (AgentKind, AgentIntegrationAction) async throws -> Void = { _, _ in },
        focusOrigin: @escaping @Sendable (AgentorSessionKey) async -> Bool = { _ in false }
    ) {
        self.publishPrompt = publishPrompt
        self.revokePrompt = revokePrompt
        self.setEditingText = setEditingText
        self.scanIntegrations = scanIntegrations
        self.performIntegration = performIntegration
        self.focusOrigin = focusOrigin
    }
}

@MainActor
@Observable
public final class AgentorStore {
    public private(set) var reducer = AgentorReducer()
    public private(set) var integrationStatuses: [AgentIntegrationStatus] = []
    public private(set) var isEnabled = true
    public private(set) var isScanning = false
    public private(set) var operatingAgent: AgentKind?
    public private(set) var integrationError: String?
    public private(set) var focusMessage: String?
    public private(set) var hasScanned = false

    private let dependencies: AgentorFeatureDependencies
    @ObservationIgnored private var responders: [String: @MainActor @Sendable (AgentorResponse) -> Void] = [:]
    @ObservationIgnored private var timeoutTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var noticeTasks: [AgentorSessionKey: Task<Void, Never>] = [:]

    public init(dependencies: AgentorFeatureDependencies) {
        self.dependencies = dependencies
    }

    deinit {
        timeoutTasks.values.forEach { $0.cancel() }
        noticeTasks.values.forEach { $0.cancel() }
    }

    public var sessions: [AgentorSessionState] { reducer.orderedSessions }
    public var activeSessionCount: Int { reducer.sessions.count }
    public var pendingRequestCount: Int { reducer.pendingRequests.count }
    public var hasPendingQuestions: Bool { !reducer.pendingRequests.isEmpty }

    public func pendingRequests(for session: AgentorSessionState) -> [AgentorPendingRequest] {
        session.pendingRequestIDs.compactMap { reducer.pendingRequests[$0] }
    }

    public func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        guard !enabled else { return }
        let requestIDs = reducer.reset()
        for requestID in requestIDs {
            responders.removeValue(forKey: requestID)?(.fallback(.featureDisabled))
            timeoutTasks.removeValue(forKey: requestID)?.cancel()
            dependencies.revokePrompt(questionPromptToken(requestID))
        }
        noticeTasks.values.forEach { $0.cancel() }
        noticeTasks.removeAll()
        focusMessage = nil
    }

    public func receive(_ event: AgentorEvent) {
        guard isEnabled else { return }
        apply(reducer.apply(event))
    }

    public func receive(
        _ question: AgentorQuestionRequest,
        respond: @escaping @MainActor @Sendable (AgentorResponse) -> Void
    ) {
        guard isEnabled else {
            respond(.fallback(.featureDisabled))
            return
        }
        let (effects, fallback) = reducer.open(question)
        apply(effects)
        if let fallback {
            respond(.fallback(fallback))
            return
        }
        guard question.supportsWriteback else {
            respond(.ack)
            return
        }
        responders[question.requestID] = respond
        timeoutTasks[question.requestID] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(AgentorContract.questionWaitSeconds)) }
            catch { return }
            self?.fallBack(requestID: question.requestID, reason: .timedOut, publishFailure: true)
        }
    }

    public func setDraft(_ draft: AgentorQuestionDraft, questionID: String, requestID: String) {
        reducer.setDraft(draft, questionID: questionID, requestID: requestID)
    }

    public func selectOption(requestID: String, questionID: String, wireValue: String) {
        guard let pending = reducer.pendingRequests[requestID],
              let question = pending.request.questions.first(where: { $0.id == questionID }) else { return }
        var draft = pending.drafts[questionID] ?? AgentorQuestionDraft()
        draft.usesOther = false
        if question.kind == .multiple {
            if draft.selectedValues.contains(wireValue) { draft.selectedValues.remove(wireValue) }
            else { draft.selectedValues.insert(wireValue) }
        } else {
            draft.selectedValues = [wireValue]
        }
        reducer.setDraft(draft, questionID: questionID, requestID: requestID)
        if pending.request.questions.count == 1, question.kind == .single { submit(requestID: requestID) }
    }

    public func submit(requestID: String) {
        guard let answers = reducer.markSubmitting(requestID),
              let pending = reducer.pendingRequests[requestID],
              let responder = responders.removeValue(forKey: requestID) else { return }
        timeoutTasks.removeValue(forKey: requestID)?.cancel()
        responder(.answer(answers))
        if pending.request.session.agent == .claude {
            apply(reducer.resolveRequest(requestID, upstream: false))
        }
    }

    public func answerInAgent(requestID: String) {
        guard let pending = reducer.pendingRequests[requestID] else { return }
        if pending.supportsWriteback {
            fallBack(requestID: requestID, reason: .userChoseNative, publishFailure: false)
        }
        Task { [weak self] in
            guard let self else { return }
            let focused = await dependencies.focusOrigin(resolvedKey(for: pending.request))
            await MainActor.run {
                self.focusMessage = focused ? nil : "无法定位原窗口，请手动切回 Agent。"
            }
        }
    }

    public func removeSession(_ key: AgentorSessionKey) {
        let requestIDs = reducer.removeSession(key)
        for requestID in requestIDs {
            responders.removeValue(forKey: requestID)?(.fallback(.upstreamHandled))
            timeoutTasks.removeValue(forKey: requestID)?.cancel()
            dependencies.revokePrompt(questionPromptToken(requestID))
        }
    }

    public func removeStaleSessions(now: Date = Date()) {
        let requestIDs = reducer.removeStale(before: now.addingTimeInterval(-20 * 60))
        for requestID in requestIDs {
            responders.removeValue(forKey: requestID)?(.fallback(.timedOut))
            timeoutTasks.removeValue(forKey: requestID)?.cancel()
            dependencies.revokePrompt(questionPromptToken(requestID))
        }
    }

    public func scanIfNeeded() async {
        guard !hasScanned else { return }
        await refreshIntegrations()
    }

    public func refreshIntegrations() async {
        guard !isScanning, operatingAgent == nil else { return }
        isScanning = true
        integrationError = nil
        let statuses = await dependencies.scanIntegrations()
        integrationStatuses = AgentKind.allCases.compactMap { agent in statuses.first { $0.agent == agent } }
        hasScanned = true
        isScanning = false
    }

    public func perform(_ action: AgentIntegrationAction, for agent: AgentKind) async {
        guard operatingAgent == nil, !isScanning else { return }
        operatingAgent = agent
        integrationError = nil
        do {
            try await dependencies.performIntegration(agent, action)
        } catch {
            integrationError = error.localizedDescription
        }
        operatingAgent = nil
        await refreshIntegrations()
    }

    public func setEditingText(_ editing: Bool) {
        dependencies.setEditingText(editing)
    }

    private func apply(_ effects: [AgentorReducerEffect]) {
        for effect in effects {
            switch effect {
            case let .started(key, eventID):
                guard let session = reducer.sessions[key] else { continue }
                publish(eventID: eventID, icon: "sparkles", summary: "\(key.agent.displayName) · \(session.label)", style: .activity)
            case let .ended(key, outcome, _, eventID):
                let style: FunctionCardPromptStyle = outcome == .normal ? .success : .failure
                let icon = outcome == .normal ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                let prefix = outcome == .normal ? "已完成" : (outcome == .cancel ? "已取消" : "执行失败")
                publish(eventID: eventID, icon: icon, summary: "\(prefix) · \(key.agent.displayName)", style: style)
            case let .requestOpened(key, requestID):
                guard let session = reducer.sessions[key] else { continue }
                dependencies.publishPrompt(FunctionCardPrompt(
                    token: questionPromptToken(requestID), sourceID: .agentor,
                    systemImage: "questionmark.circle.fill", moduleName: "Agentor",
                    summary: "等待回答 · \(key.agent.displayName) · \(session.label)", style: .attention
                ))
            case let .requestResolved(key, requestID, upstream):
                responders.removeValue(forKey: requestID)?(.fallback(.upstreamHandled))
                timeoutTasks.removeValue(forKey: requestID)?.cancel()
                dependencies.revokePrompt(questionPromptToken(requestID))
                if upstream { scheduleNoticeClear(for: key) }
            case let .writebackFailed(key, requestID):
                publish(eventID: "writeback:\(requestID)", icon: "exclamationmark.triangle.fill", summary: "回答写回失败 · \(key.agent.displayName)", style: .failure)
            case .droppedCapacity:
                break
            }
        }
    }

    private func fallBack(requestID: String, reason: AgentorFallbackReason, publishFailure: Bool) {
        guard reducer.pendingRequests[requestID] != nil else { return }
        responders.removeValue(forKey: requestID)?(.fallback(reason))
        timeoutTasks.removeValue(forKey: requestID)?.cancel()
        let pending = reducer.pendingRequests[requestID]
        apply(reducer.resolveRequest(requestID, upstream: false))
        if publishFailure, let pending {
            publish(
                eventID: "fallback:\(requestID)", icon: "exclamationmark.triangle.fill",
                summary: "回答超时 · \(pending.request.session.agent.displayName)", style: .failure
            )
        }
    }

    private func publish(eventID: String, icon: String, summary: String, style: FunctionCardPromptStyle) {
        dependencies.publishPrompt(FunctionCardPrompt(
            token: "agentor:event:\(eventID)", sourceID: .agentor,
            systemImage: icon, moduleName: "Agentor", summary: summary, style: style
        ))
    }

    private func questionPromptToken(_ requestID: String) -> String {
        "agentor:question:\(requestID)"
    }

    private func resolvedKey(for request: AgentorQuestionRequest) -> AgentorSessionKey {
        guard let parent = request.parentSessionID, !parent.isEmpty else { return request.session }
        return AgentorSessionKey(agent: request.session.agent, sessionID: parent)
    }

    private func scheduleNoticeClear(for key: AgentorSessionKey) {
        noticeTasks[key]?.cancel()
        noticeTasks[key] = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            self?.reducer.clearResolutionNotice(for: key)
            self?.noticeTasks.removeValue(forKey: key)
        }
    }
}
