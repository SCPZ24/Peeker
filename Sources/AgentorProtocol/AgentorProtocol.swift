import Foundation

public enum AgentorContract {
    public static let schemaVersion = 1
    public static let maximumFrameBytes = 512 * 1024
    public static let maximumActiveSessions = 100
    public static let maximumPendingRequests = 100
    public static let maximumQuestions = 5
    public static let maximumOptions = 5
    public static let maximumIdentifierBytes = 1_024
    public static let questionWaitSeconds: TimeInterval = 590
}

public enum AgentKind: String, CaseIterable, Codable, Sendable, Equatable, Identifiable {
    case claude
    case openCode = "opencode"
    case hermes
    case pi
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .openCode: "OpenCode"
        case .hermes: "Hermes"
        case .pi: "Pi"
        case .codex: "Codex"
        }
    }
}

public struct AgentorSessionKey: Hashable, Codable, Sendable {
    public let agent: AgentKind
    public let sessionID: String

    public init(agent: AgentKind, sessionID: String) {
        self.agent = agent
        self.sessionID = sessionID
    }
}

public enum AgentorProcessScope: String, Codable, Sendable, Equatable {
    case session
    case shared
    case unknown
}

public struct AgentorProcessIdentity: Codable, Sendable, Equatable {
    public let pid: Int32
    public let startedAt: Date?
    public let scope: AgentorProcessScope

    public init(pid: Int32, startedAt: Date? = nil, scope: AgentorProcessScope = .unknown) {
        self.pid = pid
        self.startedAt = startedAt
        self.scope = scope
    }
}

public enum AgentorTurnOutcome: String, Codable, Sendable, Equatable {
    case normal
    case failure
    case cancel
}

public enum AgentorEventName: String, Codable, Sendable, Equatable {
    case turnStarted
    case thinking
    case toolStarted
    case toolFinished
    case questionResolved
    case subagentStarted
    case subagentFinished
    case turnEnded
    case heartbeat
    case writebackSucceeded
    case writebackFailed
}

public struct AgentorEvent: Codable, Sendable, Equatable {
    public let eventID: String
    public let occurredAt: Date
    public let session: AgentorSessionKey
    public let turnID: String?
    public let parentSessionID: String?
    public let title: String?
    public let workingDirectoryName: String?
    public let process: AgentorProcessIdentity?
    public let name: AgentorEventName
    public let toolID: String?
    public let subagentID: String?
    public let requestID: String?
    public let outcome: AgentorTurnOutcome?
    public let transcriptPath: String?

    public init(
        eventID: String,
        occurredAt: Date = Date(),
        session: AgentorSessionKey,
        turnID: String? = nil,
        parentSessionID: String? = nil,
        title: String? = nil,
        workingDirectoryName: String? = nil,
        process: AgentorProcessIdentity? = nil,
        name: AgentorEventName,
        toolID: String? = nil,
        subagentID: String? = nil,
        requestID: String? = nil,
        outcome: AgentorTurnOutcome? = nil,
        transcriptPath: String? = nil
    ) {
        self.eventID = eventID
        self.occurredAt = occurredAt
        self.session = session
        self.turnID = turnID
        self.parentSessionID = parentSessionID
        self.title = title
        self.workingDirectoryName = workingDirectoryName
        self.process = process
        self.name = name
        self.toolID = toolID
        self.subagentID = subagentID
        self.requestID = requestID
        self.outcome = outcome
        self.transcriptPath = transcriptPath
    }
}

public enum AgentorQuestionKind: String, Codable, Sendable, Equatable {
    case single
    case multiple
    case text
}

public struct AgentorQuestionOption: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let detail: String?
    public let wireValue: String

    public init(id: String, label: String, detail: String? = nil, wireValue: String) {
        self.id = id
        self.label = label
        self.detail = detail
        self.wireValue = wireValue
    }
}

public struct AgentorQuestion: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let answerKey: String
    public let title: String?
    public let body: String
    public let kind: AgentorQuestionKind
    public let options: [AgentorQuestionOption]
    public let allowsOther: Bool
    public let isRequired: Bool

    public init(
        id: String,
        answerKey: String,
        title: String? = nil,
        body: String,
        kind: AgentorQuestionKind,
        options: [AgentorQuestionOption] = [],
        allowsOther: Bool = false,
        isRequired: Bool = true
    ) {
        self.id = id
        self.answerKey = answerKey
        self.title = title
        self.body = body
        self.kind = kind
        self.options = options
        self.allowsOther = allowsOther
        self.isRequired = isRequired
    }
}

public struct AgentorQuestionRequest: Codable, Sendable, Equatable, Identifiable {
    public let requestID: String
    public let occurredAt: Date
    public let session: AgentorSessionKey
    public let turnID: String?
    public let parentSessionID: String?
    public let title: String?
    public let workingDirectoryName: String?
    public let process: AgentorProcessIdentity?
    public let supportsWriteback: Bool
    public let questions: [AgentorQuestion]

    public var id: String { requestID }

    public init(
        requestID: String,
        occurredAt: Date = Date(),
        session: AgentorSessionKey,
        turnID: String? = nil,
        parentSessionID: String? = nil,
        title: String? = nil,
        workingDirectoryName: String? = nil,
        process: AgentorProcessIdentity? = nil,
        supportsWriteback: Bool,
        questions: [AgentorQuestion]
    ) {
        self.requestID = requestID
        self.occurredAt = occurredAt
        self.session = session
        self.turnID = turnID
        self.parentSessionID = parentSessionID
        self.title = title
        self.workingDirectoryName = workingDirectoryName
        self.process = process
        self.supportsWriteback = supportsWriteback
        self.questions = questions
    }

    public var validationFailure: AgentorValidationError? {
        guard Self.validIdentifier(requestID) else { return .invalidIdentifier }
        guard !questions.isEmpty, questions.count <= AgentorContract.maximumQuestions else {
            return .invalidQuestionCount
        }
        var answerKeys = Set<String>()
        for question in questions {
            guard Self.validIdentifier(question.id),
                  !question.answerKey.isEmpty,
                  !question.body.isEmpty else {
                return .invalidIdentifier
            }
            guard answerKeys.insert(question.answerKey).inserted else { return .duplicateAnswerKey }
            guard question.options.count <= AgentorContract.maximumOptions else { return .invalidOptionCount }
            if question.kind == .text, !question.options.isEmpty { return .invalidQuestionShape }
            if question.kind != .text, question.options.isEmpty { return .invalidQuestionShape }
            var optionIDs = Set<String>()
            for option in question.options {
                guard Self.validIdentifier(option.id),
                      !option.label.isEmpty,
                      !option.wireValue.isEmpty,
                      optionIDs.insert(option.id).inserted else {
                    return .invalidIdentifier
                }
            }
        }
        return nil
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.lengthOfBytes(using: .utf8) <= AgentorContract.maximumIdentifierBytes
    }
}

public struct AgentorAnswer: Codable, Sendable, Equatable {
    public let questionID: String
    public let answerKey: String
    public let values: [String]

    public init(questionID: String, answerKey: String, values: [String]) {
        self.questionID = questionID
        self.answerKey = answerKey
        self.values = values
    }
}

public enum AgentorRequestKind: String, Codable, Sendable, Equatable {
    case event
    case question
}

public struct AgentorRequest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let kind: AgentorRequestKind
    public let event: AgentorEvent?
    public let question: AgentorQuestionRequest?

    public init(event: AgentorEvent) {
        schemaVersion = AgentorContract.schemaVersion
        kind = .event
        self.event = event
        question = nil
    }

    public init(question: AgentorQuestionRequest) {
        schemaVersion = AgentorContract.schemaVersion
        kind = .question
        event = nil
        self.question = question
    }

    public func validate() throws {
        guard schemaVersion == AgentorContract.schemaVersion else { throw AgentorValidationError.protocolMismatch }
        switch kind {
        case .event:
            guard let event, question == nil,
                  validIdentifier(event.eventID),
                  validIdentifier(event.session.sessionID),
                  validOptionalIdentifier(event.turnID),
                  validOptionalIdentifier(event.parentSessionID),
                  validOptionalIdentifier(event.toolID),
                  validOptionalIdentifier(event.subagentID),
                  validOptionalIdentifier(event.requestID) else {
                throw AgentorValidationError.invalidEnvelope
            }
        case .question:
            guard event == nil, let question else { throw AgentorValidationError.invalidEnvelope }
            guard validIdentifier(question.session.sessionID),
                  validOptionalIdentifier(question.turnID),
                  validOptionalIdentifier(question.parentSessionID) else {
                throw AgentorValidationError.invalidIdentifier
            }
        }
    }

    private func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.lengthOfBytes(using: .utf8) <= AgentorContract.maximumIdentifierBytes
    }

    private func validOptionalIdentifier(_ value: String?) -> Bool {
        value.map(validIdentifier) ?? true
    }
}

public enum AgentorFallbackReason: String, Codable, Sendable, Equatable {
    case appUnavailable
    case featureDisabled
    case invalidRequest
    case capacityExceeded
    case timedOut
    case userChoseNative
    case upstreamHandled
    case writebackUnavailable
    case writebackFailed
}

public enum AgentorResponseKind: String, Codable, Sendable, Equatable {
    case ack
    case answer
    case nativeFallback
    case rejected
}

public struct AgentorResponse: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let kind: AgentorResponseKind
    public let answers: [AgentorAnswer]
    public let fallbackReason: AgentorFallbackReason?
    public let rejectionCode: String?

    public init(
        kind: AgentorResponseKind,
        answers: [AgentorAnswer] = [],
        fallbackReason: AgentorFallbackReason? = nil,
        rejectionCode: String? = nil
    ) {
        schemaVersion = AgentorContract.schemaVersion
        self.kind = kind
        self.answers = answers
        self.fallbackReason = fallbackReason
        self.rejectionCode = rejectionCode
    }

    public static let ack = AgentorResponse(kind: .ack)

    public static func answer(_ values: [AgentorAnswer]) -> AgentorResponse {
        AgentorResponse(kind: .answer, answers: values)
    }

    public static func fallback(_ reason: AgentorFallbackReason) -> AgentorResponse {
        AgentorResponse(kind: .nativeFallback, fallbackReason: reason)
    }

    public static func rejected(_ code: String) -> AgentorResponse {
        AgentorResponse(kind: .rejected, rejectionCode: code)
    }
}

public enum AgentorValidationError: String, Error, Codable, Sendable, Equatable {
    case protocolMismatch
    case invalidEnvelope
    case invalidIdentifier
    case invalidQuestionCount
    case invalidOptionCount
    case duplicateAnswerKey
    case invalidQuestionShape
    case frameTooLarge
    case malformedFrame
}

public enum AgentorFrameCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let payload = try JSONEncoder.agentor.encode(value)
        guard payload.count <= AgentorContract.maximumFrameBytes else { throw AgentorValidationError.frameTooLarge }
        var length = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        frame.append(payload)
        return frame
    }

    public static func decode<T: Decodable>(_ type: T.Type, from frame: Data) throws -> T {
        guard frame.count >= 4 else { throw AgentorValidationError.malformedFrame }
        let length = frame.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= AgentorContract.maximumFrameBytes else { throw AgentorValidationError.frameTooLarge }
        guard frame.count == 4 + Int(length) else { throw AgentorValidationError.malformedFrame }
        do { return try JSONDecoder.agentor.decode(type, from: frame.dropFirst(4)) }
        catch { throw AgentorValidationError.malformedFrame }
    }
}

public enum AgentorPaths {
    public static func socketURL(
        applicationSupportDirectory: URL? = nil
    ) -> URL {
        let root = applicationSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root
            .appendingPathComponent("com.scpz24.Peeker", isDirectory: true)
            .appendingPathComponent("agentor-v1.sock")
    }
}

public extension JSONEncoder {
    static var agentor: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var agentor: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
