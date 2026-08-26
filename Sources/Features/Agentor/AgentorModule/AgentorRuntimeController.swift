import AgentorFeature
import AgentorProtocol
import Foundation

@MainActor
final class AgentorRuntimeController {
    let store: AgentorStore
    private let socketURL: URL
    private var server: AgentorIPCServer?
    private var cleanupTask: Task<Void, Never>?
    private var processSources: [AgentorSessionKey: any DispatchSourceProcess] = [:]
    private var origins: [AgentorSessionKey: AgentorOriginIdentity] = [:]
    private var isRunning = false
    private lazy var codexMonitor = CodexTranscriptMonitor { [weak self] message in
        await self?.handleCodexMessage(message)
    }

    init(store: AgentorStore, socketURL: URL = AgentorPaths.socketURL()) {
        self.store = store
        self.socketURL = socketURL
    }

    deinit {
        cleanupTask?.cancel()
        processSources.values.forEach { $0.cancel() }
        server?.stop()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { start() }
        else { stop() }
    }

    func focusOrigin(_ key: AgentorSessionKey) -> Bool {
        guard let identity = origins[key] else { return false }
        return AgentorProcessInspector.activate(identity)
    }

    private func start() {
        guard !isRunning else { return }
        store.setEnabled(true)
        let server = AgentorIPCServer(socketURL: socketURL) { [weak self] request in
            guard let self else { return .fallback(.appUnavailable) }
            return await self.handle(request)
        }
        do {
            try server.start()
            self.server = server
            isRunning = true
            cleanupTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) }
                    catch { return }
                    guard let self else { return }
                    let before = Set(self.store.sessions.map(\.key))
                    self.store.removeStaleSessions()
                    let after = Set(self.store.sessions.map(\.key))
                    for key in before.subtracting(after) { self.cleanup(key) }
                }
            }
        } catch {
            store.setEnabled(false)
        }
    }

    private func stop() {
        guard isRunning || store.isEnabled else { return }
        store.setEnabled(false)
        cleanupTask?.cancel()
        cleanupTask = nil
        processSources.values.forEach { $0.cancel() }
        processSources.removeAll()
        origins.removeAll()
        codexMonitor.stopAll()
        server?.stop()
        server = nil
        isRunning = false
    }

    private func handle(_ request: AgentorRequest) async -> AgentorResponse {
        guard isRunning, store.isEnabled else { return .fallback(.featureDisabled) }
        switch request.kind {
        case .event:
            guard let event = request.event else { return .rejected("invalid_event") }
            captureRuntimeMetadata(event.session, parentSessionID: event.parentSessionID, process: event.process)
            if event.session.agent == .codex, let path = event.transcriptPath {
                codexMonitor.watch(path: path, session: event.session, turnID: event.turnID)
            }
            store.receive(event)
            if event.name == .turnEnded { cleanup(event.session, parentSessionID: event.parentSessionID) }
            return .ack
        case .question:
            guard let question = request.question else { return .rejected("invalid_question") }
            captureRuntimeMetadata(question.session, parentSessionID: question.parentSessionID, process: question.process)
            return await withCheckedContinuation { continuation in
                store.receive(question) { response in continuation.resume(returning: response) }
            }
        }
    }

    private func captureRuntimeMetadata(
        _ session: AgentorSessionKey,
        parentSessionID: String?,
        process: AgentorProcessIdentity?
    ) {
        guard let process else { return }
        let key = resolvedKey(session, parentSessionID: parentSessionID)
        if origins[key] == nil, let origin = AgentorProcessInspector.nearestRunningApplication(from: process.pid) {
            origins[key] = origin
        }
        guard process.scope == .session, processSources[key] == nil,
              let inspected = AgentorProcessInspector.processInfo(process.pid),
              AgentorProcessInspector.startTimeMatches(process.startedAt, actual: inspected.startedAt) else { return }
        let source = DispatchSource.makeProcessSource(identifier: process.pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            self?.store.removeSession(key)
            self?.cleanup(key)
        }
        processSources[key] = source
        source.resume()
    }

    private func cleanup(_ session: AgentorSessionKey, parentSessionID: String?) {
        cleanup(resolvedKey(session, parentSessionID: parentSessionID))
    }

    private func cleanup(_ key: AgentorSessionKey) {
        processSources.removeValue(forKey: key)?.cancel()
        origins.removeValue(forKey: key)
        codexMonitor.stop(session: key)
    }

    private func resolvedKey(_ session: AgentorSessionKey, parentSessionID: String?) -> AgentorSessionKey {
        guard let parentSessionID, !parentSessionID.isEmpty else { return session }
        return AgentorSessionKey(agent: session.agent, sessionID: parentSessionID)
    }

    private func handleCodexMessage(_ message: CodexTranscriptMessage) {
        switch message {
        case let .question(request):
            store.receive(request) { _ in }
        case let .resolved(session, requestID, eventID, occurredAt):
            store.receive(AgentorEvent(
                eventID: eventID, occurredAt: occurredAt, session: session,
                name: .questionResolved, requestID: requestID
            ))
        case let .aborted(session, turnID, outcome, eventID, occurredAt):
            store.receive(AgentorEvent(
                eventID: eventID, occurredAt: occurredAt, session: session, turnID: turnID,
                name: .turnEnded, outcome: outcome
            ))
            cleanup(session)
        }
    }
}
