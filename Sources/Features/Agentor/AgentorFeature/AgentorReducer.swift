import AgentorProtocol
import Foundation

public enum AgentorExecutionStatus: String, Sendable, Equatable {
    case thinking
    case runningTool
    case waitingForAnswer

    public var displayName: String {
        switch self {
        case .thinking: "思考中"
        case .runningTool: "执行工具"
        case .waitingForAnswer: "等待回答"
        }
    }
}

public enum AgentorRequestStatus: String, Sendable, Equatable {
    case waiting
    case submitting
    case readOnly
}

public struct AgentorQuestionDraft: Sendable, Equatable {
    public var selectedValues: Set<String> = []
    public var text = ""
    public var otherText = ""
    public var usesOther = false

    public init() {}
}

public struct AgentorPendingRequest: Identifiable, Sendable, Equatable {
    public let request: AgentorQuestionRequest
    public let isSchemaSafe: Bool
    public var status: AgentorRequestStatus
    public var drafts: [String: AgentorQuestionDraft]

    public var id: String { request.requestID }
    public var supportsWriteback: Bool { isSchemaSafe && request.supportsWriteback && status != .readOnly }

    public init(request: AgentorQuestionRequest, isSchemaSafe: Bool) {
        self.request = request
        self.isSchemaSafe = isSchemaSafe
        status = isSchemaSafe && request.supportsWriteback ? .waiting : .readOnly
        drafts = Dictionary(uniqueKeysWithValues: request.questions.map { ($0.id, AgentorQuestionDraft()) })
    }

    public var isSubmittable: Bool {
        guard supportsWriteback, status == .waiting else { return false }
        return request.questions.allSatisfy { question in
            guard question.isRequired else { return true }
            let draft = drafts[question.id] ?? AgentorQuestionDraft()
            if draft.usesOther { return !draft.otherText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            switch question.kind {
            case .single, .multiple: return !draft.selectedValues.isEmpty
            case .text: return !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    public func answers() -> [AgentorAnswer]? {
        guard isSubmittable else { return nil }
        return request.questions.map { question in
            let draft = drafts[question.id] ?? AgentorQuestionDraft()
            let values: [String]
            if draft.usesOther {
                values = [draft.otherText]
            } else if question.kind == .text {
                values = [draft.text]
            } else {
                values = question.options.compactMap { draft.selectedValues.contains($0.wireValue) ? $0.wireValue : nil }
            }
            return AgentorAnswer(questionID: question.id, answerKey: question.answerKey, values: values)
        }
    }
}

public struct AgentorSessionState: Identifiable, Sendable, Equatable {
    public let key: AgentorSessionKey
    public var turnID: String?
    public var generation: UInt64
    public var startedAt: Date
    public var lastEventAt: Date
    public var title: String?
    public var workingDirectoryName: String?
    public var process: AgentorProcessIdentity?
    public var activeToolIDs: Set<String>
    public var completedToolIDs: [String]
    public var activeSubagentIDs: Set<String>
    public var pendingRequestIDs: [String]
    public var recentEventIDs: [String]
    public var resolutionNotice: String?

    public var id: AgentorSessionKey { key }

    public var status: AgentorExecutionStatus {
        if !pendingRequestIDs.isEmpty { return .waitingForAnswer }
        if !activeToolIDs.isEmpty { return .runningTool }
        return .thinking
    }

    public var label: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        if let workingDirectoryName, !workingDirectoryName.isEmpty { return workingDirectoryName }
        return "\(key.agent.displayName) · \(String(key.sessionID.prefix(8)))"
    }
}

public enum AgentorReducerEffect: Sendable, Equatable {
    case started(AgentorSessionKey, eventID: String)
    case ended(AgentorSessionKey, AgentorTurnOutcome, label: String, eventID: String)
    case requestOpened(AgentorSessionKey, String)
    case requestResolved(AgentorSessionKey, String, upstream: Bool)
    case writebackFailed(AgentorSessionKey, String)
    case droppedCapacity
}

private struct AgentorTerminalWatermark: Sendable, Equatable {
    let turnID: String?
    let occurredAt: Date
}

public struct AgentorReducer: Sendable, Equatable {
    public private(set) var sessions: [AgentorSessionKey: AgentorSessionState] = [:]
    public private(set) var pendingRequests: [String: AgentorPendingRequest] = [:]
    private var terminalWatermarks: [AgentorSessionKey: AgentorTerminalWatermark] = [:]
    private var terminalWatermarkOrder: [AgentorSessionKey] = []
    private var nextGeneration: UInt64 = 1

    public init() {}

    public var orderedSessions: [AgentorSessionState] {
        sessions.values.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            if $0.key.agent != $1.key.agent { return $0.key.agent.rawValue < $1.key.agent.rawValue }
            return $0.key.sessionID < $1.key.sessionID
        }
    }

    public mutating func apply(_ event: AgentorEvent) -> [AgentorReducerEffect] {
        let key = resolvedKey(session: event.session, parentSessionID: event.parentSessionID)
        if event.name == .questionResolved || event.name == .writebackSucceeded || event.name == .writebackFailed {
            guard let requestID = event.requestID else { return [] }
            let wasFailure = event.name == .writebackFailed
            let effects = resolveRequest(requestID, upstream: event.name == .questionResolved)
            if wasFailure { return effects + [.writebackFailed(key, requestID)] }
            return effects
        }
        if event.name == .turnEnded {
            return terminate(key: key, event: event)
        }

        let isExplicitStart = event.name == .turnStarted
        if let watermark = terminalWatermarks[key] {
            let sameTurn = event.turnID != nil && event.turnID == watermark.turnID
            guard isExplicitStart, !sameTurn, event.occurredAt > watermark.occurredAt else { return [] }
            terminalWatermarks.removeValue(forKey: key)
            terminalWatermarkOrder.removeAll { $0 == key }
        }

        if var existing = sessions[key] {
            guard !existing.recentEventIDs.contains(event.eventID) else { return [] }
            if let currentTurn = existing.turnID, let incomingTurn = event.turnID, currentTurn != incomingTurn {
                guard isExplicitStart else { return [] }
                existing = makeSession(key: key, event: event)
                sessions[key] = existing
                return [.started(key, eventID: event.eventID)]
            }
            if isExplicitStart, existing.turnID == nil || event.turnID == nil {
                guard event.occurredAt > existing.lastEventAt else { return [] }
                let requestEffects = existing.pendingRequestIDs.map {
                    pendingRequests.removeValue(forKey: $0)
                    return AgentorReducerEffect.requestResolved(key, $0, upstream: true)
                }
                sessions[key] = makeSession(key: key, event: event)
                return requestEffects + [.started(key, eventID: event.eventID)]
            }
            guard event.occurredAt >= existing.lastEventAt else { return [] }
            applyMetadata(event, to: &existing)
            applyEvent(event, to: &existing)
            sessions[key] = existing
            return []
        }

        guard event.name != .toolFinished,
              event.name != .subagentFinished,
              event.name != .heartbeat || isExplicitStart else { return [] }
        guard sessions.count < AgentorContract.maximumActiveSessions else { return [.droppedCapacity] }
        let session = makeSession(key: key, event: event)
        sessions[key] = session
        return isExplicitStart ? [.started(key, eventID: event.eventID)] : []
    }

    public mutating func open(_ request: AgentorQuestionRequest) -> ([AgentorReducerEffect], AgentorFallbackReason?) {
        guard !request.requestID.isEmpty else { return ([], .invalidRequest) }
        guard pendingRequests[request.requestID] == nil else { return ([], .upstreamHandled) }
        guard pendingRequests.count < AgentorContract.maximumPendingRequests else { return ([.droppedCapacity], .capacityExceeded) }
        let key = resolvedKey(session: request.session, parentSessionID: request.parentSessionID)
        if sessions[key] == nil {
            guard sessions.count < AgentorContract.maximumActiveSessions else { return ([.droppedCapacity], .capacityExceeded) }
            let event = AgentorEvent(
                eventID: "question:\(request.requestID)", occurredAt: request.occurredAt,
                session: key, turnID: request.turnID, title: request.title,
                workingDirectoryName: request.workingDirectoryName, process: request.process,
                name: .thinking
            )
            sessions[key] = makeSession(key: key, event: event)
        }
        let safe = request.validationFailure == nil
        pendingRequests[request.requestID] = AgentorPendingRequest(request: request, isSchemaSafe: safe)
        var session = sessions[key]!
        if !session.pendingRequestIDs.contains(request.requestID) { session.pendingRequestIDs.append(request.requestID) }
        session.lastEventAt = max(session.lastEventAt, request.occurredAt)
        sessions[key] = session
        return ([.requestOpened(key, request.requestID)], safe ? nil : .invalidRequest)
    }

    public mutating func resolveRequest(_ requestID: String, upstream: Bool) -> [AgentorReducerEffect] {
        guard let pending = pendingRequests.removeValue(forKey: requestID) else { return [] }
        let key = resolvedKey(session: pending.request.session, parentSessionID: pending.request.parentSessionID)
        if var session = sessions[key] {
            session.pendingRequestIDs.removeAll { $0 == requestID }
            session.resolutionNotice = upstream ? "已在 Agent 端处理" : nil
            sessions[key] = session
        }
        return [.requestResolved(key, requestID, upstream: upstream)]
    }

    public mutating func setDraft(_ draft: AgentorQuestionDraft, questionID: String, requestID: String) {
        guard var request = pendingRequests[requestID], request.status == .waiting else { return }
        request.drafts[questionID] = draft
        pendingRequests[requestID] = request
    }

    public mutating func markSubmitting(_ requestID: String) -> [AgentorAnswer]? {
        guard var request = pendingRequests[requestID], let answers = request.answers() else { return nil }
        request.status = .submitting
        pendingRequests[requestID] = request
        return answers
    }

    public mutating func clearResolutionNotice(for key: AgentorSessionKey) {
        guard var session = sessions[key] else { return }
        session.resolutionNotice = nil
        sessions[key] = session
    }

    public mutating func removeSession(_ key: AgentorSessionKey) -> [String] {
        guard let session = sessions.removeValue(forKey: key) else { return [] }
        let requests = session.pendingRequestIDs
        requests.forEach { pendingRequests.removeValue(forKey: $0) }
        return requests
    }

    public mutating func removeStale(before cutoff: Date) -> [String] {
        let keys = sessions.values.filter { $0.lastEventAt < cutoff }.map(\.key)
        return keys.flatMap { removeSession($0) }
    }

    public mutating func reset() -> [String] {
        let requestIDs = Array(pendingRequests.keys)
        sessions.removeAll()
        pendingRequests.removeAll()
        terminalWatermarks.removeAll()
        terminalWatermarkOrder.removeAll()
        return requestIDs
    }

    private mutating func makeSession(key: AgentorSessionKey, event: AgentorEvent) -> AgentorSessionState {
        defer { nextGeneration &+= 1 }
        var session = AgentorSessionState(
            key: key, turnID: event.turnID, generation: nextGeneration,
            startedAt: event.occurredAt, lastEventAt: event.occurredAt,
            title: event.title, workingDirectoryName: event.workingDirectoryName,
            process: event.process, activeToolIDs: [], completedToolIDs: [],
            activeSubagentIDs: [], pendingRequestIDs: [], recentEventIDs: [], resolutionNotice: nil
        )
        applyEvent(event, to: &session)
        return session
    }

    private func applyMetadata(_ event: AgentorEvent, to session: inout AgentorSessionState) {
        session.lastEventAt = event.occurredAt
        if let title = event.title, !title.isEmpty { session.title = title }
        if let name = event.workingDirectoryName, !name.isEmpty { session.workingDirectoryName = name }
        if let process = event.process { session.process = process }
    }

    private func applyEvent(_ event: AgentorEvent, to session: inout AgentorSessionState) {
        appendBounded(event.eventID, to: &session.recentEventIDs)
        switch event.name {
        case .toolStarted:
            if let id = event.toolID, !session.completedToolIDs.contains(id), session.activeToolIDs.count < 100 {
                session.activeToolIDs.insert(id)
            }
        case .toolFinished:
            if let id = event.toolID {
                session.activeToolIDs.remove(id)
                appendBounded(id, to: &session.completedToolIDs)
            }
        case .subagentStarted:
            if let id = event.subagentID, session.activeSubagentIDs.count < 100 { session.activeSubagentIDs.insert(id) }
        case .subagentFinished:
            if let id = event.subagentID { session.activeSubagentIDs.remove(id) }
        default:
            break
        }
    }

    private mutating func terminate(key: AgentorSessionKey, event: AgentorEvent) -> [AgentorReducerEffect] {
        guard let session = sessions[key] else {
            setTerminalWatermark(key, turnID: event.turnID, occurredAt: event.occurredAt)
            return []
        }
        if let currentTurn = session.turnID, let incomingTurn = event.turnID, currentTurn != incomingTurn { return [] }
        guard event.occurredAt >= session.lastEventAt else { return [] }
        let requestIDs = removeSession(key)
        setTerminalWatermark(key, turnID: event.turnID, occurredAt: event.occurredAt)
        let outcome = event.outcome ?? .normal
        var effects = requestIDs.map { AgentorReducerEffect.requestResolved(key, $0, upstream: true) }
        effects.append(.ended(key, outcome, label: session.label, eventID: event.eventID))
        return effects
    }

    private mutating func setTerminalWatermark(_ key: AgentorSessionKey, turnID: String?, occurredAt: Date) {
        terminalWatermarks[key] = AgentorTerminalWatermark(turnID: turnID, occurredAt: occurredAt)
        terminalWatermarkOrder.removeAll { $0 == key }
        terminalWatermarkOrder.append(key)
        while terminalWatermarkOrder.count > AgentorContract.maximumActiveSessions {
            terminalWatermarks.removeValue(forKey: terminalWatermarkOrder.removeFirst())
        }
    }

    private func resolvedKey(session: AgentorSessionKey, parentSessionID: String?) -> AgentorSessionKey {
        guard let parentSessionID, !parentSessionID.isEmpty else { return session }
        return AgentorSessionKey(agent: session.agent, sessionID: parentSessionID)
    }

    private func appendBounded(_ value: String, to values: inout [String]) {
        guard !values.contains(value) else { return }
        values.append(value)
        if values.count > 100 { values.removeFirst(values.count - 100) }
    }
}
