import Foundation

public enum PeekerContract {
    public static let schemaVersion = 1
    public static let protocolVersion = 1
    public static let appVersion = "2.0.1"
    public static let maximumFrameBytes = 16 * 1_024 * 1_024
}

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

public struct PeekerWarning: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let details: [String: JSONValue]?

    public init(code: String, message: String, details: [String: JSONValue]? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }
}

public struct PeekerError: Error, Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let details: [String: JSONValue]?

    public init(code: String, message: String, details: [String: JSONValue]? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }

    public var exitCode: Int32 {
        switch code {
        case "invalid_usage", "validation_error",
             "timer_invalid_duration", "timer_invalid_color",
             "pusher_invalid_title", "pusher_invalid_urgency", "pusher_invalid_status",
             "scheduler_invalid_title", "scheduler_invalid_time_range", "scheduler_invalid_recurrence": 2
        case "app_not_running", "ipc_unavailable", "ipc_timeout": 3
        case "not_found", "ambiguous_selector", "timer_target_not_found",
             "pusher_target_not_found", "scheduler_occurrence_not_found", "scheduler_source_not_found": 4
        case "conflict", "card_enablement_conflict", "timer_already_running", "timer_no_active_task",
             "timer_task_completed", "pusher_target_wrong_column", "scheduler_scope_required",
             "scheduler_scope_not_allowed", "scheduler_source_path_conflict": 5
        case "protocol_mismatch": 7
        default: 6
        }
    }
}

public struct PeekerEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let ok: Bool
    public let data: JSONValue?
    public let warnings: [PeekerWarning]?
    public let error: PeekerError?

    public static func success(
        _ data: JSONValue = .object([:]),
        warnings: [PeekerWarning] = []
    ) -> PeekerEnvelope {
        PeekerEnvelope(
            schemaVersion: PeekerContract.schemaVersion,
            ok: true,
            data: data,
            warnings: warnings.isEmpty ? nil : warnings,
            error: nil
        )
    }

    public static func failure(_ error: PeekerError) -> PeekerEnvelope {
        PeekerEnvelope(
            schemaVersion: PeekerContract.schemaVersion,
            ok: false,
            data: nil,
            warnings: nil,
            error: error
        )
    }
}

public enum CommandCategory: String, Codable, Sendable {
    case read
    case mutation
}

public struct CommandInvocation: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let featureID: String
    public let arguments: [String]
    public let category: CommandCategory

    public init(
        requestID: UUID = UUID(),
        featureID: String,
        arguments: [String],
        category: CommandCategory
    ) {
        self.requestID = requestID
        self.featureID = featureID
        self.arguments = arguments
        self.category = category
    }
}

public struct ProtocolHandshake: Codable, Equatable, Sendable {
    public let protocolVersion: Int

    public init(protocolVersion: Int = PeekerContract.protocolVersion) {
        self.protocolVersion = protocolVersion
    }
}

public enum IPCRequest: Codable, Equatable, Sendable {
    case handshake(ProtocolHandshake)
    case status
    case command(CommandInvocation)
}

public struct IPCResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let envelope: PeekerEnvelope

    public init(
        protocolVersion: Int = PeekerContract.protocolVersion,
        envelope: PeekerEnvelope
    ) {
        self.protocolVersion = protocolVersion
        self.envelope = envelope
    }
}
