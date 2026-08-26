import AgentorProtocol
import Darwin
import Foundation

nonisolated enum CodexTranscriptMessage: Sendable {
    case question(AgentorQuestionRequest)
    case resolved(AgentorSessionKey, requestID: String, eventID: String, occurredAt: Date)
    case aborted(AgentorSessionKey, turnID: String?, outcome: AgentorTurnOutcome, eventID: String, occurredAt: Date)
}

final class CodexTranscriptMonitor: @unchecked Sendable {
    typealias Handler = @Sendable (CodexTranscriptMessage) async -> Void

    private final class Entry: @unchecked Sendable {
        let descriptor: Int32
        let source: any DispatchSourceFileSystemObject
        let session: AgentorSessionKey
        let turnID: String?
        var offset: off_t
        var buffer = Data()

        init(descriptor: Int32, source: any DispatchSourceFileSystemObject, session: AgentorSessionKey, turnID: String?, offset: off_t) {
            self.descriptor = descriptor
            self.source = source
            self.session = session
            self.turnID = turnID
            self.offset = offset
        }
    }

    private let handler: Handler
    private let queue = DispatchQueue(label: "com.scpz24.Peeker.agentor.codex-transcript", qos: .utility)
    private let lock = NSLock()
    private var entries: [AgentorSessionKey: Entry] = [:]

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    deinit { stopAll() }

    func watch(path: String, session: AgentorSessionKey, turnID: String?) {
        guard session.agent == .codex, validatedURL(path) != nil else { return }
        lock.lock()
        if entries[session] != nil { lock.unlock(); return }
        lock.unlock()

        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { return }
        let offset = lseek(descriptor, 0, SEEK_END)
        guard offset >= 0 else { _ = Darwin.close(descriptor); return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: queue
        )
        let entry = Entry(descriptor: descriptor, source: source, session: session, turnID: turnID, offset: offset)
        source.setEventHandler { [weak self, weak entry] in
            guard let self, let entry else { return }
            let events = entry.source.data
            if !events.intersection([.delete, .rename, .revoke]).isEmpty {
                self.stop(session: entry.session)
                return
            }
            self.readAvailable(entry)
        }
        source.setCancelHandler { _ = Darwin.close(descriptor) }
        lock.lock()
        guard entries[session] == nil else {
            lock.unlock()
            source.cancel()
            return
        }
        entries[session] = entry
        lock.unlock()
        source.resume()
    }

    func stop(session: AgentorSessionKey) {
        lock.lock()
        let entry = entries.removeValue(forKey: session)
        lock.unlock()
        entry?.source.cancel()
    }

    func stopAll() {
        lock.lock()
        let values = Array(entries.values)
        entries.removeAll()
        lock.unlock()
        values.forEach { $0.source.cancel() }
    }

    private func readAvailable(_ entry: Entry) {
        var chunk = Data(count: 32 * 1024)
        while true {
            let count = chunk.withUnsafeMutableBytes { buffer in
                pread(entry.descriptor, buffer.baseAddress, buffer.count, entry.offset)
            }
            if count > 0 {
                entry.offset += off_t(count)
                entry.buffer.append(chunk.prefix(count))
                if entry.buffer.count > AgentorContract.maximumFrameBytes {
                    entry.buffer.removeAll()
                    return
                }
                consumeLines(entry)
                continue
            }
            if count < 0, errno == EINTR { continue }
            return
        }
    }

    private func consumeLines(_ entry: Entry) {
        while let newline = entry.buffer.firstIndex(of: 0x0A) {
            let line = entry.buffer[..<newline]
            entry.buffer.removeSubrange(...newline)
            guard line.count <= AgentorContract.maximumFrameBytes,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let message = Self.parse(object, session: entry.session, turnID: entry.turnID) else { continue }
            Task { await handler(message) }
        }
    }

    static func parse(
        _ object: [String: Any],
        session: AgentorSessionKey,
        turnID: String?
    ) -> CodexTranscriptMessage? {
        let payload = object["payload"] as? [String: Any]
        let payloadType = payload?["type"] as? String
        let occurredAt = parseDate(object["timestamp"] as? String)
        if object["type"] as? String == "response_item", payloadType == "function_call",
           payload?["name"] as? String == "request_user_input",
           let requestID = payload?["call_id"] as? String,
           let arguments = payload?["arguments"] as? String,
           let data = arguments.data(using: .utf8), data.count <= AgentorContract.maximumFrameBytes,
           let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let questions = parseQuestions(input["questions"] as? [[String: Any]]) {
            return .question(AgentorQuestionRequest(
                requestID: requestID, occurredAt: occurredAt, session: session, turnID: turnID,
                supportsWriteback: false, questions: questions
            ))
        }
        if object["type"] as? String == "response_item", payloadType == "function_call_output",
           let requestID = payload?["call_id"] as? String {
            return .resolved(session, requestID: requestID, eventID: "codex:resolved:\(requestID)", occurredAt: occurredAt)
        }
        if object["type"] as? String == "event_msg", payloadType == "turn_aborted" {
            let reason = payload?["reason"] as? String
            let activeTurn = payload?["turn_id"] as? String ?? turnID
            let eventID = "codex:aborted:\(activeTurn ?? String(occurredAt.timeIntervalSince1970))"
            return .aborted(
                session, turnID: activeTurn, outcome: reason == "interrupted" ? .cancel : .failure,
                eventID: eventID, occurredAt: occurredAt
            )
        }
        return nil
    }

    private static func parseQuestions(_ values: [[String: Any]]?) -> [AgentorQuestion]? {
        guard let values, !values.isEmpty else { return nil }
        return values.enumerated().map { index, value in
            let id = value["id"] as? String ?? ""
            let body = value["question"] as? String ?? ""
            let rawOptions = value["options"] as? [[String: Any]] ?? []
            let parsedOptions = rawOptions.enumerated().compactMap { optionIndex, option -> AgentorQuestionOption? in
                guard let label = option["label"] as? String else { return nil }
                return AgentorQuestionOption(
                    id: "\(index)-\(optionIndex)", label: label,
                    detail: option["description"] as? String, wireValue: label
                )
            }
            return AgentorQuestion(
                id: id, answerKey: id, title: value["header"] as? String, body: body,
                kind: rawOptions.isEmpty ? .text : .single,
                options: parsedOptions.count == rawOptions.count ? parsedOptions : [],
                allowsOther: false, isRequired: true
            )
        }
    }

    private func validatedURL(_ path: String) -> URL? {
        let original = URL(fileURLWithPath: path)
        let resolved = original.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved.path == root || resolved.path.hasPrefix(root + "/") else { return nil }
        var metadata = stat()
        guard lstat(original.path, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_uid == geteuid() else { return nil }
        return resolved
    }

    private static func parseDate(_ value: String?) -> Date {
        guard let value else { return Date() }
        return ISO8601DateFormatter().date(from: value) ?? Date()
    }
}
